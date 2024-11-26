// scripts/deploy.js
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Using price feed address:", process.env.PRICE_FEED_ADDRESS);
  console.log("Using fee collector address:", process.env.FEE_COLLECTOR_ADDRESS);
  console.log("Using liquidity collector address:", process.env.LIQUIDITY_COLLECTOR_ADDRESS);
  console.log("Using BEX DEX address:", process.env.BEX_DEX_ADDRESS);

  // Verify required environment variables
  if (!process.env.PRICE_FEED_ADDRESS) {
    throw new Error("PRICE_FEED_ADDRESS not set in environment");
  }
  if (!process.env.FEE_COLLECTOR_ADDRESS) {
    throw new Error("FEE_COLLECTOR_ADDRESS not set in environment");
  }
  if (!process.env.LIQUIDITY_COLLECTOR_ADDRESS) {
    throw new Error("LIQUIDITY_COLLECTOR_ADDRESS not set in environment");
  }
  if (!process.env.BEX_DEX_ADDRESS) {
    throw new Error("BEX_DEX_ADDRESS not set in environment");
  }

  // Deploy BexLiquidityManager first with BEX DEX address
  console.log("Deploying BexLiquidityManager...");
  const BexLiquidityManager = await hre.ethers.getContractFactory("BexLiquidityManager");
  const bexLiquidityManager = await BexLiquidityManager.deploy(
    process.env.BEX_DEX_ADDRESS  // Only needs BEX DEX address
  );
  await bexLiquidityManager.waitForDeployment();
  const bexLiquidityManagerAddress = await bexLiquidityManager.getAddress();
  console.log("BexLiquidityManager deployed to:", bexLiquidityManagerAddress);

  // Deploy TokenFactory with updated parameters
  console.log("Deploying TokenFactory...");
  const TokenFactory = await hre.ethers.getContractFactory("TokenFactory");
  const tokenFactory = await TokenFactory.deploy(
    process.env.FEE_COLLECTOR_ADDRESS,
    bexLiquidityManagerAddress,
    process.env.LIQUIDITY_COLLECTOR_ADDRESS
  );

  await tokenFactory.waitForDeployment();
  const tokenFactoryAddress = await tokenFactory.getAddress();
  console.log("TokenFactory deployed to:", tokenFactoryAddress);

  // Save deployment info
  const fs = require('fs');
  const deploymentInfo = {
    tokenFactoryAddress,
    bexLiquidityManagerAddress,
    bexDexAddress: process.env.BEX_DEX_ADDRESS,
    priceFeedAddress: process.env.PRICE_FEED_ADDRESS,
    feeCollectorAddress: process.env.FEE_COLLECTOR_ADDRESS,
    liquidityCollectorAddress: process.env.LIQUIDITY_COLLECTOR_ADDRESS,
    timestamp: new Date().toISOString()
  };
  
  fs.writeFileSync(
    'factory-deployment-info.json', 
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("Deployment info saved to factory-deployment-info.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });