// scripts/deploy.js
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Using price feed address:", process.env.PRICE_FEED_ADDRESS);
  console.log("Using fee collector address:", process.env.FEE_COLLECTOR_ADDRESS);

  // Verify required environment variables
  if (!process.env.PRICE_FEED_ADDRESS) {
    throw new Error("PRICE_FEED_ADDRESS not set in environment");
  }
  if (!process.env.FEE_COLLECTOR_ADDRESS) {
    throw new Error("FEE_COLLECTOR_ADDRESS not set in environment");
  }

  // Deploy TokenFactory
  const TokenFactory = await hre.ethers.getContractFactory("TokenFactory");
  const tokenFactory = await TokenFactory.deploy(process.env.FEE_COLLECTOR_ADDRESS);

  // Wait for the contract to be deployed
  await tokenFactory.waitForDeployment();

  // Get the deployed contract address
  const tokenFactoryAddress = await tokenFactory.getAddress();

  console.log("TokenFactory deployed to:", tokenFactoryAddress);

  // Save deployment info
  const fs = require('fs');
  const deploymentInfo = {
    tokenFactoryAddress,
    priceFeedAddress: process.env.PRICE_FEED_ADDRESS,
    feeCollectorAddress: process.env.FEE_COLLECTOR_ADDRESS,
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