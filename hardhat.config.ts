import type { HardhatUserConfig } from "hardhat/types";
import { task } from "hardhat/config";
import fs from "fs";
import path from "path";
import "@nomicfoundation/hardhat-chai-matchers";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import "solidity-coverage";
import "dotenv/config";

import { Network, NETWORKS_RPC_URL } from "./tasks/config";

const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY || "";
const MNEMONIC_PATH = "m/44'/60'/0'/0";
const MNEMONIC = process.env.MNEMONIC || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const REPORT_GAS = !!process.env.REPORT_GAS;
// const GWEI = 1000 * 1000 * 1000;

const tasksPath = path.join(__dirname, "tasks");
fs.readdirSync(tasksPath)
  .filter((pth) => pth.endsWith(".ts"))
  .forEach((task) => {
    require(`${tasksPath}/${task}`);
  });

task("accounts", "Prints the list of accounts", async (_args, hre) => {
  const accounts = await hre.ethers.getSigners();
  accounts.forEach(async (account) => console.info(account.address));
});

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 5,
      initialBaseFeePerGas: 0,
      forking: {
        url: NETWORKS_RPC_URL[Network.goerli],
        blockNumber: 8076786,
      },
      allowUnlimitedContractSize: true,
    },
    goerli: {
      url: NETWORKS_RPC_URL[Network.goerli],
      accounts: PRIVATE_KEY
        ? [PRIVATE_KEY]
        : {
            mnemonic: MNEMONIC,
            path: MNEMONIC_PATH,
            initialIndex: 0,
            count: 20,
          },
    },
    mainnet: {
      // gasPrice: 7 * GWEI,
      url: NETWORKS_RPC_URL[Network.mainnet],
      accounts: PRIVATE_KEY
        ? [PRIVATE_KEY]
        : {
            mnemonic: MNEMONIC,
            path: MNEMONIC_PATH,
            initialIndex: 0,
            count: 20,
          },
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.8.10",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    ],
  },
  paths: {
    sources: "./contracts/",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./abis",
    runOnCompile: true,
    clear: true,
    flat: true,
    pretty: false,
    except: ["test*", "@openzeppelin*"],
  },
  gasReporter: {
    enabled: REPORT_GAS,
    excludeContracts: ["test*", "@openzeppelin*"],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
};

export default config;
