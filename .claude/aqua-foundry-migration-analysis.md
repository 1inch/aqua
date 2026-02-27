# Aqua — Foundry Migration Analysis

## foundry.toml Sections & Settings

### `[profile.default]`
| Setting | Value |
|---|---|
| `solc` | `"0.8.30"` |
| `optimizer` | `true` |
| `optimizer_runs` | `10_000_000` |
| `via_ir` | `true` |
| `libs` | `["node_modules", "lib"]` |
| `fs_permissions` | `[{ access = "read-write", path = "./deployments" }, { access = "read-write", path = "./config" }]` |

### `[profile.ci]`
Identical to `[profile.default]` — same solc version, optimizer, via_ir, libs, and fs_permissions.

### `[profile.solx]`
| Setting | Value |
|---|---|
| `solc` | `"~/.local/bin/solx"` — custom compiler binary |

### `[fmt]`
| Setting | Value |
|---|---|
| `single_line_statement_blocks` | `"multi"` |
| `multiline_func_header` | `"all"` |
| `override_spacing` | `false` |
| `bracket_spacing` | `true` |
| `int_types` | `"long"` |
| `number_underscore` | `"thousands"` |

## Remappings (`remappings.txt`)
```
forge-std/=node_modules/forge-std/src/
@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/
@1inch/solidity-utils/=node_modules/@1inch/solidity-utils/
```

## Submodules
None — no `.gitmodules` file, no `lib/` directory. All dependencies are npm-based.

## Directory Structure
- **Source:** `src/` — `Aqua.sol`, `AquaApp.sol`, `AquaRouter.sol`, `interfaces/`, `libs/`
- **Tests:** `test/` — 6 test files (`.t.sol`), `base/`, `mock/`, `utils/`
- **Scripts:** `script/` — `DeployAquaRouter.s.sol`
- **Examples:** `examples/apps/` (contracts), `examples/test/` (2 test files)

## Dependencies (from `package.json`)
- `forge-std` — GitHub dependency (`github:foundry-rs/forge-std#v1.11.0`)
- `@1inch/solidity-utils` — `6.9.2`
- `@openzeppelin/contracts` — `5.4.0`

## Lockfile
`yarn.lock` — use `yarn` for package management.

## Test Count
- `test/` directory: **49 test functions** across 6 `.t.sol` files
- `examples/test/` directory: **26 test functions** across 2 `.t.sol` files
- **Total: 75 test functions**

## Absolute Imports (8 files)
Files with `src/` or `test/` prefixed imports:
- `test/AquaEvents.t.sol` — `src/interfaces/IAqua.sol`
- `test/AquaBalances.t.sol` — `src/interfaces/IAqua.sol`
- `test/AquaPushPull.t.sol` — `src/interfaces/IAqua.sol`
- `test/AquaShipDock.t.sol` — `src/interfaces/IAqua.sol`
- `test/AquaLifecycle.t.sol` — `src/interfaces/IAqua.sol`
- `test/base/AquaTestBase.sol` — `src/Aqua.sol`, `src/interfaces/IAqua.sol`
- `examples/test/XYCNestedSwaps.t.sol` — `test/utils/Dynamic.sol`, `src/Aqua.sol`, `src/AquaApp.sol`
- `examples/test/XYCSwap.t.sol` — `test/utils/Dynamic.sol`, `src/Aqua.sol`, `src/AquaApp.sol`

**Decision:** 8 files → convert to relative imports.

## Notable Patterns
- `via_ir = true` with 10M optimizer runs — heavy optimization
- `[profile.ci]` is identical to default (no test-specific overrides)
- `[profile.solx]` uses a custom compiler binary — Foundry-only, no Hardhat equivalent
- `[fmt]` section — Foundry-only formatter config
- `forge-std` installed via npm (GitHub URL), not git submodule
- `fs_permissions` grants read-write to `./deployments` and `./config` directories
- Scripts use `forge test` and `forge snapshot --no-match-test "testFuzz_*"`
