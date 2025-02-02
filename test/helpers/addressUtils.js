const { ethers } = require("hardhat");

module.exports = {
    getContractAddress: async (contract) => {
        return await contract.getAddress();
    },
    validateAddress: (address) => {
        if (!ethers.isAddress(address)) {
            throw new Error(`Invalid address: ${address}`);
        }
        return address;
    }
}; 