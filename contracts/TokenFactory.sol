// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BondingCurve.sol";

/*
    Instructions for token creation and initial purchase:
    
    1. To deploy a new token (and its associated bonding curve), call createToken with the following parameters:
       - name: The token name.
       - symbol: The token symbol.
       - initialSupply: The total token supply (in whole units, e.g. 1000000000 for 1B tokens).
       - priceFeedAddress: The address of the price feed contract (for example, a Chainlink aggregator).
    
    2. In the transaction, send a total value of at least the creation fee (0.002 BERA).
       Any amount above the creation fee will be used as an initial purchase. That extra BERA is forwarded
       to the bonding curve, which immediately sells tokens from its pre‑minted pool to the creator.
*/

contract CustomERC20 is Ownable, ERC20 {
    constructor(
        string memory name, 
        string memory symbol, 
        uint256 initialSupply,
        address owner_
    ) ERC20(name, symbol) Ownable(owner_) {
        // Mint the fixed total supply (using 18 decimals) to the creator (TokenFactory)
        _mint(owner_, initialSupply * (10 ** uint256(18)));
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract TokenFactory is Ownable, ReentrancyGuard {
    uint256 public creationFee = 0.002 ether;
    address public feeCollector;
    address public liquidityManager;
    address public liquidityCollector;

    event TokenCreated(
        address indexed creator,
        address tokenAddress,
        address bondingCurveAddress,
        string name,
        string symbol
    );

    constructor(
        address _feeCollector,
        address _liquidityManager,
        address _liquidityCollector
    ) Ownable(msg.sender) {
        feeCollector = _feeCollector;
        liquidityManager = _liquidityManager;
        liquidityCollector = _liquidityCollector;
    }

    /// @notice Creates a new token and its bonding curve. Any extra BERA (beyond the creation fee) is used
    ///         to make an initial purchase (i.e. to sell tokens from the pre‑minted pool to the creator).
    /// @param name The name of the new token.
    /// @param symbol The token symbol.
    /// @param initialSupply The total token supply (in whole numbers, e.g. 1000000000 for 1B tokens).
    /// @param priceFeedAddress The address of the price feed (e.g. a Chainlink aggregator).
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address priceFeedAddress
    ) external payable nonReentrant {
        require(msg.value >= creationFee, "Insufficient creation fee");
        uint256 purchaseValue = msg.value - creationFee;

        // Deploy a new token; the full supply is minted to this factory.
        CustomERC20 token = new CustomERC20(
            name,
            symbol,
            initialSupply,
            address(this)
        );

        // Deploy a new bonding curve that will hold and sell the tokens.
        BondingCurve bondingCurve = new BondingCurve(
            address(token),
            feeCollector,
            priceFeedAddress,
            liquidityManager,
            liquidityCollector
        );

        // Transfer the entire token supply from this factory to the bonding curve.
        require(token.transfer(address(bondingCurve), initialSupply * (10 ** 18)), "Token transfer failed");

        // Transfer token ownership to the bonding curve.
        token.transferOwnership(address(bondingCurve));

        // Send the fixed creation fee to the fee collector.
        (bool sentFee, ) = feeCollector.call{value: creationFee}("");
        require(sentFee, "Failed to send creation fee");

        // If extra funds are provided, use them to make an initial purchase (i.e. sell tokens from the bonding curve).
        if (purchaseValue > 0) {
            bondingCurve.buyTokensFor{value: purchaseValue}(msg.sender);
        }

        emit TokenCreated(
            msg.sender,
            address(token),
            address(bondingCurve),
            name,
            symbol
        );
    }

    function setCreationFee(uint256 _newFee) external onlyOwner {
        creationFee = _newFee;
    }

    function setFeeCollector(address _newCollector) external onlyOwner {
        feeCollector = _newCollector;
    }

    function setLiquidityManager(address _newManager) external onlyOwner {
        liquidityManager = _newManager;
    }
}
