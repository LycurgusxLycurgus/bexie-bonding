// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockPriceFeed {
    int256 private price;
    uint8 private decimals_ = 8;

    constructor(uint256 _price) {
        price = int256(_price / 1e10);
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            1,              // roundId
            price,          // answer (8 decimals)
            block.timestamp,// startedAt
            block.timestamp,// updatedAt
            1              // answeredInRound
        );
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
} 