const { expect } = require("chai");
const { ethers } = require("hardhat");

// Helper: validate that an address is correctly formatted.
function validateAddress(address, name) {
  if (!ethers.isAddress(address)) {
    throw new Error(`Invalid ${name} address: ${address}`);
  }
  return address;
}

// Define constants as BigInts using ethers.parseEther
const TOTAL_TOKENS = ethers.parseEther("1000000000"); // 1B tokens (as BigInt)
const TOKEN_SOLD_THRESHOLD = ethers.parseEther("800000000"); // 800M tokens (as BigInt)

describe("BondingCurve Price Scaling Tests", function () {
  let TokenFactory, tokenFactory, owner, addr1, feeCollector, token, bondingCurve, mockPriceFeed;
  let liquidityManager, liquidityCollector;
  const creationFee = ethers.parseEther("0.002");

  // Helper functions for logging
  const getTimestamp = () => new Date().toISOString();
  const logSection = (sectionName) => {
    console.log("\n=== " + sectionName + " [" + getTimestamp() + "] ===");
  };

  beforeEach(async function () {
    try {
      logSection("Test Setup");
      [owner, addr1, feeCollector, liquidityCollector] = await ethers.getSigners();
      console.log("Test accounts loaded:", {
        owner: owner.address,
        addr1: addr1.address,
        feeCollector: feeCollector.address,
        liquidityCollector: liquidityCollector.address,
      });

      // Deploy mock price feed with $3,000 BERA price (8 decimals, initialAnswer scaled accordingly)
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      mockPriceFeed = await MockV3Aggregator.deploy(8, 300000000000);
      const mockPriceFeedAddress = validateAddress(
        await mockPriceFeed.getAddress(),
        "MockV3Aggregator"
      );

      // Deploy mock DEX and liquidity manager
      const MockBexDex = await ethers.getContractFactory("MockBexDex");
      const mockBexDex = await MockBexDex.deploy();
      const mockBexDexAddress = validateAddress(
        await mockBexDex.getAddress(),
        "MockBexDex"
      );

      const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
      const bexLiquidityManager = await BexLiquidityManager.deploy(mockBexDexAddress);
      const bexLiquidityManagerAddress = validateAddress(
        await bexLiquidityManager.getAddress(),
        "BexLiquidityManager"
      );

      // Deploy token factory and create token using only the creation fee (no extra purchase)
      TokenFactory = await ethers.getContractFactory("TokenFactory");
      tokenFactory = await TokenFactory.deploy(
        feeCollector.address,
        bexLiquidityManagerAddress,
        liquidityCollector.address
      );

      const createTokenTx = await tokenFactory.createToken(
        "Test Token",
        "TEST",
        1000000000,
        mockPriceFeedAddress,
        { value: creationFee }
      );
      const receipt = await createTokenTx.wait();

      // Parse event to get token and bonding curve addresses.
      const event = receipt.logs.find((log) => {
        try {
          return tokenFactory.interface.parseLog(log)?.name === "TokenCreated";
        } catch (e) {
          return false;
        }
      });
      const parsedEvent = tokenFactory.interface.parseLog(event);
      const [creator, tokenAddress, bondingCurveAddress] = parsedEvent.args;

      // Transfer ownership of bexLiquidityManager to bondingCurve (as required).
      await bexLiquidityManager.transferOwnership(bondingCurveAddress);

      const Token = await ethers.getContractFactory("CustomERC20");
      token = Token.attach(validateAddress(tokenAddress, "Token"));

      const BondingCurve = await ethers.getContractFactory("BondingCurve");
      bondingCurve = BondingCurve.attach(validateAddress(bondingCurveAddress, "BondingCurve"));

      // Fund bonding curve with extra BERA (10 ether) for sales and liquidity deployment.
      await owner.sendTransaction({
        to: bondingCurveAddress,
        value: ethers.parseEther("10")
      });
    } catch (error) {
      console.error("Setup failed at " + getTimestamp());
      console.error("Error details:", error);
      throw error;
    }
  });

  it("Should start with correct initial price", async function () {
    const beraPrice = await bondingCurve.getBeraPrice();
    const initialPrice = await bondingCurve.getCurrentPrice();
    console.log("Initial state:", {
      beraPrice: ethers.formatEther(beraPrice),
      tokenPrice: ethers.formatUnits(initialPrice, 6)
    });
    // Expected price = (7 * beraPrice) / (3000 * 1e18) computed using BigInt arithmetic.
    const expectedPrice = (7n * beraPrice) / (3000n * 10n**18n);
    expect(initialPrice).to.be.closeTo(expectedPrice, expectedPrice / 1000n);
  });

  it("Should scale price correctly when buying tokens", async function () {
    const buyAmount = ethers.parseEther("1"); // 1 BERA
    const initialPrice = await bondingCurve.getCurrentPrice();
    await bondingCurve.buyTokens(1, { value: buyAmount });
    const newPrice = await bondingCurve.getCurrentPrice();
    console.log("Price after buy:", {
      initial: (Number(initialPrice) / 1e6).toFixed(6),
      current: (Number(newPrice) / 1e6).toFixed(6)
    });
    expect(newPrice).to.be.gt(initialPrice);
  });

  it("Should reach target price at threshold", async function () {
    const beraPrice = await bondingCurve.getBeraPrice();
    // Execute 7 buys of 1 BERA each.
    for (let i = 0; i < 7; i++) {
      await bondingCurve.buyTokens(1, { value: ethers.parseEther("1") });
    }
    // Compute soldTokens as: TOTAL_TOKENS - totalSupplyTokens.
    const totalSupply = await bondingCurve.totalSupplyTokens();
    const soldTokens = TOTAL_TOKENS - totalSupply;
    console.log("After 7 buys, sold tokens:", ethers.formatEther(soldTokens));
    // Calculate tokensNeeded to reach threshold:
    const tokensNeeded = TOKEN_SOLD_THRESHOLD - soldTokens;
    console.log("Tokens needed to hit threshold:", ethers.formatEther(tokensNeeded));
    const currentPrice = await bondingCurve.getCurrentPrice();
    const beraPriceVal = await bondingCurve.getBeraPrice();
    // Rearranging the contract formula:
    // requiredBera = (tokensNeeded * currentPrice * 1e18) / (PRICE_DECIMALS * beraPrice)
    const requiredBera = (tokensNeeded * currentPrice * 10n**18n) / (1000000n * beraPriceVal);
    console.log("Required extra BERA to hit threshold:", ethers.formatEther(requiredBera));
    // Perform the buy that should reach the threshold.
    await bondingCurve.buyTokens(requiredBera, { value: requiredBera });
    const finalSoldTokens = TOTAL_TOKENS - (await bondingCurve.totalSupplyTokens());
    console.log("Final sold tokens:", ethers.formatEther(finalSoldTokens));
    // Expected final price computed using multiplier 75.
    const finalPrice = await bondingCurve.getCurrentPrice();
    // Adjust tolerance to 2% due to rounding.
    const expectedFinalPrice = (75n * beraPrice) / (3000n * 10n**18n);
    console.log("Final state:", {
      actualPrice: ethers.formatUnits(finalPrice, 6),
      expectedPrice: ethers.formatUnits(expectedFinalPrice, 6)
    });
    expect(finalPrice).to.be.closeTo(expectedFinalPrice, expectedFinalPrice / 50n);
  });

  it("Should deploy liquidity at threshold", async function () {
    // To deploy liquidity, exactly TOKEN_SOLD_THRESHOLD (800M tokens) must be sold.
    // We'll perform 7 buys of 1 BERA each, then compute the extra BERA needed.
    for (let i = 0; i < 7; i++) {
      await bondingCurve.buyTokens(1, { value: ethers.parseEther("1") });
    }
    const totalSupply = await bondingCurve.totalSupplyTokens();
    const soldTokens = TOTAL_TOKENS - totalSupply;
    console.log("After 7 buys, sold tokens:", ethers.formatEther(soldTokens));
    const tokensNeeded = TOKEN_SOLD_THRESHOLD - soldTokens;
    console.log("Tokens needed for liquidity threshold:", ethers.formatEther(tokensNeeded));
    const currentPrice = await bondingCurve.getCurrentPrice();
    const beraPriceVal = await bondingCurve.getBeraPrice();
    const requiredBera = (tokensNeeded * currentPrice * 10n**18n) / (1000000n * beraPriceVal);
    console.log("Required extra BERA to reach liquidity threshold:", ethers.formatEther(requiredBera));
    // Perform the purchase that should trigger liquidity deployment.
    await bondingCurve.buyTokensFor(owner.address, { value: requiredBera });
    const liquidityDeployed = await bondingCurve.liquidityDeployed();
    expect(liquidityDeployed).to.be.true;
  });

  it("Should handle sells correctly", async function () {
    // addr1 buys tokens.
    await bondingCurve.connect(addr1).buyTokens(1, { value: ethers.parseEther("1") });
    const balance = await token.balanceOf(addr1.address);
    const sellAmount = balance / 2n;
    // Approve and sell.
    await token.connect(addr1).approve(bondingCurve.getAddress(), sellAmount);
    await bondingCurve.connect(addr1).sellTokens(sellAmount);
    const newBalance = await token.balanceOf(addr1.address);
    expect(newBalance).to.equal(balance - sellAmount);
  });

  it("Should handle edge cases", async function () {
    await expect(
      bondingCurve.buyTokens(1, { value: 0 })
    ).to.be.revertedWith("Zero BERA amount");
    await expect(
      bondingCurve.sellTokens(0)
    ).to.be.revertedWith("Zero token amount");
    const largeAmount = ethers.parseEther("1000000000") + 1n;
    await expect(
      bondingCurve.sellTokens(largeAmount)
    ).to.be.reverted;
  });
});
