// scripts/deploy.js
const hre = require("hardhat");
const { ethers } = require("hardhat");
require("dotenv").config();

// Simple address validation
function validateAddress(address, name) {
    if (!ethers.isAddress(address)) {
        throw new Error(`Invalid ${name} address: ${address}`);
    }
    return address;
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    // Validate BEX DEX address first
    if (!process.env.BEX_DEX_ADDRESS) {
        throw new Error("BEX_DEX_ADDRESS not set in environment");
    }

    try {
        // Deploy BexLiquidityManager with proper constructor argument
        console.log("Deploying BexLiquidityManager...");
        const BexLiquidityManager = await hre.ethers.getContractFactory("BexLiquidityManager");
        const bexLiquidityManager = await BexLiquidityManager.deploy(process.env.BEX_DEX_ADDRESS);
        
        // Wait for deployment and get address
        const bexLiquidityManagerAddress = await bexLiquidityManager.getAddress();
        console.log("BexLiquidityManager deployed to:", bexLiquidityManagerAddress);

        // Deploy TokenFactory
        console.log("Deploying TokenFactory...");
        const TokenFactory = await hre.ethers.getContractFactory("TokenFactory");
        const tokenFactory = await TokenFactory.deploy(
            process.env.FEE_COLLECTOR_ADDRESS,
            bexLiquidityManagerAddress,
            process.env.LIQUIDITY_COLLECTOR_ADDRESS
        );

        const tokenFactoryAddress = await tokenFactory.getAddress();
        console.log("TokenFactory deployed to:", tokenFactoryAddress);

        // Save deployment info
        const deploymentInfo = {
            tokenFactoryAddress,
            bexLiquidityManagerAddress,
            bexDexAddress: process.env.BEX_DEX_ADDRESS,
            priceFeedAddress: process.env.PRICE_FEED_ADDRESS,
            feeCollectorAddress: process.env.FEE_COLLECTOR_ADDRESS,
            liquidityCollectorAddress: process.env.LIQUIDITY_COLLECTOR_ADDRESS,
            timestamp: new Date().toISOString()
        };

        require('fs').writeFileSync(
            'factory-deployment-info.json', 
            JSON.stringify(deploymentInfo, null, 2)
        );
        console.log("Deployment info saved to factory-deployment-info.json");

    } catch (error) {
        console.error("Deployment failed with error:", error);
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });