import type { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.30",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10_000_000,
          },
          viaIR: true,
          evmVersion: "cancun",
        },
      },
    ],
  },
  test: {
    solidity: {
      fsPermissions: {
        dangerouslyReadWriteDirectory: ["./deployments", "./config"],
      },
    },
  },
  // ----- Foundry-only settings (no Hardhat equivalent) -----

  // [profile.ci] — identical to [profile.default], no separate mapping needed.
  //   Foundry CI profile only mirrors default compiler settings in this project.

  // [profile.solx] — custom compiler binary: solc = "~/.local/bin/solx"
  //   Hardhat does not support custom compiler binaries. Foundry-only.

  // [fmt] — Foundry formatter settings (single_line_statement_blocks, multiline_func_header, etc.)
  //   No Hardhat equivalent. Use prettier-plugin-solidity or solhint instead.
  //   Foundry-only.

  // forge snapshot — gas snapshot testing
  //   Not supported in Hardhat. See: https://github.com/NomicFoundation/hardhat/issues/7769

  // out = "out" / libs — Hardhat uses its own artifacts/ + cache/ directories
};

export default config;
