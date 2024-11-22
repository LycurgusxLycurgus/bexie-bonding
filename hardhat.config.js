// hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    berachain: {
      url: process.env.BERACHAIN_RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
