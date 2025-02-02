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

describe("Deployed Contracts Tests", function () {
  // Set deployed contract address
  const DEPLOYED_TOKEN_FACTORY = validateAddress("0x547290255f50f524e0dCe4eF00E18DC60911336A", "Token Factory");
  // Using Berachain's BERA/USD price feed address (you'll need to replace this with the actual address)
  const PRICE_FEED_ADDRESS = validateAddress(process.env.PRICE_FEED_ADDRESS, "Price Feed");
  
  let tokenFactory, signer, provider;
  // Update creation fee to match contract
  const creationFee = ethers.parseEther("0.002");
  const extraPurchase = ethers.parseEther("0.002"); // Extra BERA for initial purchase
  const totalValue = creationFee + extraPurchase;

  before(async function () {
    provider = new ethers.JsonRpcProvider(process.env.BERACHAIN_RPC_URL);
    signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    console.log("Testing with address:", await signer.getAddress());
    console.log("Using price feed address:", PRICE_FEED_ADDRESS);
    
    // Attach to the deployed TokenFactory and connect with signer
    const TokenFactory = await ethers.getContractFactory("TokenFactory");
    tokenFactory = TokenFactory.attach(DEPLOYED_TOKEN_FACTORY).connect(signer);

    // Verify contract exists
    const code = await provider.getCode(DEPLOYED_TOKEN_FACTORY);
    if (code === "0x") throw new Error("TokenFactory not deployed at specified address");
  });

  it("Should create a token and make initial purchase through deployed factory", async function () {
    const signerAddress = await signer.getAddress();
    console.log("Creating token with address:", signerAddress);
    console.log("Total value sent:", ethers.formatEther(totalValue), "BERA");
    console.log("- Creation fee:", ethers.formatEther(creationFee), "BERA");
    console.log("- Initial purchase:", ethers.formatEther(extraPurchase), "BERA");

    const tx = await tokenFactory.createToken(
      "TestTokenBillion", 
      "TTKb", 
      1000000000,
      PRICE_FEED_ADDRESS,
      { value: totalValue }
    );
    
    console.log("Transaction hash:", tx.hash);
    const receipt = await tx.wait();

    // Find TokenCreated event
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
    const [creator, tokenAddress, bondingCurveAddress, name, symbol] = parsedEvent.args;
    
    console.log("New Token Address:", tokenAddress);
    console.log("New Bonding Curve Address:", bondingCurveAddress);
    console.log("Token Name:", name);
    console.log("Token Symbol:", symbol);

    // Verify basic token creation details
    expect(creator).to.equal(signerAddress);
    expect(name).to.equal("TestTokenBillion");
    expect(symbol).to.equal("TTKb");

    // Verify initial token purchase
    // Use standard ERC20 ABI for reading balance
    const erc20Abi = [
      "function balanceOf(address) view returns (uint256)",
      "function decimals() view returns (uint8)",
      "function symbol() view returns (string)"
    ];
    const token = new ethers.Contract(tokenAddress, erc20Abi, provider);
    
    // Add verification of token address
    console.log("Verifying token at address:", tokenAddress);
    const code = await provider.getCode(tokenAddress);
    if (code === "0x") throw new Error("Token contract not deployed at specified address");
    
    // Keep the delay since blockchain state needs time to update
    console.log("Waiting 30 seconds for blockchain state update...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    const balance = await token.balanceOf(signerAddress);
    
    console.log("Initial token balance:", ethers.formatUnits(balance, 18));
    expect(balance).to.be.gt(0, "Creator should have received tokens from initial purchase");

    // Save deployment info
    const deploymentInfo = {
      tokenAddress: validateAddress(tokenAddress, "Created Token"),
      bondingCurveAddress: validateAddress(bondingCurveAddress, "Bonding Curve"),
      initialBalance: balance.toString(),
      timestamp: new Date().toISOString()
    };
    
    const fs = require('fs');
    fs.writeFileSync(
      'deployment-info.json', 
      JSON.stringify(deploymentInfo, null, 2)
    );
    console.log("Deployment info saved to deployment-info.json");
  });
}); 