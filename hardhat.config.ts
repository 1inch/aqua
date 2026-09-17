import { configVariable, defineConfig } from "hardhat/config";
import hardhatIgnitionViem from "@nomicfoundation/hardhat-ignition-viem";
import hardhatIgnoreWarnings from "hardhat-ignore-warnings";
import hardhatKeystore from "@nomicfoundation/hardhat-keystore";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

const aquaCompilerSettings = {
  version: "0.8.30",
  settings: {
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 10_000_000,
    },
  },
};

export default defineConfig({
  plugins: [
    hardhatIgnitionViem,
    hardhatIgnoreWarnings,
    hardhatKeystore,
    hardhatVerify,
  ],
  solidity: {
    splitTestsCompilation: true,
    profiles: {
      default: { compilers: [aquaCompilerSettings] },
      production: { compilers: [aquaCompilerSettings] },
    },
  },
  paths: {
    sources: "./src",
  },
  networks: {
    localhost: {
      type: "http",
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    sepolia: {
      type: "http",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
  test: {
    solidity: {
      fsPermissions: {
        dangerouslyReadWriteDirectory: ["./deployments", "./config"],
      },
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
  warnings: {
    "test/**/*": {
      "code-size": "off",
    },
    "npm/@1inch/**/*": {
      "transient-storage": "off",
    },
  },
});
