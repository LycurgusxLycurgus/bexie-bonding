# Bonding Curve Usage Examples

This guide demonstrates how to interact with a deployed bonding curve contract, including buying/selling tokens and retrieving market metrics.

## Basic Market Information

### Getting Current Price and Supply

```javascript
// Connect to the deployed bonding curve
const BondingCurve = await ethers.getContractFactory("BondingCurve");
const bondingCurve = BondingCurve.attach("YOUR_BONDING_CURVE_ADDRESS");

// Get current market metrics
const beraPrice = await bondingCurve.getBeraPrice();
const tokenPrice = await bondingCurve.getCurrentPrice();
const remainingSupply = await bondingCurve.totalSupplyTokens();
const totalSupply = ethers.parseEther("1000000000"); // 1B tokens
const soldTokens = totalSupply - remainingSupply;

console.log({
    beraPriceUSD: ethers.formatEther(beraPrice),
    tokenPriceUSD: ethers.formatUnits(tokenPrice, 6),
    remainingSupply: ethers.formatEther(remainingSupply),
    soldTokens: ethers.formatEther(soldTokens)
});
```

## Buying Tokens

### Simple Token Purchase

```javascript
const BondingCurve = await ethers.getContractFactory("BondingCurve");
const bondingCurve = BondingCurve.attach("YOUR_BONDING_CURVE_ADDRESS");

// Buy tokens with 0.1 BERA
const buyAmount = ethers.parseEther("0.1");

// Execute purchase (minimum tokens parameter is unused)
const tx = await bondingCurve.buyTokens(1, { value: buyAmount });
const receipt = await tx.wait();

// Get purchase event
const event = receipt.logs.find(
    log => {
        try {
            return bondingCurve.interface.parseLog(log)?.name === "TokensPurchased";
        } catch {
            return false;
        }
    }
);

// Parse purchase details
const [buyer, tokensReceived, beraSpent] = bondingCurve.interface.parseLog(event).args;
console.log({
    tokensReceived: ethers.formatEther(tokensReceived),
    beraSpent: ethers.formatEther(beraSpent)
});
```

### Buying Tokens for Another Address

```javascript
// Buy tokens for a specific beneficiary
const beneficiary = "RECIPIENT_ADDRESS";
const buyAmount = ethers.parseEther("0.1");

const tx = await bondingCurve.buyTokensFor(beneficiary, { value: buyAmount });
await tx.wait();
```

## Selling Tokens

### Calculate Sell Price

```javascript
// Get expected BERA return for selling tokens
const tokenAmount = ethers.parseEther("1000"); // 1,000 tokens
const expectedBera = await bondingCurve.getSellPrice(tokenAmount);
console.log("Expected BERA return:", ethers.formatEther(expectedBera));
```

### Execute Token Sale

```javascript
// First approve the bonding curve to spend your tokens
const Token = await ethers.getContractFactory("CustomERC20");
const token = Token.attach("YOUR_TOKEN_ADDRESS");

const tokenAmount = ethers.parseEther("1000");
await token.approve(bondingCurve.address, tokenAmount);

// Then sell the tokens
const tx = await bondingCurve.sellTokens(tokenAmount);
const receipt = await tx.wait();

// Get sell event
const event = receipt.logs.find(
    log => {
        try {
            return bondingCurve.interface.parseLog(log)?.name === "TokensSold";
        } catch {
            return false;
        }
    }
);

// Parse sale details
const [seller, tokensSold, beraReceived] = bondingCurve.interface.parseLog(event).args;
console.log({
    tokensSold: ethers.formatEther(tokensSold),
    beraReceived: ethers.formatEther(beraReceived)
});
```

## Market Metrics and Thresholds

### Check Liquidity Deployment Status

```javascript
// Check if liquidity has been deployed to BEX
const liquidityDeployed = await bondingCurve.liquidityDeployed();

// Get collected BERA value in USD
const collectedBeraUSD = await bondingCurve.collectedBeraUSD();

// Constants
const TOKEN_SOLD_THRESHOLD = ethers.parseEther("800000000"); // 800M tokens
const BERA_RAISED_THRESHOLD = ethers.parseEther("6"); // 6 BERA

console.log({
    liquidityDeployed,
    collectedBeraUSD: ethers.formatEther(collectedBeraUSD),
    tokenSoldThreshold: ethers.formatEther(TOKEN_SOLD_THRESHOLD),
    beraRaisedThreshold: ethers.formatEther(BERA_RAISED_THRESHOLD)
});
```

## Important Notes

1. **Fees**: All purchases and sales incur a 2% fee
2. **Price Scaling**: Token price increases linearly as more tokens are sold
3. **Liquidity Deployment**: Occurs automatically when:
   - 800M tokens have been sold
   - 6 BERA has been raised
4. **Initial Price**: Starts at $0.000007 per token (at $3,000 BERA price)
5. **Target Price**: Scales to $0.000075 per token at the threshold
6. **BERA Price Updates**: Price feed updates hourly

## Example Price Calculation

```javascript
// Get current BERA price and token metrics
const beraPrice = await bondingCurve.getBeraPrice();
const totalSupply = await bondingCurve.totalSupplyTokens();
const soldTokens = ethers.parseEther("1000000000") - totalSupply;

// Initial price = (7 * beraPrice) / (3000 * 1e18)
// Final price = (75 * beraPrice) / (3000 * 1e18)
// Current price scales linearly between these based on tokens sold

const currentPrice = await bondingCurve.getCurrentPrice();
const marketCap = (TOTAL_TOKENS - totalSupply) * currentPrice / 1e6;

console.log({
    currentPriceUSD: ethers.formatUnits(currentPrice, 6),
    marketCapUSD: ethers.formatEther(marketCap),
    soldTokensPercent: (soldTokens * 100n / ethers.parseEther("1000000000")).toString() + '%'
});
```

## Error Handling

```javascript
try {
    // Attempt to buy with 0 BERA (will fail)
    await bondingCurve.buyTokens(1, { value: 0 });
} catch (error) {
    console.log("Error:", error.reason); // "Zero BERA amount"
}

try {
    // Attempt to sell 0 tokens (will fail)
    await bondingCurve.sellTokens(0);
} catch (error) {
    console.log("Error:", error.reason); // "Zero token amount"
}
``` 