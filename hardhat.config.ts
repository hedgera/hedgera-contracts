import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    hedera: {
      url: "https://mainnet.hashio.io/api",
      chainId: 295, // 0x127
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gas: 1500000000, // 15M gas limit
      gasPrice: 350000000000, // 350 gwei (above minimum 320)
      timeout: 60000,
    },
  },
  defaultNetwork: "hedera",
};

export default config;
