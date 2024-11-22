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
}

contract BondingCurve is Ownable, ReentrancyGuard {
    ICustomERC20 public token;
    address public feeCollector;
    uint256 public totalSupplyTokens;
    uint256 public constant FEE_PERCENT = 2; // 2%
    
    uint256 public constant INITIAL_MARKET_CAP_USD = 7000 * 1e18; // $7000 in wei
    uint256 public constant TOTAL_TOKENS = 1000000000 * 1e18; // 1 billion tokens

    AggregatorV3Interface internal priceFeed;
    uint256 public lastBeraPrice;
    uint256 public lastUpdateTime;
    uint256 public constant UPDATE_INTERVAL = 1 hours;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);
    event TokensSold(address indexed seller, uint256 amount, uint256 price);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);

    constructor(
        address _token, 
        address _feeCollector,
        address _priceFeed
    ) Ownable(msg.sender) {
        token = ICustomERC20(_token);
        feeCollector = _feeCollector;
        totalSupplyTokens = TOTAL_TOKENS;
        priceFeed = AggregatorV3Interface(_priceFeed);
        updateBeraPrice();
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
        uint256 currentMarketCap = INITIAL_MARKET_CAP_USD;
        if (totalSupplyTokens < TOTAL_TOKENS) {
            unchecked {
                // Safe because totalSupplyTokens is always <= TOTAL_TOKENS
                uint256 tokensDiff = TOTAL_TOKENS - totalSupplyTokens;
                currentMarketCap += (tokensDiff * INITIAL_MARKET_CAP_USD) / TOTAL_TOKENS;
            }
        }
        
        // Calculate tokens to receive
        return (beraAmount * TOTAL_TOKENS) / currentMarketCap;
    }

    function buyTokens(uint256 minTokens) external payable nonReentrant {
        updateBeraPrice();
        uint256 tokensToReceive = getBuyPrice(msg.value);
        require(tokensToReceive >= minTokens, "Insufficient tokens for BERA sent");

        uint256 fee = (msg.value * FEE_PERCENT) / 100;
        
        (bool sent, ) = feeCollector.call{value: fee}("");
        require(sent, "Failed to send fee");

        token.mint(msg.sender, tokensToReceive);
        totalSupplyTokens -= tokensToReceive;

        emit TokensPurchased(msg.sender, tokensToReceive, msg.value);
    }

    function getSellPrice(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount <= totalSupplyTokens, "Not enough tokens to sell");
        
        uint256 beraPrice = getBeraPrice();
        
        // Calculate current market cap
        uint256 currentMarketCap = INITIAL_MARKET_CAP_USD;
        if (totalSupplyTokens < TOTAL_TOKENS) {
            unchecked {
                // Safe because totalSupplyTokens is always <= TOTAL_TOKENS
                uint256 tokensDiff = TOTAL_TOKENS - totalSupplyTokens;
                currentMarketCap += (tokensDiff * INITIAL_MARKET_CAP_USD) / TOTAL_TOKENS;
            }
        }
        
        // Break down calculations to avoid overflow
        // First calculate the token's share of the market cap
        uint256 tokenShare = (tokenAmount * 1e18) / TOTAL_TOKENS;
        
        // Then calculate USD value
        uint256 usdValue = (tokenShare * currentMarketCap) / 1e18;
        
        // Finally convert to BERA
        return (usdValue * 1e18) / beraPrice;
    }

    function sellTokens(uint256 amount) external nonReentrant {
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        updateBeraPrice();

        uint256 beraToReturn = getSellPrice(amount);
        uint256 fee = (beraToReturn * FEE_PERCENT) / 100;
        uint256 totalRefund = beraToReturn - fee;

        token.burn(msg.sender, amount);

        (bool feeSuccess, ) = feeCollector.call{value: fee}("");
        require(feeSuccess, "Failed to send fee");

        (bool refundSuccess, ) = msg.sender.call{value: totalRefund}("");
        require(refundSuccess, "Failed to send refund");

        totalSupplyTokens += amount;

        emit TokensSold(msg.sender, amount, beraToReturn);
    }

    receive() external payable {}
}
