// contracts/TokenFactory.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BondingCurve.sol";

contract CustomERC20 is Ownable, ERC20 {
    constructor(
        string memory name, 
        string memory symbol, 
        uint256 initialSupply,
        address owner_
    ) ERC20(name, symbol) Ownable(owner_) {
        // Mint the initial supply to the owner
        _mint(owner_, initialSupply * (10 ** uint256(18)));  // 18 decimals is standard for ERC20
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract TokenFactory is Ownable, ReentrancyGuard {
    uint256 public creationFee = 0.02 ether;
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

    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address priceFeedAddress
    ) external payable nonReentrant {
        require(msg.value >= creationFee, "Insufficient creation fee");

        // Create new token with TokenFactory as the initial owner
        CustomERC20 token = new CustomERC20(
            name,
            symbol,
            initialSupply,
            address(this)  // TokenFactory is set as the owner
        );

        // Create new bonding curve with liquidity parameters
        BondingCurve bondingCurve = new BondingCurve(
            address(token),
            feeCollector,
            priceFeedAddress,
            liquidityManager,
            liquidityCollector
        );

        // Transfer tokens directly to the bonding curve instead of the creator
        token.transfer(address(bondingCurve), initialSupply * (10 ** 18));

        // Transfer token ownership to the bonding curve
        token.transferOwnership(address(bondingCurve));

        // Transfer creation fee to fee collector
        (bool sent, ) = feeCollector.call{value: msg.value}("");
        require(sent, "Failed to send fee");

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
