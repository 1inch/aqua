# AGENTS.md

Guidance for coding agents working in this repository.

## What this repository is

Aqua is a shared liquidity layer: liquidity providers keep their tokens in their own wallets and allocate virtual balances to several trading strategies through one registry, instead of locking capital in separate pools. This repository holds the Aqua contracts (`Aqua`, the deployed `AquaRouter`, and the `AquaApp` base contract for strategy apps), their tests, an example AMM and the scripts that deploy `AquaRouter`.

## Toolchain

This project uses Hardhat 3 (`hardhat.config.ts`), with solc pinned to 0.8.30.

### Build and test

The commands to build and test this repository are in [the README's Getting Started section](README.md#getting-started), the one place they are kept. Run those rather than inventing parallel ones, and do not introduce `forge fmt`, Prettier, or another formatter unless this repository already uses one.

## Layout

| Path | Contents |
|---|---|
| `contracts/` | Protocol contracts: `Aqua` (the shared liquidity registry), `AquaRouter` (the deployed entry point, which adds simulation, multicall and token rescue), the `AquaApp` base contract for strategy apps, the `IAqua` interface and the `BalanceLib` library |
| `test/` | Solidity tests run by Hardhat, with a shared test base, an ERC-20 mock and test utilities |
| `examples/` | `XYCSwap`, an example constant-product AMM built on `AquaApp`, with its callback interface and tests |
| `script/` | The Hardhat script that deploys `AquaRouter` through the Ignition module, and a helper that reads the owner from `config/` |
| `ignition/` | The Hardhat Ignition module that deploys `AquaRouter` |
| `config/` | Deployment parameters per chain: `constants.json` holds the router owner |
| `docs/` | The Aqua 1.0 whitepaper (PDF) |
| `LICENSES/` | Full licence texts for Aqua and the third-party code it uses |
| `.github/` | GitHub Actions workflows: CI, tag, release and publish, and the Claude workflows |

Contracts live under `contracts/`, tests under `test/` and deployment scripts under `script/`. Protocol docs are Markdown under `docs/` (PDF only for whitepapers and math-heavy papers) — never commit HTML/CSS/JS documentation sites.

## Deployments and security

- Deployed addresses: [deployments.md](deployments.md).
- Vulnerability disclosure and bounty: [SECURITY.md](SECURITY.md). Never open a public issue or PR for an undisclosed vulnerability.

## Agent constraints

- Do not commit secrets, private keys, mnemonics or API keys. Do not edit a file only to delete a leaked secret — report it for rotation instead.
- Do not rewrite `SPDX-License-Identifier` headers.
- Do not change compiler `optimizer_runs` or `evm_version` unless explicitly asked — that changes bytecode.
- Keep diffs scoped: no drive-by reformatting of files you are not changing.
- Follow existing Solidity style and NatSpec conventions; public/external functions need accurate NatSpec.

## Project-specific notes

- `AquaRouter` is not upgradeable and is deployed at the same address on every chain. Its only privileged role is the owner passed to the constructor, which the deploy scripts read from `config/constants.json`; the contract uses the owner only to rescue stuck tokens and ETH (`Rescuable`).
- 1inch/swap-vm imports these contracts by their path inside the package, so moving or renaming a file under `contracts/` breaks it.
- CI also runs `yarn lint` and `yarn snapshot:check`. When a change moves gas on purpose, regenerate `.gas-snapshot` with `yarn snapshot`.
- `yarn build` and `yarn test` compile only `contracts/` and `test/`. Nothing builds `examples/`, so check changes there yourself.
