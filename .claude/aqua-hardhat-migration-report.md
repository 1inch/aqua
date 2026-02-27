# Aqua — Hardhat 3 Migration Report

## 1. Test Count Comparison

| Metric | Count |
|---|---|
| `function test*` declarations in `test/*.t.sol` | **49** |
| Hardhat tests executed | **49** |
| Discrepancy | **None** |

The `examples/test/` directory contains 26 additional test functions across 2 files, but these are outside the default `test/` directory and not run by either `forge test` or `npx hardhat test solidity` with default config.

## 2. Feature Parity Table

| Feature | Forge | Hardhat 3 | Parity |
|---|---|---|---|
| Solidity compilation | `forge build` | `npx hardhat compile` | **Full** |
| Unit tests | `forge test` | `npx hardhat test solidity` | **Full** |
| Fuzz testing | auto-detects `testFuzz_*` | Built-in | **Full** (1 fuzz test ran with 256 runs) |
| forge-std cheatcodes (vm.*) | Native | Supported via EDR | **Full** |
| `remappings.txt` | Native | Auto-loaded | **Full** |
| Optimizer (10M runs, viaIR) | `foundry.toml` | `hardhat.config.ts` | **Full** |
| `fs_permissions` | Array format | `fsPermissions` object | **Full** |
| Gas snapshots | `forge snapshot` | Not supported | **Gap** — [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) |
| Deployment scripts (`.s.sol`) | `forge script` | No equivalent | **Gap** |
| Custom compiler binary (`solx`) | `solc = "path"` | Not supported | **Gap** — Foundry-only |
| Formatter (`forge fmt`) | Built-in | Not available | **Gap** — use prettier/solhint |

## 3. Workarounds Applied

### patch-package for `@1inch/solidity-utils`

**Problem:** The `@1inch/solidity-utils` npm package has a restrictive `exports` field that only exposes JS/TS entry points, not `.sol` contract files. Hardhat 3 respects Node.js `exports` fields, causing `HHE902` errors when importing Solidity files from the package.

**Fix:** Added `"./contracts/*.sol": "./contracts/*.sol"` to the package's `exports` field via `patch-package`. Patch file: `patches/@1inch+solidity-utils+6.9.2.patch`.

### Absolute imports → relative imports (8 files)

Converted absolute imports (`src/...`, `test/...`, `examples/...`) to relative imports in:
- `test/AquaEvents.t.sol`
- `test/AquaBalances.t.sol`
- `test/AquaPushPull.t.sol`
- `test/AquaShipDock.t.sol`
- `test/AquaLifecycle.t.sol`
- `test/base/AquaTestBase.sol`
- `examples/test/XYCNestedSwaps.t.sol`
- `examples/test/XYCSwap.t.sol`

### ESM migration

Added `"type": "module"` to `package.json` (required by Hardhat 3). No existing CommonJS files were affected.

## 4. Missing Features

| Feature | Impact | Tracking |
|---|---|---|
| Gas snapshots (`forge snapshot`) | Cannot run `snapshot` script via Hardhat | [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) |
| Deployment scripts (`forge script`) | `script/DeployAquaRouter.s.sol` has no Hardhat equivalent | No direct equivalent in Hardhat 3 |
| Custom compiler binary (`[profile.solx]`) | Cannot use `solx` compiler via Hardhat | Foundry-only feature |
| Formatter (`[fmt]`) | No `forge fmt` equivalent in Hardhat | Use prettier-plugin-solidity or solhint |

## 5. Verdict

**Successful with gaps** — All 49 Solidity tests pass. Compilation succeeds. The gaps are:

1. **Gas snapshots** — no Hardhat equivalent yet (tracking issue exists)
2. **Deployment scripts** — `forge script` has no Hardhat counterpart
3. **Custom compiler binary** (`solx` profile) — Foundry-only
4. **Formatter** — Foundry-only (`forge fmt`)

None of these gaps affect compilation or test execution. The core development workflow (compile + test) has full parity.
