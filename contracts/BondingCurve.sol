// contracts/BondingCurve.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface ICustomERC20 {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBexLiquidityManager {
    function deployLiquidity(
        address token,
        uint256 tokenAmount,
        address liquidityCollector
    ) external payable;
}

contract BondingCurve is Ownable, ReentrancyGuard {
    ICustomERC20 public token;
    address public feeCollector;
    uint256 public totalSupplyTokens;
    uint256 public constant FEE_PERCENT = 2; // 2%
    
    uint256 public constant TOTAL_TOKENS = 1_000_000_000 * 1e18; // 1B tokens
    uint256 public constant TOKEN_SOLD_THRESHOLD = 800_000_000 * 1e18; // 80% for bonding curve
    uint256 public constant BERA_RAISED_THRESHOLD = 6 ether; // 6 BERA target
    uint256 public constant INITIAL_PRICE_MULTIPLIER = 7; // $0.000007 per token initially
    uint256 public constant FINAL_PRICE_MULTIPLIER = 75; // $0.000075 target at 3000 USD/BERA
    uint256 public constant PRICE_DECIMALS = 1e6; // Price multiplier decimals

    uint256 public collectedBeraUSD;
    uint256 public currentPrice;
    bool public liquidityDeployed;

    AggregatorV3Interface internal priceFeed;
    uint256 public lastBeraPrice;
    uint256 public lastUpdateTime;
    uint256 public constant UPDATE_INTERVAL = 1 hours;

    address public liquidityManager;
    address public liquidityCollector;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);
    event TokensSold(address indexed seller, uint256 amount, uint256 price);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);
    event LiquidityDeployedToBex(uint256 beraAmount, uint256 tokenAmount);

    constructor(
        address _token, 
        address _feeCollector,
        address _priceFeed,
        address _liquidityManager,
        address _liquidityCollector
    ) Ownable(msg.sender) {
        token = ICustomERC20(_token);
        feeCollector = _feeCollector;
        liquidityManager = _liquidityManager;
        liquidityCollector = _liquidityCollector;
        priceFeed = AggregatorV3Interface(_priceFeed);
        
        totalSupplyTokens = TOTAL_TOKENS;
        updateBeraPrice();
        
        // Set initial price in raw form
        currentPrice = (INITIAL_PRICE_MULTIPLIER * getBeraPrice()) / (3000 * 1e18);
    }

    function updateBeraPrice() public {
        if (block.timestamp >= lastUpdateTime + UPDATE_INTERVAL) {
            (, int256 price,,,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid BERA price");
            lastBeraPrice = uint256(price) * 1e10; // Convert to 18 decimals
            lastUpdateTime = block.timestamp;
            emit PriceUpdated(lastBeraPrice, block.timestamp);
        }
    }

    function getBeraPrice() public view returns (uint256) {
        if (block.timestamp >= lastUpdateTime + UPDATE_INTERVAL) {
            (, int256 price,,,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid BERA price");
            return uint256(price) * 1e10; // Convert to 18 decimals
        }
        return lastBeraPrice;
    }

    function getCurrentPrice() public view returns (uint256) {
        uint256 beraPrice = getBeraPrice(); // 18 decimals
        
        if (totalSupplyTokens == TOTAL_TOKENS) {
            // For $0.000007: (7 * beraPrice) / (3000 * 1e18)
            return (INITIAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        }

        uint256 soldTokens = TOTAL_TOKENS - totalSupplyTokens;
        
        // Calculate prices in raw form (not multiplied by 1e6)
        uint256 initialPrice = (INITIAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        uint256 finalPrice = (FINAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        uint256 priceDiff = finalPrice - initialPrice;
        
        return initialPrice + (priceDiff * soldTokens) / TOKEN_SOLD_THRESHOLD;
    }

    function buyTokens(uint256 minTokens) external payable nonReentrant {
        require(msg.value > 0, "Zero BERA amount");
        require(totalSupplyTokens > 0, "No tokens available");
        
        updateBeraPrice();
        uint256 beraValueUSD = (msg.value * getBeraPrice()) / 1e18;
        
        // Calculate tokens based on current price
        uint256 price = getCurrentPrice();
        uint256 tokensToMint = (beraValueUSD * PRICE_DECIMALS) / price;
        
        require(tokensToMint >= minTokens, "Insufficient tokens for BERA sent");
        require(tokensToMint <= totalSupplyTokens, "Not enough tokens in supply");

        uint256 fee = (msg.value * FEE_PERCENT) / 100;
        (bool sent, ) = feeCollector.call{value: fee}("");
        require(sent, "Failed to send fee");

        token.mint(msg.sender, tokensToMint);
        totalSupplyTokens -= tokensToMint;
        collectedBeraUSD += beraValueUSD;

        // Check deployment conditions
        if (!liquidityDeployed && 
            collectedBeraUSD >= (BERA_RAISED_THRESHOLD * getBeraPrice()) / 1e18 &&
            (TOTAL_TOKENS - totalSupplyTokens) >= TOKEN_SOLD_THRESHOLD) {
            deployLiquidityToBex();
        }

        emit TokensPurchased(msg.sender, tokensToMint, msg.value);
    }

    function getSellPrice(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount > 0, "Zero token amount");
        require(totalSupplyTokens > 0, "No tokens in supply");
        
        uint256 price = getCurrentPrice();
        uint256 valueUSD = (tokenAmount * price) / PRICE_DECIMALS;
        return (valueUSD * 1e18) / getBeraPrice();
    }

    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Zero token amount");
        require(tokenAmount <= totalSupplyTokens, "Not enough tokens to sell");
        
        updateBeraPrice();
        uint256 beraToReceive = getSellPrice(tokenAmount);
        require(beraToReceive <= address(this).balance, "Insufficient BERA balance");
        
        uint256 fee = (beraToReceive * FEE_PERCENT) / 100;
        uint256 effectiveBeraAmount = beraToReceive - fee;

        token.burn(msg.sender, tokenAmount);
        totalSupplyTokens += tokenAmount;
        
        // Send fee first
        (bool sent1, ) = feeCollector.call{value: fee}("");
        require(sent1, "Failed to send fee");

        // Then send BERA to seller
        (bool sent2, ) = msg.sender.call{value: effectiveBeraAmount}("");
        require(sent2, "Failed to send BERA");

        emit TokensSold(msg.sender, tokenAmount, beraToReceive);
    }

    function deployLiquidityToBex() internal {
        require(!liquidityDeployed, "Liquidity already deployed");
        require(address(this).balance >= 6 ether, "Insufficient BERA for liquidity");

        uint256 tokenAmount = 200000000 * 1e18; // 200M tokens

        // Mint tokens for liquidity
        token.mint(address(this), tokenAmount);
        require(token.approve(liquidityManager, tokenAmount), "Token approval failed");

        // Deploy 5 BERA to liquidity
        IBexLiquidityManager(liquidityManager).deployLiquidity{value: 5 ether}(
            address(token),
            tokenAmount,
            liquidityCollector
        );

        // Send 1 BERA to fee collector
        (bool sent, ) = feeCollector.call{value: 1 ether}("");
        require(sent, "Failed to send BERA to collector");

        liquidityDeployed = true;
        emit LiquidityDeployedToBex(6 ether, tokenAmount);
    }

    receive() external payable {}
}
