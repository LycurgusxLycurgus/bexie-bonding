# Token Factory & Bonding Curve Usage Examples

## Creating a Token with Initial Purchase

You can create a new token and make an initial purchase in a single transaction. The creation fee (0.002 BERA) is fixed, and any additional BERA sent will be used to purchase tokens from the bonding curve.

### Using Hardhat Console or Scripts

```javascript
// Connect to the deployed factory
const TokenFactory = await ethers.getContractFactory("TokenFactory");
const tokenFactory = TokenFactory.attach("0x547290255f50f524e0dCe4eF00E18DC60911336A");

// Set up the amounts
const creationFee = ethers.parseEther("0.002");
const extraPurchase = ethers.parseEther("0.002"); // Amount for initial token purchase
const totalValue = creationFee + extraPurchase;

// Create token with initial purchase
const tx = await tokenFactory.createToken(
    "My Token",
    "MYT",
    1000000000,           // 1B tokens total supply
    "0x11B714817cBC92D402383cFd3f1037B122dcf69A",  // BERA/USD price feed
    { value: totalValue }
);

// Wait for transaction and get addresses
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

// Get deployed addresses from event
const [creator, tokenAddress, bondingCurveAddress] = tokenFactory.interface.parseLog(event).args;

// Check initial token balance
const erc20Abi = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)"
];
const token = new ethers.Contract(tokenAddress, erc20Abi, provider);
const balance = await token.balanceOf(creator);
console.log("Initial token balance:", ethers.formatUnits(balance, 18));
```

### Using ethers.js in Node.js

```javascript
const { ethers } = require('ethers');
require('dotenv').config();

async function createTokenWithPurchase() {
    const provider = new ethers.JsonRpcProvider(process.env.BERACHAIN_RPC_URL);
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    // Factory ABI (minimal required for createToken)
    const factoryAbi = [
        "function createToken(string,string,uint256,address) payable returns (address)"
    ];
    
    const tokenFactory = new ethers.Contract(
        "0x547290255f50f524e0dCe4eF00E18DC60911336A",
        factoryAbi,
        signer
    );

    const creationFee = ethers.parseEther("0.002");
    const extraPurchase = ethers.parseEther("0.002");
    const totalValue = creationFee + extraPurchase;

    const tx = await tokenFactory.createToken(
        "My Token",
        "MYT",
        1000000000,
        "0x11B714817cBC92D402383cFd3f1037B122dcf69A",
        { value: totalValue }
    );

    console.log("Transaction hash:", tx.hash);
    await tx.wait();
}
```

### Address Management After Creation

```javascript
// Add validation helper
function validateAddress(address, label) {
    if (!ethers.isAddress(address)) {
        throw new Error(`Invalid ${label} address: ${address}`);
    }
    return address;
}

async function getAndStoreAddresses(receipt, tokenFactory) {
    try {
        // Get TokenCreated event
        const event = receipt.logs.find(
            log => {
                try {
                    return tokenFactory.interface.parseLog(log)?.name === "TokenCreated";
                } catch {
                    return false;
                }
            }
        );

        if (!event) {
            throw new Error("TokenCreated event not found in transaction receipt");
        }

        // Parse and validate event data
        const [creator, tokenAddress, bondingCurveAddress, name, symbol] = tokenFactory.interface.parseLog(event).args;
        
        // Validate addresses
        const validatedTokenAddress = validateAddress(tokenAddress, "Token");
        const validatedBondingCurveAddress = validateAddress(bondingCurveAddress, "BondingCurve");
        
        // Create deployment info object
        const deploymentInfo = {
            tokenAddress: validatedTokenAddress,
            bondingCurveAddress: validatedBondingCurveAddress,
            name,
            symbol,
            creator: validateAddress(creator, "Creator"),
            timestamp: new Date().toISOString()
        };

        // Save to file with error handling
        try {
            const fs = require('fs');
            fs.writeFileSync(
                'deployment-info.json',
                JSON.stringify(deploymentInfo, null, 2)
            );
        } catch (error) {
            throw new Error(`Failed to save deployment info: ${error.message}`);
        }

        console.log("Deployment addresses saved:", {
            token: validatedTokenAddress,
            bondingCurve: validatedBondingCurveAddress,
            name,
            symbol
        });

        return deploymentInfo;
    } catch (error) {
        console.error("Error in getAndStoreAddresses:", error);
        throw error;
    }
}
```

### Loading Saved Addresses

```javascript
async function loadDeployedContracts(provider) {
    try {
        // Load deployment info with error handling
        let deploymentInfo;
        try {
            const fs = require('fs');
            deploymentInfo = JSON.parse(
                fs.readFileSync('deployment-info.json')
            );
        } catch (error) {
            throw new Error(`Failed to load deployment info: ${error.message}`);
        }

        // Validate addresses
        const tokenAddress = validateAddress(deploymentInfo.tokenAddress, "Token");
        const bondingCurveAddress = validateAddress(deploymentInfo.bondingCurveAddress, "BondingCurve");

        // Complete ABIs based on codebase
        const erc20Abi = [
            "function balanceOf(address) view returns (uint256)",
            "function decimals() view returns (uint8)",
            "function symbol() view returns (string)",
            "function approve(address,uint256) returns (bool)",
            "function transfer(address,uint256) returns (bool)",
            "function transferFrom(address,address,uint256) returns (bool)"
        ];

        const bondingCurveAbi = [
            "function buyTokens(uint256) payable",
            "function buyTokensFor(address) payable",
            "function sellTokens(uint256)",
            "function getCurrentPrice() view returns (uint256)",
            "function getBeraPrice() view returns (uint256)",
            "function totalSupplyTokens() view returns (uint256)",
            "function liquidityDeployed() view returns (bool)",
            "function collectedBeraUSD() view returns (uint256)",
            "function getSellPrice(uint256) view returns (uint256)"
        ];

        // Connect to contracts
        const token = new ethers.Contract(
            tokenAddress,
            erc20Abi,
            provider
        );

        const bondingCurve = new ethers.Contract(
            bondingCurveAddress,
            bondingCurveAbi,
            provider
        );

        // Verify contracts are deployed
        const tokenCode = await provider.getCode(tokenAddress);
        const bondingCurveCode = await provider.getCode(bondingCurveAddress);
        
        if (tokenCode === "0x") throw new Error("Token contract not deployed");
        if (bondingCurveCode === "0x") throw new Error("Bonding curve contract not deployed");

        return {
            token,
            bondingCurve,
            deploymentInfo
        };
    } catch (error) {
        console.error("Error in loadDeployedContracts:", error);
        throw error;
    }
}
```

## Important Notes

1. **Creation Fee**: Fixed at 0.002 BERA
2. **Initial Purchase**: Any amount above the creation fee will be used to purchase tokens
3. **Token Supply**: Always 1B tokens (1,000,000,000)
4. **Price Feed**: Uses Berachain's BERA/USD price feed
5. **Verification**: Wait at least 30 seconds after transaction confirmation to verify token balances
6. **Gas**: Ensure you have enough BERA for gas fees on top of the creation fee and purchase amount

## Example Transaction Breakdown

For a total value of 0.004 BERA:
- 0.002 BERA: Creation fee (sent to fee collector)
- 0.002 BERA: Initial token purchase (processed by bonding curve)
- Additional: Gas fees for the transaction

The creator will receive tokens based on the bonding curve's pricing algorithm, which starts at a low initial price and increases as more tokens are sold. 