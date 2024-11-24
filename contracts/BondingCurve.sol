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
    
    uint256 public constant INITIAL_MARKET_CAP_USD = 7000 * 1e18; // $7000 in wei
    uint256 public constant TARGET_MARKET_CAP_USD = 69420 * 1e18; // $69,420 in wei
    uint256 public constant TARGET_COLLECTED_BERA_USD = 13884 * 1e18; // $13,884 in wei
    uint256 public constant TOTAL_TOKENS = 1000000000 * 1e18; // 1 billion tokens

    uint256 public currentMarketCapUSD;
    uint256 public collectedBeraUSD;
    bool public targetReached;

    AggregatorV3Interface internal priceFeed;
    uint256 public lastBeraPrice;
    uint256 public lastUpdateTime;
    uint256 public constant UPDATE_INTERVAL = 1 hours;

    address public liquidityManager;
    address public liquidityCollector;
    bool public liquidityDeployed;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);
    event TokensSold(address indexed seller, uint256 amount, uint256 price);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);
    event MarketCapUpdated(uint256 newMarketCap, uint256 collectedBeraUSD);
    event TargetReached(uint256 marketCap, uint256 collectedBera);
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
        totalSupplyTokens = TOTAL_TOKENS;
        priceFeed = AggregatorV3Interface(_priceFeed);
        updateBeraPrice();
        currentMarketCapUSD = INITIAL_MARKET_CAP_USD;
        collectedBeraUSD = 0;
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

    function getBuyPrice(uint256 beraAmount) public view returns (uint256) {
        // Calculate current market cap
        uint256 currentMarketCap = currentMarketCapUSD;
        if (totalSupplyTokens < TOTAL_TOKENS) {
            unchecked {
                // Safe because totalSupplyTokens is always <= TOTAL_TOKENS
                uint256 tokensDiff = TOTAL_TOKENS - totalSupplyTokens;
                currentMarketCap += (tokensDiff * INITIAL_MARKET_CAP_USD) / TOTAL_TOKENS;
            }
        }
        
        // Calculate tokens to receive using unchecked to prevent overflow
        unchecked {
            return (beraAmount * TOTAL_TOKENS) / currentMarketCap;
        }
    }

    function updateMarketMetrics(uint256 beraAmount, bool isBuy) internal {
        // Get and update BERA price
        updateBeraPrice();
        uint256 beraValueUSD = (beraAmount * getBeraPrice()) / 1e18;
        
        if (isBuy) {
            currentMarketCapUSD += beraValueUSD;
            
            // Calculate collected BERA based on market cap proportion
            if (currentMarketCapUSD > INITIAL_MARKET_CAP_USD) {
                uint256 mcapDiff = currentMarketCapUSD - INITIAL_MARKET_CAP_USD;
                uint256 totalMcapRange = TARGET_MARKET_CAP_USD - INITIAL_MARKET_CAP_USD;
                collectedBeraUSD = (mcapDiff * TARGET_COLLECTED_BERA_USD) / totalMcapRange;
            } else {
                collectedBeraUSD = 0;
            }
        } else {
            // Prevent underflow in market cap calculation
            currentMarketCapUSD = currentMarketCapUSD > beraValueUSD ? 
                currentMarketCapUSD - beraValueUSD : INITIAL_MARKET_CAP_USD;
            
            // Recalculate collected BERA based on new market cap
            if (currentMarketCapUSD > INITIAL_MARKET_CAP_USD) {
                uint256 mcapDiff = currentMarketCapUSD - INITIAL_MARKET_CAP_USD;
                uint256 totalMcapRange = TARGET_MARKET_CAP_USD - INITIAL_MARKET_CAP_USD;
                collectedBeraUSD = (mcapDiff * TARGET_COLLECTED_BERA_USD) / totalMcapRange;
            } else {
                collectedBeraUSD = 0;
            }
        }

        emit MarketCapUpdated(currentMarketCapUSD, collectedBeraUSD);

        // Check if target conditions are met and liquidity hasn't been deployed yet
        if (!liquidityDeployed && 
            currentMarketCapUSD >= TARGET_MARKET_CAP_USD && 
            collectedBeraUSD >= TARGET_COLLECTED_BERA_USD) {
            targetReached = true;
            emit TargetReached(currentMarketCapUSD, collectedBeraUSD);
            deployLiquidityToBex();
        }
    }

    function buyTokens(uint256 minTokens) external payable nonReentrant {
        require(msg.value > 0, "Zero BERA amount");
        updateBeraPrice();
        uint256 tokensToReceive = getBuyPrice(msg.value);
        require(tokensToReceive >= minTokens, "Insufficient tokens for BERA sent");

        uint256 fee = (msg.value * FEE_PERCENT) / 100;
        uint256 effectiveBeraAmount = msg.value - fee;
        
        (bool sent, ) = feeCollector.call{value: fee}("");
        require(sent, "Failed to send fee");

        token.mint(msg.sender, tokensToReceive);
        totalSupplyTokens -= tokensToReceive;

        updateMarketMetrics(effectiveBeraAmount, true);
        emit TokensPurchased(msg.sender, tokensToReceive, msg.value);
    }

    function getSellPrice(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount > 0, "Zero token amount");
        require(tokenAmount <= totalSupplyTokens, "Not enough tokens to sell");
        
        uint256 beraPrice = getBeraPrice();
        
        // Calculate current market cap
        uint256 currentMarketCap = currentMarketCapUSD;
        if (totalSupplyTokens < TOTAL_TOKENS) {
            unchecked {
                // Safe because totalSupplyTokens is always <= TOTAL_TOKENS
                uint256 tokensDiff = TOTAL_TOKENS - totalSupplyTokens;
                currentMarketCap += (tokensDiff * INITIAL_MARKET_CAP_USD) / TOTAL_TOKENS;
            }
        }

        // Calculate BERA to receive using unchecked to prevent overflow
        unchecked {
            return (tokenAmount * currentMarketCap) / TOTAL_TOKENS;
        }
    }

    function sellTokens(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Zero token amount");
        require(tokenAmount <= totalSupplyTokens, "Not enough tokens to sell");
        
        updateBeraPrice();
        uint256 beraToReceive = getSellPrice(tokenAmount);
        
        uint256 fee = (beraToReceive * FEE_PERCENT) / 100;
        uint256 effectiveBeraAmount = beraToReceive - fee;

        token.burn(msg.sender, tokenAmount);
        totalSupplyTokens += tokenAmount;

        (bool sent1, ) = feeCollector.call{value: fee}("");
        require(sent1, "Failed to send fee");

        (bool sent2, ) = msg.sender.call{value: effectiveBeraAmount}("");
        require(sent2, "Failed to send BERA");

        updateMarketMetrics(effectiveBeraAmount, false);
        emit TokensSold(msg.sender, tokenAmount, beraToReceive);
    }

    function deployLiquidityToBex() internal {
        require(targetReached, "Target not reached");
        require(!liquidityDeployed, "Liquidity already deployed");
        
        // Calculate BERA amount needed for liquidity (6942 USD worth of BERA)
        uint256 beraForLiquidity = (6942 * 1e18 * 1e18) / getBeraPrice(); // 6942 USD worth of BERA
        uint256 tokenAmount = getBuyPrice(beraForLiquidity);

        // Transfer BERA to this contract if needed
        require(address(this).balance >= beraForLiquidity * 2, "Insufficient BERA for liquidity");

        // Mint tokens for liquidity and approve liquidity manager
        token.mint(address(this), tokenAmount);
        require(token.approve(liquidityManager, tokenAmount), "Token approval failed");

        // Deploy liquidity through manager
        IBexLiquidityManager(liquidityManager).deployLiquidity{value: beraForLiquidity * 2}(
            address(token),
            tokenAmount,
            liquidityCollector
        );

        liquidityDeployed = true;
        emit LiquidityDeployedToBex(beraForLiquidity * 2, tokenAmount);
    }

    receive() external payable {}
}
