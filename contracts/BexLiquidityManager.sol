// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrocSwapDex {
    function userCmd(uint16 callpath, bytes calldata cmd) external payable returns (bytes memory);
}

contract BexLiquidityManager is Ownable {
    // BEX DEX contract address
    address public bexDex;
    
    // Events
    event LiquidityDeployed(
        address indexed token,
        uint256 beraAmount,
        uint256 tokenAmount,
        address liquidityCollector
    );

    constructor(address _bexDex) Ownable(msg.sender) {
        bexDex = _bexDex;
    }

    function setBexDex(address _bexDex) external onlyOwner {
        bexDex = _bexDex;
    }

    function deployLiquidity(
        address token,
        uint256 tokenAmount,
        address liquidityCollector
    ) external payable onlyOwner {
        require(msg.value == 5 ether, "Exactly 5 BERA required for liquidity");
        require(tokenAmount > 0, "No tokens provided for liquidity");

        // Get tokens from caller
        require(IERC20(token).transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

        // Approve tokens for BEX DEX
        require(IERC20(token).approve(bexDex, tokenAmount), "Token approval failed");

        // Prepare liquidity deployment command
        bytes memory cmd = abi.encodePacked(
            uint8(3),                // code: fixed liquidity units
            token,                   // base token
            uint256(0),             // poolIdx
            int24(0),               // bidTick (full range)
            int24(0),               // askTick (full range)
            uint128(msg.value),     // qty in BERA
            uint128(0),             // limitLower
            uint128(type(uint128).max), // limitHigher
            uint8(0),               // settleFlags
            address(0)              // lpConduit
        );

        // Deploy liquidity to BEX
        try ICrocSwapDex(bexDex).userCmd{value: msg.value}(2, cmd) {
            emit LiquidityDeployed(token, msg.value, tokenAmount, liquidityCollector);
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("BEX operation failed");
        }
    }

    // Allow contract to receive BERA
    receive() external payable {}
} 