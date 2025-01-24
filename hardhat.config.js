// hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
  networks: {
    berachain: {
      url: process.env.BERACHAIN_RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
