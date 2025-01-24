(REQUIRES UPDATES)

# ERC20 Token Factory with Bonding Curve

## Description

This project allows users to create their own ERC20 tokens with a bonding curve for dynamic pricing based on supply and demand. It includes features like fee collection, liquidity management, and security measures.

## Features

- **Token Creation Smart Contract:** Create new ERC20 tokens with custom name, symbol, and initial supply.
- **Bonding Curve Implementation:** Dynamic buy and sell pricing based on a linear bonding curve.
- **Fee Collection:** Charge a creation fee and transaction fees for platform sustainability.
- **Security:** Implement ownership control, reentrancy protection, and input validation.

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/en/) v14 or higher
- [Hardhat](https://hardhat.org/getting-started/)
- [Git](https://git-scm.com/)

### Installation

1. **Clone the Repository**

   ```bash
   git clone https://github.com/yourusername/your-project.git
   cd your-project
   ```

2. **Install Dependencies**

   ```bash
   npm install
   ```

3. **Configure Environment Variables**

   Create a `.env` file in the root directory and add your private key and Berachain RPC URL.

   ```env
   PRIVATE_KEY=your_private_key_here
   BERACHAIN_RPC_URL=https://your-berachain-rpc-url
   FEE_COLLECTOR_ADDRESS=fee_collector_address_here
   ```

4. **Compile Contracts**

   ```bash
   npm run compile
   ```

5. **Run Tests**

   ```bash
   npm run test
   ```

6. **Deploy Contracts**

   ```bash
   npm run deploy
   ```

## Usage

Once deployed, interact with the `TokenFactory` contract to create new ERC20 tokens. Each token will have an associated `BondingCurve` contract to manage dynamic pricing.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.

## License

This project is licensed under the MIT License.
