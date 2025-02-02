// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint80 private _roundId;
    uint256 private _timestamp;

    constructor(uint8 __decimals, int256 initialAnswer) {
        _decimals = __decimals;
        _answer = initialAnswer;
        _roundId = 1;
        _timestamp = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock V3 Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 3;
    }

    function getRoundData(uint80 roundId_) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        require(roundId_ > 0, "Invalid round ID");
        return (
            roundId_,
            _answer,
            _timestamp,
            _timestamp,
            roundId_
        );
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (
            _roundId,
            _answer,
            _timestamp,
            _timestamp,
            _roundId
        );
    }

    // Test helper function
    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _roundId++;
        _timestamp = block.timestamp;
    }

    // Add explicit address conversion
    function getAddress() external view returns (address) {
        return address(this);
    }
} 