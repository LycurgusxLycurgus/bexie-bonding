// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface ICustomERC20 {
    function mint(address to, uint256 amount) external; // no longer used in sales
    function burn(address from, uint256 amount) external; // no longer used in sales
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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
    // totalSupplyTokens tracks the unsold tokens held by the bonding curve.
    uint256 public totalSupplyTokens;
    uint256 public constant FEE_PERCENT = 2; // 2%

    uint256 public constant TOTAL_TOKENS = 1_000_000_000 * 1e18; // 1B tokens
    uint256 public constant TOKEN_SOLD_THRESHOLD = 800_000_000 * 1e18; // 80% sold triggers liquidity
    uint256 public constant BERA_RAISED_THRESHOLD = 6 ether; // 6 BERA target
    uint256 public constant INITIAL_PRICE_MULTIPLIER = 7;  // e.g. $0.000007 per token initially
    uint256 public constant FINAL_PRICE_MULTIPLIER = 75;   // e.g. $0.000075 target at 3000 USD/BERA
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

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 beraSpent);
    event TokensSold(address indexed seller, uint256 amount, uint256 beraReceived);
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
        
        // The unsold token balance is initially the full supply.
        totalSupplyTokens = TOTAL_TOKENS;
        updateBeraPrice();
        
        // Set an initial price (in raw form)
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
            // Initial price: (INITIAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18)
            return (INITIAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        }

        uint256 soldTokens = TOTAL_TOKENS - totalSupplyTokens;
        uint256 initialPrice = (INITIAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        uint256 finalPrice = (FINAL_PRICE_MULTIPLIER * beraPrice) / (3000 * 1e18);
        uint256 priceDiff = finalPrice - initialPrice;
        return initialPrice + (priceDiff * soldTokens) / TOKEN_SOLD_THRESHOLD;
    }

    /// @notice Sells tokens to the caller for the provided BERA amount.
    function buyTokens(uint256 /* unused */) external payable nonReentrant {
        require(msg.value > 0, "Zero BERA amount");
        require(totalSupplyTokens > 0, "No tokens available");
        
        updateBeraPrice();
        uint256 beraValueUSD = (msg.value * getBeraPrice()) / 1e18;
        uint256 price = getCurrentPrice();
        uint256 tokensToSell = (beraValueUSD * PRICE_DECIMALS) / price;
        
        require(tokensToSell <= totalSupplyTokens, "Not enough tokens in supply");

        // Charge fee
        uint256 fee = (msg.value * FEE_PERCENT) / 100;
        (bool sentFee, ) = feeCollector.call{value: fee}("");
        require(sentFee, "Failed to send fee");

        // Transfer tokens from this contract (the unsold pool) to the buyer.
        require(token.transfer(msg.sender, tokensToSell), "Token transfer failed");
        totalSupplyTokens -= tokensToSell;
        collectedBeraUSD += beraValueUSD;

        // Check if liquidity conditions are met.
        if (!liquidityDeployed &&
            collectedBeraUSD >= (BERA_RAISED_THRESHOLD * getBeraPrice()) / 1e18 &&
            (TOTAL_TOKENS - totalSupplyTokens) >= TOKEN_SOLD_THRESHOLD) {
            deployLiquidityToBex();
        }

        emit TokensPurchased(msg.sender, tokensToSell, msg.value);
    }

    /// @notice Sells tokens on behalf of a specified beneficiary.
    function buyTokensFor(address beneficiary) external payable nonReentrant {
        require(msg.value > 0, "Zero BERA amount");
        require(totalSupplyTokens > 0, "No tokens available");

        updateBeraPrice();
        uint256 beraValueUSD = (msg.value * getBeraPrice()) / 1e18;
        uint256 price = getCurrentPrice();
        uint256 tokensToSell = (beraValueUSD * PRICE_DECIMALS) / price;
        require(tokensToSell <= totalSupplyTokens, "Not enough tokens in supply");

        uint256 fee = (msg.value * FEE_PERCENT) / 100;
        (bool sentFee, ) = feeCollector.call{value: fee}("");
        require(sentFee, "Failed to send fee");

        require(token.transfer(beneficiary, tokensToSell), "Token transfer failed");
        totalSupplyTokens -= tokensToSell;
        collectedBeraUSD += beraValueUSD;

        if (!liquidityDeployed &&
            collectedBeraUSD >= (BERA_RAISED_THRESHOLD * getBeraPrice()) / 1e18 &&
            (TOTAL_TOKENS - totalSupplyTokens) >= TOKEN_SOLD_THRESHOLD) {
            deployLiquidityToBex();
        }

        emit TokensPurchased(beneficiary, tokensToSell, msg.value);
    }

    /// @notice Computes the amount of BERA a seller would receive for a given tokenAmount.
    function getSellPrice(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount > 0, "Zero token amount");
        require(totalSupplyTokens > 0, "No tokens in supply");
        uint256 price = getCurrentPrice();
        uint256 valueUSD = (tokenAmount * price) / PRICE_DECIMALS;
        return (valueUSD * 1e18) / getBeraPrice();
    }

    /// @notice Allows a token holder to sell tokens back to the bonding curve.
    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Zero token amount");
        updateBeraPrice();
        uint256 beraToReceive = getSellPrice(tokenAmount);
        require(beraToReceive <= address(this).balance, "Insufficient BERA balance");

        uint256 fee = (beraToReceive * FEE_PERCENT) / 100;
        uint256 effectiveBeraAmount = beraToReceive - fee;

        // Transfer tokens from seller back to the contract.
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        totalSupplyTokens += tokenAmount;

        (bool sentFee, ) = feeCollector.call{value: fee}("");
        require(sentFee, "Failed to send fee");

        (bool sentSeller, ) = msg.sender.call{value: effectiveBeraAmount}("");
        require(sentSeller, "Failed to send BERA");

        emit TokensSold(msg.sender, tokenAmount, beraToReceive);
    }

    /// @notice When sufficient tokens have been sold and enough BERA collected,
    ///         deploy liquidity to the external DEX using a fixed amount of tokens.
    function deployLiquidityToBex() internal {
        require(!liquidityDeployed, "Liquidity already deployed");
        require(address(this).balance >= 6 ether, "Insufficient BERA for liquidity");

        uint256 tokenAmount = 200_000_000 * 1e18; // 200M tokens for liquidity
        require(totalSupplyTokens >= tokenAmount, "Not enough tokens for liquidity deployment");
        totalSupplyTokens -= tokenAmount;

        // Approve tokens for the liquidity manager.
        require(token.approve(liquidityManager, tokenAmount), "Token approval failed");

        IBexLiquidityManager(liquidityManager).deployLiquidity{value: 5 ether}(
            address(token),
            tokenAmount,
            liquidityCollector
        );

        (bool sentFee, ) = feeCollector.call{value: 1 ether}("");
        require(sentFee, "Failed to send BERA to collector");

        liquidityDeployed = true;
        emit LiquidityDeployedToBex(6 ether, tokenAmount);
    }

    // Allow the contract to receive BERA.
    receive() external payable {}
}
