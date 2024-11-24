// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockBexDex {
    mapping(address => mapping(address => uint256)) public liquidityPools;

    function userCmd(uint16 callpath, bytes calldata cmd) external payable returns (bytes memory) {
        require(callpath == 2, "Invalid callpath");
        
        // Extract the first byte (code)
        uint8 code = uint8(cmd[0]);
        require(code == 3, "Invalid code");

        // Extract token address (next 20 bytes)
        address baseToken;
        assembly {
            // Skip the first byte and load the next 32 bytes
            let ptr := add(cmd.offset, 1)
            baseToken := shr(96, calldataload(ptr))
        }
        
        // Record the liquidity using msg.value
        liquidityPools[baseToken][address(0)] = msg.value;
        
        return "";
    }

    function getLiquidity(address baseToken, address quoteToken) external view returns (uint256) {
        return liquidityPools[baseToken][quoteToken];
    }
}

contract MockFailingBexDex {
    function userCmd(uint16, bytes calldata) external pure returns (bytes memory) {
        assembly {
            revert(0, 0)
        }
    }
} 