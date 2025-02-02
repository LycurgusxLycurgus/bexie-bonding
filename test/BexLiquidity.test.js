const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("BEX Liquidity Deployment", function () {
    let tokenFactory;
    let bexLiquidityManager;
    let token;
    let bondingCurve;
    let owner;
    let feeCollector;
    let liquidityCollector;
    let priceFeed;
    let mockBexDex;

    // Test constants
    const INITIAL_SUPPLY = 1000000000; // 1 billion tokens
    const TARGET_MARKET_CAP = ethers.parseEther("69420"); // $69,420
    const LIQUIDITY_AMOUNT = ethers.parseEther("6942"); // $6,942
    const BERA_PRICE = ethers.parseEther("10"); // $10 per BERA

    beforeEach(async function () {
        // Get signers
        [owner, feeCollector, liquidityCollector] = await ethers.getSigners();

        // Fund accounts with large amounts of BERA
        for (const account of [owner, feeCollector, liquidityCollector]) {
            await ethers.provider.send("hardhat_setBalance", [
                account.address,
                ethers.toBeHex(ethers.parseEther("1000000"))
            ]);
        }

        // Deploy mock price feed
        const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
        priceFeed = await MockPriceFeed.deploy(BERA_PRICE);
        await priceFeed.waitForDeployment();

        // Deploy mock BEX DEX
        const MockBexDex = await ethers.getContractFactory("MockBexDex");
        mockBexDex = await MockBexDex.deploy();
        await mockBexDex.waitForDeployment();

        // Deploy BexLiquidityManager with mock BEX DEX
        const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
        bexLiquidityManager = await BexLiquidityManager.deploy(await mockBexDex.getAddress());
        await bexLiquidityManager.waitForDeployment();

        // Deploy TokenFactory
        const TokenFactory = await ethers.getContractFactory("TokenFactory");
        tokenFactory = await TokenFactory.deploy(
            feeCollector.address,
            await bexLiquidityManager.getAddress(),
            liquidityCollector.address
        );
        await tokenFactory.waitForDeployment();

        // Create a new token
        const tx = await tokenFactory.createToken(
            "Test Token",
            "TEST",
            INITIAL_SUPPLY,
            await priceFeed.getAddress(),
            { value: ethers.parseEther("0.02") } // Creation fee
        );
        const receipt = await tx.wait();

        // Get token and bonding curve addresses from event
        const event = receipt.logs.find(
            log => {
                try {
                    const decoded = tokenFactory.interface.parseLog(log);
                    return decoded.name === "TokenCreated";
                } catch (e) {
                    return false;
                }
            }
        );
        const decodedEvent = tokenFactory.interface.parseLog(event);
        token = await ethers.getContractAt("CustomERC20", decodedEvent.args.tokenAddress);
        bondingCurve = await ethers.getContractAt("BondingCurve", decodedEvent.args.bondingCurveAddress);

        // Transfer BexLiquidityManager ownership to bonding curve
        await bexLiquidityManager.transferOwnership(await bondingCurve.getAddress());

        // Fund the bonding curve with BERA (enough for liquidity deployment)
        await owner.sendTransaction({
            to: await bondingCurve.getAddress(),
            value: ethers.parseEther("100000") // Much more than needed
        });
    });

    describe("Liquidity Deployment Tests", function () {
        it("Should deploy liquidity to BEX when target market cap is reached", async function () {
            console.log("=== Testing Liquidity Deployment ===");
            
            // Buy enough tokens to reach target market cap (6942 BERA at $10 = $69,420)
            const buyAmount = ethers.parseEther("7000");
            console.log("Buying tokens with", ethers.formatEther(buyAmount), "BERA");
            
            const initialCollectorBalance = await ethers.provider.getBalance(liquidityCollector.address);
            
            await bondingCurve.connect(owner).buyTokens(0, { value: buyAmount });
            
            const marketCap = await bondingCurve.currentMarketCapUSD();
            console.log("Current Market Cap:", ethers.formatEther(marketCap), "USD");
            
            const collectedBera = await bondingCurve.collectedBeraUSD();
            console.log("Collected BERA:", ethers.formatEther(collectedBera), "USD");

            // Wait for a block to ensure all state changes are processed
            await ethers.provider.send("evm_mine", []);

            // Verify liquidity deployment
            expect(await bondingCurve.targetReached()).to.be.true;
            expect(await bondingCurve.liquidityDeployed()).to.be.true;

            // Check BEX liquidity pool
            const bexLiquidity = await mockBexDex.getLiquidity(
                await token.getAddress(),
                ethers.ZeroAddress
            );
            console.log("BEX Liquidity Pool:", ethers.formatEther(bexLiquidity), "BERA");
            expect(bexLiquidity).to.be.gt(0);

            // Check liquidity collector balance
            const finalCollectorBalance = await ethers.provider.getBalance(liquidityCollector.address);
            expect(finalCollectorBalance).to.be.gt(initialCollectorBalance);
            console.log("Liquidity Collector Balance Change:", 
                ethers.formatEther(finalCollectorBalance - initialCollectorBalance), "BERA");
        });

        it("Should not deploy liquidity before target market cap", async function () {
            console.log("=== Testing Pre-Target Behavior ===");
            
            // Buy small amount of tokens
            const buyAmount = ethers.parseEther("100"); // 100 BERA = $1,000
            console.log("Buying tokens with", ethers.formatEther(buyAmount), "BERA");
            
            const initialCollectorBalance = await ethers.provider.getBalance(liquidityCollector.address);
            
            await bondingCurve.connect(owner).buyTokens(0, { value: buyAmount });
            
            const marketCap = await bondingCurve.currentMarketCapUSD();
            console.log("Current Market Cap:", ethers.formatEther(marketCap), "USD");
            
            // Wait for a block to ensure all state changes are processed
            await ethers.provider.send("evm_mine", []);

            // Verify no liquidity deployment
            expect(await bondingCurve.targetReached()).to.be.false;
            expect(await bondingCurve.liquidityDeployed()).to.be.false;

            // Check liquidity collector balance hasn't changed
            const finalCollectorBalance = await ethers.provider.getBalance(liquidityCollector.address);
            expect(finalCollectorBalance).to.equal(initialCollectorBalance);
        });

        it("Should handle errors gracefully during liquidity deployment", async function () {
            console.log("=== Testing Error Handling ===");
            
            // Deploy faulty mock BEX DEX
            const MockFailingBexDex = await ethers.getContractFactory("MockFailingBexDex");
            const failingBexDex = await MockFailingBexDex.deploy();

            // Create new BexLiquidityManager with failing DEX
            const BexLiquidityManager = await ethers.getContractFactory("BexLiquidityManager");
            const failingManager = await BexLiquidityManager.deploy(await failingBexDex.getAddress());

            // Approve tokens for failing manager
            await token.approve(await failingManager.getAddress(), ethers.parseEther("1000"));
            
            // Try to deploy liquidity
            const tx = failingManager.deployLiquidity(
                await token.getAddress(),
                ethers.parseEther("1000"),
                liquidityCollector.address,
                { value: ethers.parseEther("1") }
            );
            
            await expect(tx).to.be.reverted;
            
            console.log("Error handling test passed");
        });
    });
}); 