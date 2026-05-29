import { defineConfig } from "hardhat/config";

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
});
