import { defineConfig } from "hardhat/config";
import hardhatIgnition from "@nomicfoundation/hardhat-ignition";
import hardhatIgnoreWarnings from "hardhat-ignore-warnings";

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
  plugins: [hardhatIgnition, hardhatIgnoreWarnings],
  solidity: {
    profiles: {
      default: { compilers: [aquaCompilerSettings] },
      production: { compilers: [aquaCompilerSettings] },
    },
  },
  paths: {
    sources: "./src",
  },
  test: {
    solidity: {
      fsPermissions: {
        dangerouslyReadWriteDirectory: ["./deployments", "./config"],
      },
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
