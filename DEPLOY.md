# Aqua Deployment Guide

Aqua is deployed with [Hardhat Ignition](https://hardhat.org/ignition) and verified with `hardhat-verify`.

## Prerequisites

- Node.js + Yarn (`yarn install`)
- A funded deployer key and an RPC URL for the target network
- For verification: an Etherscan API key (v2 — a single key works across all chains)

## 1. Configure secrets (config variables)

RPC URLs and the deployer private key are Hardhat **configuration variables**. Hardhat 3 does **not** auto-load `.env`; provide them either as environment variables of the same name, or via the encrypted keystore:

```bash
# Option A — environment variables
export SEPOLIA_RPC_URL=https://...
export SEPOLIA_PRIVATE_KEY=0x...
export ETHERSCAN_API_KEY=...

# Option B — encrypted keystore (prompts for a password when the value is needed)
npx hardhat keystore set SEPOLIA_RPC_URL
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
npx hardhat keystore set ETHERSCAN_API_KEY
```

Configured networks live in `hardhat.config.ts` (`localhost`, `sepolia`); add more by copying the pattern. See `.env.example` for the full list of variable names.

## 2. Deploy

Deploy with `hardhat ignition` through a wrapped script that injects the `owner`:

```bash
npx hardhat run ./script/deployAquaRouter.ts --network <network>
```

### Deployment Artifacts

Deployment information is saved in:

- `ignition/deployments/chain-<chainId>

## Helper Commands

### Development Tools

| Command                                 | Description                              |
| --------------------------------------- | ---------------------------------------- |
| `yarn build`                            | Compile all contracts                    |
| `yarn test`                             | Run test suite                           |
| `npx hardhat test solidity --gas-stats` | Run test suite with gas reporting        |
| `npx hardhat test solidity --coverage`  | Generate code coverage report            |
| `yarn snapshot`                         | Create gas snapshot                      |
| `yarn snapshot:check`                   | Check gas against the committed snapshot |
| `yarn format`                           | Format code using Prettier               |
| `yarn lint`                             | Check code formatting                    |
| `npx hardhat clean`                     | Clean build artifacts                    |

### Local Development

Start local development node fork:

```bash
npx hardhat node --fork <your-rpc-url>
```
