# BEX DEX Integration Guide

This guide provides the necessary steps to integrate with the BEX Decentralized Exchange (DEX) on the Berachain network, focusing on obtaining the contract's ABI and address, understanding the function signatures for adding liquidity, and setting up the environment.

## 1. BEX DEX Documentation

### 1.1. Obtain the ABI and Address of the BEX DEX Contract

- **Contract Address**: The BEX DEX contract, known as `CrocSwapDex`, is deployed on the bArtio Testnet at:

  ```
  0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49
  ```

  

- **ABI (Application Binary Interface)**: The ABI for `CrocSwapDex` can be found in the Berachain's official GitHub repository:

  ```
  https://github.com/berachain/doc-abis/blob/main/bex/CrocSwapDex.json
  ```

  

### 1.2. Understand the Function Signatures for Adding Liquidity

Adding liquidity to the BEX DEX involves interacting with the `userCmd` function of the `CrocSwapDex` contract. The function signature is:

```solidity
function userCmd(
    uint16 callpath,
    bytes cmd
) public payable returns (bytes)
```

To add liquidity, the `callpath` parameter should be set to `2`, which corresponds to LP (Liquidity Provider) operations. The `cmd` parameter is an encoded byte string containing the following structured data:

- `code` (uint8): Specifies the type of LP action. For minting liquidity, use:
  - `3` for fixed in liquidity units.
  - `31` for fixed in base tokens.
  - `32` for fixed in quote tokens.
- `base` (address): The address of the base token.
- `quote` (address): The address of the quote token.
- `poolIdx` (uint256): The index of the pool.
- `bidTick` (int24): Set to `0` for full-range liquidity.
- `askTick` (int24): Set to `0` for full-range liquidity.
- `qty` (uint128): The size of the liquidity being added.
- `limitLower` (uint128): The minimum acceptable curve price.
- `limitHigher` (uint128): The maximum acceptable curve price.
- `settleFlags` (uint8): Flag indicating how the user wants to settle the tokens.
- `lpConduit` (address): The address of the LP token.



## 2. Environment Setup

Before deploying liquidity, ensure the following:

- **Permissions**: The contract or wallet used must have the necessary permissions to interact with the `CrocSwapDex` contract. This includes approval to spend the specific tokens intended for liquidity provision.

- **BERA Balance**: Ensure that the contract or wallet has a sufficient balance of BERA tokens to cover transaction fees and the liquidity amount.
