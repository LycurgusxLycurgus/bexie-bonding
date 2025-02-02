// test/TokenFactory.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContractAddress, validateAddress } = require("./helpers/addressUtils");

describe("TokenFactory", function() {
    let tokenFactory;
    let owner;
    let user;
    let feeCollector;
    let liquidityManager;
    let liquidityCollector;
    let mockPriceFeed;

    const DECIMALS = 8;
    const INITIAL_PRICE = ethers.parseUnits("2000", 8); // $2000 with 8 decimals

    beforeEach(async function() {
        [owner, user, feeCollector, liquidityManager, liquidityCollector] = await ethers.getSigners();

        // Deploy mock price feed
        const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
        mockPriceFeed = await MockV3Aggregator.deploy(DECIMALS, INITIAL_PRICE);
        const mockAddress = validateAddress(await getContractAddress(mockPriceFeed));

        // Deploy TokenFactory
        const TokenFactory = await ethers.getContractFactory("TokenFactory");
        tokenFactory = await TokenFactory.deploy(
            validateAddress(feeCollector.address),
            validateAddress(liquidityManager.address),
            validateAddress(liquidityCollector.address)
        );
        const factoryAddress = validateAddress(await getContractAddress(tokenFactory));

        // Verify deployments
        expect(await mockPriceFeed.decimals()).to.equal(DECIMALS);
        expect(await tokenFactory.owner()).to.equal(owner.address);
    });

    describe("Constructor", function() {
        it("should initialize with correct parameters", async function() {
            expect(await tokenFactory.feeCollector()).to.equal(feeCollector.address);
            expect(await tokenFactory.liquidityManager()).to.equal(liquidityManager.address);
            expect(await tokenFactory.liquidityCollector()).to.equal(liquidityCollector.address);
            expect(await tokenFactory.creationFee()).to.equal(ethers.parseEther("0.002"));
            expect(await tokenFactory.owner()).to.equal(owner.address);
        });
    });

    describe("Token Creation", function() {
        const tokenName = "Test Token";
        const tokenSymbol = "TEST";
        const initialSupply = 1000;

        it("should revert if creation fee is not paid", async function() {
            await expect(
                tokenFactory.createToken(
                    tokenName,
                    tokenSymbol,
                    initialSupply,
                    mockPriceFeed
                )
            ).to.be.revertedWith("Insufficient creation fee");
        });

        it("should create token and bonding curve with correct parameters", async function() {
            const creationFee = await tokenFactory.creationFee();
            
            const tx = await tokenFactory.createToken(
                tokenName,
                tokenSymbol,
                initialSupply,
                mockPriceFeed,
                { value: creationFee }
            );

            const receipt = await tx.wait();
            const event = receipt.logs.find(
                log => {
                    try {
                        return tokenFactory.interface.parseLog(log)?.name === "TokenCreated";
                    } catch {
                        return false;
                    }
                }
            );
            expect(event).to.not.be.undefined;

            const parsedEvent = tokenFactory.interface.parseLog(event);
            const tokenAddress = parsedEvent.args[1];
            const bondingCurveAddress = parsedEvent.args[2];

            // Verify token
            const token = await ethers.getContractAt("CustomERC20", tokenAddress);
            expect(await token.name()).to.equal(tokenName);
            expect(await token.symbol()).to.equal(tokenSymbol);
            expect(await token.owner()).to.equal(bondingCurveAddress);

            // Verify bonding curve
            const bondingCurve = await ethers.getContractAt("BondingCurve", bondingCurveAddress);
            expect(await bondingCurve.token()).to.equal(tokenAddress);
            expect(await bondingCurve.feeCollector()).to.equal(feeCollector.address);
            expect(await bondingCurve.liquidityManager()).to.equal(liquidityManager.address);
            expect(await bondingCurve.liquidityCollector()).to.equal(liquidityCollector.address);
        });

        it("should transfer creation fee to fee collector", async function() {
            const creationFee = await tokenFactory.creationFee();
            const initialBalance = await ethers.provider.getBalance(feeCollector.address);

            await tokenFactory.createToken(
                tokenName,
                tokenSymbol,
                initialSupply,
                mockPriceFeed,
                { value: creationFee }
            );

            const finalBalance = await ethers.provider.getBalance(feeCollector.address);
            expect(finalBalance - initialBalance).to.equal(creationFee);
        });
    });

    describe("Admin Functions", function() {
        it("should allow owner to update creation fee", async function() {
            const newFee = ethers.parseEther("0.003");
            await tokenFactory.setCreationFee(newFee);
            expect(await tokenFactory.creationFee()).to.equal(newFee);
        });

        it("should allow owner to update fee collector", async function() {
            const newCollector = user.address;
            await tokenFactory.setFeeCollector(newCollector);
            expect(await tokenFactory.feeCollector()).to.equal(newCollector);
        });

        it("should allow owner to update liquidity manager", async function() {
            const newManager = user.address;
            await tokenFactory.setLiquidityManager(newManager);
            expect(await tokenFactory.liquidityManager()).to.equal(newManager);
        });

        it("should revert admin functions when called by non-owner", async function() {
            await expect(
                tokenFactory.connect(user).setCreationFee(ethers.parseEther("0.003"))
            ).to.be.revertedWithCustomError(tokenFactory, "OwnableUnauthorizedAccount")
            .withArgs(user.address);

            await expect(
                tokenFactory.connect(user).setFeeCollector(user.address)
            ).to.be.revertedWithCustomError(tokenFactory, "OwnableUnauthorizedAccount")
            .withArgs(user.address);

            await expect(
                tokenFactory.connect(user).setLiquidityManager(user.address)
            ).to.be.revertedWithCustomError(tokenFactory, "OwnableUnauthorizedAccount")
            .withArgs(user.address);
        });
    });
});
