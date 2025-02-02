const { expect } = require("chai");
const { ethers } = require("hardhat");
require("dotenv").config();

// Add address validation
function validateAddress(address, name) {
    if (!ethers.isAddress(address)) {
        throw new Error(`Invalid ${name} address: ${address}`);
    }
    return address;
}

describe("Deployed Bonding Curve Tests", function () {
  // Load addresses from deployment-info.json if it exists
  let deploymentInfo;
  try {
    deploymentInfo = require('../deployment-info.json');
  } catch {
    console.log("No deployment-info.json found, using environment variables");
  }

  const DEPLOYED_TOKEN_ADDRESS = validateAddress(
    deploymentInfo?.tokenAddress || process.env.DEPLOYED_TOKEN_ADDRESS,
    "Token"
  );
  const DEPLOYED_BONDING_CURVE = validateAddress(
    deploymentInfo?.bondingCurveAddress || process.env.DEPLOYED_BONDING_CURVE,
    "Bonding Curve"
  );
  let bondingCurve, token, signer;

  before(async function () {
    console.log("=== Test Setup ===");
    const provider = new ethers.JsonRpcProvider(process.env.BERACHAIN_RPC_URL);
    signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    console.log("Testing with address:", await signer.getAddress());
    console.log("Token address:", DEPLOYED_TOKEN_ADDRESS);
    console.log("Bonding curve address:", DEPLOYED_BONDING_CURVE);
    
    const BondingCurve = await ethers.getContractFactory("BondingCurve");
    const Token = await ethers.getContractFactory("CustomERC20");
    
    bondingCurve = BondingCurve.attach(DEPLOYED_BONDING_CURVE).connect(signer);
    token = Token.attach(DEPLOYED_TOKEN_ADDRESS).connect(signer);
    
    console.log("Contracts attached successfully");

    // Get and log current BERA price
    const beraPrice = await bondingCurve.getBeraPrice();
    console.log("Current BERA price:", ethers.formatEther(beraPrice), "USD");
  });

  describe("Token Operations", function () {
    it("Should buy tokens with 0.001 BERA", async function () {
      console.log("\n=== Buy Tokens Test ===");
      const buyAmount = ethers.parseEther("0.001");
      const beraPrice = await bondingCurve.getBeraPrice();
      const currentPrice = await bondingCurve.getCurrentPrice();
      
      // Calculate expected tokens using BigInt arithmetic
      const beraValueUSD = (buyAmount * beraPrice) / BigInt(ethers.parseEther("1"));
      const expectedTokens = (beraValueUSD * BigInt(1e6)) / currentPrice;
      
      console.log("Buy calculation:", {
          beraAmount: ethers.formatEther(buyAmount),
          beraPrice: ethers.formatEther(beraPrice),
          tokenPrice: ethers.formatUnits(currentPrice, 6),
          expectedTokens: ethers.formatEther(expectedTokens)
      });
      
      // Get initial balances and state
      const initialTokenBalance = await token.balanceOf(signer.address);
      const initialBERABalance = await ethers.provider.getBalance(signer.address);
      const initialTotalSupply = await bondingCurve.totalSupplyTokens();
      
      console.log("Initial token balance:", ethers.formatEther(initialTokenBalance));
      console.log("Initial BERA balance:", ethers.formatEther(initialBERABalance));
      console.log("Initial total supply:", ethers.formatEther(initialTotalSupply));

      try {
        console.log("Sending", ethers.formatEther(buyAmount), "BERA to buy tokens");
        
        // Execute purchase with minimum tokens of 1 wei
        const tx = await bondingCurve.buyTokens(1, { value: buyAmount });
        const receipt = await tx.wait();
        
        // Get final balances
        const finalTokenBalance = await token.balanceOf(signer.address);
        const finalBERABalance = await ethers.provider.getBalance(signer.address);
        const finalTotalSupply = await bondingCurve.totalSupplyTokens();

        // Calculate changes
        const tokensReceived = finalTokenBalance - initialTokenBalance;
        const beraSpent = initialBERABalance - finalBERABalance;
        const supplyChange = initialTotalSupply - finalTotalSupply;
        
        console.log("Tokens received:", ethers.formatEther(tokensReceived));
        console.log("BERA spent:", ethers.formatEther(beraSpent));
        console.log("Supply change:", ethers.formatEther(supplyChange));
        console.log("Transaction hash:", receipt.hash);

        // Verify the purchase event
        const event = receipt.logs.find(
          log => {
            try {
              return bondingCurve.interface.parseLog(log)?.name === "TokensPurchased";
            } catch {
              return false;
            }
          }
        );
        expect(event).to.not.be.undefined;
        
        const parsedEvent = bondingCurve.interface.parseLog(event);
        expect(parsedEvent.args.buyer).to.equal(signer.address);
      } catch (error) {
        console.log("Error buying tokens:", error.reason || error);
        throw error;
      }
    });

    it("Should sell received tokens", async function () {
      console.log("\n=== Sell Tokens Test ===");
      
      try {
        // Get initial balances and state
        const initialTokenBalance = await token.balanceOf(signer.address);
        const initialBERABalance = await ethers.provider.getBalance(signer.address);
        const initialTotalSupply = await bondingCurve.totalSupplyTokens();
        
        console.log("Initial token balance:", ethers.formatEther(initialTokenBalance));
        console.log("Initial BERA balance:", ethers.formatEther(initialBERABalance));
        console.log("Initial total supply:", ethers.formatEther(initialTotalSupply));

        if (initialTokenBalance === 0n) {
          console.log("No tokens to sell, skipping test");
          return;
        }

        // Sell 10% of our tokens
        const tokensToSell = initialTokenBalance / 10n;
        
        // Get expected BERA return before sale
        const expectedBERA = await bondingCurve.getSellPrice(tokensToSell);
        console.log("Selling tokens:", ethers.formatEther(tokensToSell));
        console.log("Expected BERA return:", ethers.formatEther(expectedBERA));

        // Approve and sell
        const approveTx = await token.approve(DEPLOYED_BONDING_CURVE, tokensToSell);
        await approveTx.wait();
        
        const tx = await bondingCurve.sellTokens(tokensToSell);
        const receipt = await tx.wait();
        
        // Get final balances
        const finalTokenBalance = await token.balanceOf(signer.address);
        const finalBERABalance = await ethers.provider.getBalance(signer.address);
        const finalTotalSupply = await bondingCurve.totalSupplyTokens();

        // Calculate changes
        const tokensSpent = initialTokenBalance - finalTokenBalance;
        const beraReceived = finalBERABalance - initialBERABalance;
        const supplyChange = finalTotalSupply - initialTotalSupply;

        console.log("Tokens spent:", ethers.formatEther(tokensSpent));
        console.log("BERA received:", ethers.formatEther(beraReceived));
        console.log("Supply change:", ethers.formatEther(supplyChange));
        console.log("Transaction hash:", receipt.hash);

        // Verify the sell event
        const event = receipt.logs.find(
          log => {
            try {
              return bondingCurve.interface.parseLog(log)?.name === "TokensSold";
            } catch {
              return false;
            }
          }
        );
        expect(event).to.not.be.undefined;
        
        const parsedEvent = bondingCurve.interface.parseLog(event);
        expect(parsedEvent.args.seller).to.equal(signer.address);
      } catch (error) {
        console.log("Error selling tokens:", error.reason || error);
        throw error;
      }
    });
  });

  describe("Price Feed and Market Cap", function () {
    it("Should show current market metrics", async function () {
      console.log("\n=== Market Metrics ===");
      
      const beraPrice = await bondingCurve.getBeraPrice();
      const currentPrice = await bondingCurve.getCurrentPrice();
      const totalSupply = await bondingCurve.totalSupplyTokens();
      const soldTokens = ethers.parseEther("1000000000") - totalSupply;
      
      console.log("Market metrics:", {
          beraPrice: ethers.formatEther(beraPrice),
          tokenPrice: ethers.formatUnits(currentPrice, 6),
          remainingSupply: ethers.formatEther(totalSupply),
          soldTokens: ethers.formatEther(soldTokens)
      });
      
      expect(currentPrice).to.be.gt(0n); // Convert to BigInt comparison
    });
  });

  describe("Fee Collector", function () {
    it("Should verify fee collector address and accumulated fees", async function () {
      console.log("\n=== Fee Collector Test ===");
      
      const feeCollectorAddress = await bondingCurve.feeCollector();
      const feeCollectorBalance = await ethers.provider.getBalance(feeCollectorAddress);
      
      console.log("Fee Collector Address:", feeCollectorAddress);
      console.log("Accumulated Fees:", ethers.formatEther(feeCollectorBalance), "BERA");
    });
  });
}); 