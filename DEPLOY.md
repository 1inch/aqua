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

Configured networks live in `hardhat.config.ts` (`localhost`, `sepolia`, `mainnet`); add more by copying the pattern. See `.env.example` for the full list of variable names.

## 2. Deploy

Deploy with `hardhat ignition` through a wrapped script that injects the `owner`:

```bash
npx hardhat run ./script/deployAquaRouter.ts --network <network>
```

### Automation Mode (Automated deployment framework)

For automated deployments .env.automation file will be created automatically and deployment is launched with:

```bash
OPS_LAUNCH_MODE=auto make deploy-aqua-router
```

### Deployment Artifacts

Deployment information is saved in:

- `ignition/deployments/chain-<chainId>

## Helper Commands

### Development Tools

| Command         | Description                       |
| --------------- | --------------------------------- |
| `make build`    | Compile all contracts             |
| `make tests`    | Run test suite with gas reporting |
| `make coverage` | Generate code coverage report     |
| `make snapshot` | Create gas snapshot               |
| `make format`   | Format code using Forge formatter |
| `make lint`     | Check code formatting             |
| `make clean`    | Clean build artifacts             |

### Local Development

Start local development node fork:

```bash
make node NODE_URL=<your-rpc-url>
```
