# Aqua Protocol

[![Github Release](https://img.shields.io/github/v/tag/1inch/aqua?sort=semver&label=github)](https://github.com/1inch/aqua/releases/latest)
[![CI](https://github.com/1inch/aqua/actions/workflows/ci.yml/badge.svg)](https://github.com/1inch/aqua/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/Coverage-61.54%25-yellow)](https://github.com/1inch/aqua)
[![Tests](https://img.shields.io/github/actions/workflow/status/1inch/aqua/ci.yml?branch=main&label=tests)](https://github.com/1inch/aqua/actions)
[![npm](https://img.shields.io/npm/v/@1inch/aqua.svg)](https://www.npmjs.com/package/@1inch/aqua)
[![License](https://img.shields.io/badge/License-Degensoft--Aqua--Source--1.1-orange)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://docs.soliditylang.org/en/v0.8.30/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://book.getfoundry.sh/)
[![Whitepaper](https://img.shields.io/badge/Whitepaper-Dev%20Preview-informational)](whitepaper/aqua-dev-preview.md)

Shared liquidity layer protocol enabling liquidity providers to allocate balances across multiple trading strategies without fragmentation.

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Core Concepts](#core-concepts)
- [Usage](#usage)
  - [For Liquidity Providers](#for-liquidity-providers)
  - [For Traders](#for-traders)
  - [For Developers](#for-developers)
- [API Reference](#api-reference)
- [Getting Started](#getting-started)

```
Traditional AMM Pools                 Aqua Protocol
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Single LP:                                    Single LP:

   [LP]                                         [LP]($$)
    │                                              │
    ├─────────┬─────────┐                          │
    │         │         │                          │
    │         │         │                      ┌───▼────┐
┌───▼────┐┌───▼────┐┌───▼────┐                 │  Aqua  │
│  AMM   ││  AMM   ││  AMM   │                 └───┬────┘
│ Pool A ││ Pool B ││ Pool C │                     │
│  ($$)  ││  ($$)  ││  ($$)  │            ┌────────┼────────┐
└───┬────┘└───┬────┘└───┬────┘            │        │        │
    │         │         │                 │        │        │
 [Taker]   [Taker]   [Taker]          ┌───▼───┐┌───▼───┐┌───▼───┐
                                      │ Aqua  ││ Aqua  ││ Aqua  │
                                      │ AMM A ││ AMM B ││ AMM C │
                                      └───┬───┘└───┬───┘└───┬───┘
                                          │        │        │
                                      [Taker]   [Taker]   [Taker]

❌ Traditional AMM Pools:              ✅ Aqua Protocol:
   • Liquidity fragmented across         • Shared liquidity via AQUA
     multiple isolated pools               virtual balances
   • Capital ($$) locked in pools        • Capital ($$) stays in wallet
```

## Overview

Traditional DeFi protocols fragment liquidity by locking it in isolated pools. Aqua solves this through a registry-based allowance system where liquidity providers maintain a single token approval while distributing virtual balances across multiple strategies.

**Key Benefits:**
- **Unified Liquidity**: Single approval enables participation in unlimited strategies
- **Capital Efficiency**: Share liquidity across protocols without redeployment
- **Granular Control**: Per-strategy balance management
- **No Custody**: Tokens remain in LP wallets, only virtual balances tracked

## Architecture

### Components

**Aqua.sol** - Core registry contract
- Stores virtual balances: `balances[maker][app][strategyHash][token]`
- Manages lifecycle: `ship()`, `dock()`
- Provides swap interface: `pull()`, `push()`

**AquaApp** - Base contract for trading applications
- Inherits to build AMMs, limit orders, auctions, etc.
- Accesses liquidity via Aqua interface
- Enforces reentrancy protection for safe callbacks

**Strategy** - Configuration identifier
- Defined by app-specific struct (e.g., token pair, fee, parameters)
- Identified by `keccak256(abi.encode(strategy))`
- Immutable once shipped

## Core Concepts

### Virtual Balances

Aqua doesn't hold tokens - it maintains allowance records. Actual tokens remain in maker wallets until pulled during trades.

```solidity
mapping(address maker =>
    mapping(address app =>
        mapping(bytes32 strategyHash =>
            mapping(address token => Balance)))) private _balances;
```

**Important:** Funds ($$$) always stay in the LP's wallet. AQUA only tracks virtual balance allocations.

### Strategy Hash

Uniquely identifies strategy configurations:

```solidity
bytes32 strategyHash = keccak256(abi.encode(strategy));
```

Ensures same parameters always produce same identifier.

### Strategy Immutability

**Once a strategy is shipped, it becomes completely immutable:**
- ✗ Parameters cannot be changed (e.g., fee rates, token pairs, weights)
- ✗ Initial liquidity amounts cannot be modified
- ✓ Token balances change ONLY through swap execution via `pull()`/`push()`

**Why Immutability?**

Immutable data structures significantly reduce bugs in concurrent and distributed systems. As noted in the seminal paper ["Out of the Tar Pit"](https://curtclifton.net/papers/MoseleyMarks06a.pdf) by Ben Moseley and Peter Marks, immutability eliminates entire classes of bugs related to state management and makes systems vastly easier to reason about.

**Easy Re-parameterization:**

Since strategies don't own funds (tokens remain in your wallet with approval), you can easily adjust parameters:
1. `dock(strategyHash)` - Withdraws virtual balances (no token transfers, just accounting)
2. `ship(newStrategy)` - Creates new strategy with updated parameters and/or liquidity allocations

This flexibility combines the safety of immutability with practical adaptability.

### Pull/Push Interface

> **⚡ Important: Swap Execution Only**
>
> `pull()` and `push()` are used exclusively during swap execution to transfer tokens between makers and takers.
> They are **NOT** used for liquidity management. Initial liquidity is set via `ship()` and shouldn't be modified afterward.

**Pull**: App withdraws tokens from maker to trader during swap
```solidity
aqua.pull(maker, strategyHash, tokenOut, amountOut, recipient);
```

**Push**: Trader deposits tokens into maker's strategy balance during swap
```solidity
aqua.push(maker, app, strategyHash, tokenIn, amountIn);
```

**Liquidity Management:**
- Add liquidity → Use `ship()` to create new strategy
- Remove liquidity → Use `dock()` to withdraw from strategy
- Change parameters → Use `dock()` then `ship()` new strategy

## Usage

### For Liquidity Providers

> **💡 Strategy Management**
>
> - **Immutable**: Once shipped, parameters and initial liquidity are locked
> - **No custody**: Your tokens stay in your wallet with approval to Aqua
> - **Easy updates**: `dock()` → `ship()` to change parameters (no token transfers needed)
> - **Safer code**: Immutability means fewer bugs and easier integration for traders

**1. Approve tokens to Aqua** (one-time)
```solidity
token.approve(address(aqua), type(uint256).max);
```

**2. Ship a strategy**
```solidity
XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
    maker: msg.sender,
    token0: DAI,
    token1: USDC,
    feeBps: 30,  // 0.3%
    salt: bytes32(0)
});

address[] memory tokens = new address[](2);
tokens[0] = DAI;
tokens[1] = USDC;

uint256[] memory amounts = new uint256[](2);
amounts[0] = 1000e18;  // 1000 DAI
amounts[1] = 1000e6;   // 1000 USDC

bytes32 strategyHash = aqua.ship(
    address(xycSwapApp),
    abi.encode(strategy),
    tokens,
    amounts
);
```

**3. Manage strategies**
```solidity
// Check balance
(uint256 balanceIn, balanceOut) = aqua.safeBalances(maker, app, strategyHash, tokenIn, tokenOut);

// Withdraw liquidity and deactivate strategy
aqua.dock(app, strategyHash, tokens);

// To change parameters or liquidity:
// 1. dock() existing strategy
// 2. ship() new strategy with updated params
```

### For Traders

**1. Implement specific callback interface**
```solidity
contract Trader is IAquaAppSwapCallback {
    function aquaAppSwapCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata takerData
    ) external override {
        // Transfer tokenIn to complete the swap (requires token approval)
        // This is the ONLY appropriate use of push() - during swap execution
        IERC20(tokenIn).forceApprove(aqua, amountIn);
        aqua.push(maker, app, strategyHash, tokenIn, amountIn);
    }
}
```

**2. Execute trades**
```solidity
aquaApp.swapExactIn(
    strategy,
    true,              // zeroForOne
    1e18,              // amountIn
    0.99e18,           // amountOutMin
    address(this),     // recipient
    ""                 // takerData
);
```

### For Developers

**1. Inherit from AquaApp**
```solidity
contract MyAMM is AquaApp {
    constructor(IAqua aqua) AquaApp(aqua) {}

    struct Strategy {
        address maker; // Must-have to make strategyHash unique per user
        address token0;
        address token1;
        // ... strategy parameters (IMMUTABLE once shipped)
    }
}
```

**2. Implement trading logic**
```solidity
function swap(
    Strategy calldata strategy,
    bool isZeroForOne,
    uint256 amountIn
)
    external
    nonReentrantStrategy(keccak256(abi.encode(strategy)))
    returns (uint256 amountOut)
{
    bytes32 strategyHash = keccak256(abi.encode(strategy));

    address tokenIn = isZeroForOne ? strategy.token0 : strategy.token1;
    address tokenOut = isZeroForOne ? strategy.token1 : strategy.token0;

    (uint256 balanceIn, uint256 balanceOut) = AQUA.safeBalances(strategy.maker, address(this), strategyHash, tokenIn, tokenOut);

    amountOut = // ... compute output amount based on AMM logic
    uint256 expectedBalanceIn = balanceIn + amountIn;

    // Pull output tokens to recipient (SWAP EXECUTION)
    AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, recipient);

    // Callback for input tokens
    IXYCSwapCallback(msg.sender).xycSwapCallback(
        tokenIn, tokenOut, amountIn, amountOut,
        strategy.maker, address(this), strategyHash, takerData
    );

    // Verify input received (SWAP EXECUTION)
    _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, expectedBalanceIn);
}
```

Method AquaApp._safeCheckAquaPush() is efficient but requires reentrancy protection to prevent nested swaps. Another option is to manually transfer tokens from taker and push to Aqua, no reentrancy protection needed:

```solidity
function swap(
    Strategy calldata strategy,
    bool isZeroForOne,
    uint256 amountIn
) external returns (uint256 amountOut) {
    bytes32 strategyHash = keccak256(abi.encode(strategy));

    address tokenIn = isZeroForOne ? strategy.token0 : strategy.token1;
    address tokenOut = isZeroForOne ? strategy.token1 : strategy.token0;

    (uint256 balanceIn, uint256 balanceOut) = AQUA.safeBalances(strategy.maker, address(this), strategyHash, tokenIn, tokenOut);

    amountOut = // ... compute output amount based on AMM logic

    // Pull output tokens to recipient (SWAP EXECUTION)
    AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, recipient);

    // Transfer input tokens from taker and push to Aqua (SWAP EXECUTION)
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenIn).approve(address(AQUA), amountIn);
    AQUA.push(strategy.maker, address(this), strategyHash, tokenIn, amountIn);
}
```

**Safe Balance Queries**

Use `safeBalances()` when you need to ensure that queried tokens are part of the active strategy. This is particularly important for:
- Multi-token AMM strategies
- Strategies with multiple tokens
- Verifying strategy validity before executing swaps

The function reverts if any token is not part of the strategy, preventing calculation errors.

```solidity
// Safe balance check before swap
(uint256 balanceIn, uint256 balanceOut) = AQUA.safeBalances(
    strategy.maker, 
    address(this), 
    strategyHash, 
    tokenIn,
    tokenOut
);
// Transaction reverts if any token is not in the strategy
```

**Taker example Implementation**
```solidity
contract SimpleTrader is IXYCSwapCallback {
    IAqua public immutable AQUA;

    constructor(IAqua _aqua, IERC20[] memory tokens) {
        AQUA = _aqua;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].approve(address(AQUA), type(uint256).max);
        }
    }

    function swap(
        XYCSwap app,
        XYCSwap.Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn
    ) external {
        app.swapExactIn(
            strategy,
            zeroForOne,
            amountIn,
            0,           // amountOutMin (calculate properly in production)
            msg.sender,  // recipient
            ""           // takerData
        );
    }

    function xycSwapCallback(
        address tokenIn,
        address,  // tokenOut
        uint256 amountIn,
        uint256,  // amountOut
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata
    ) external override {
        // Transfer input tokens to complete swap (SWAP EXECUTION ONLY)
        AQUA.push(maker, app, strategyHash, tokenIn, amountIn);
    }
}
```

## API Reference

### Aqua Core

```solidity
// Liquidity Lifecycle Management
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Ship new strategy with initial balances (immutable after creation)
function ship(
    address app,
    bytes calldata strategy,
    address[] calldata tokens,
    uint256[] calldata amounts
) external returns(bytes32 strategyHash);

// Deactivate strategy and withdraw all balances
function dock(
    address app,
    bytes32 strategyHash,
    address[] calldata tokens
) external;

// Swap Execution Only
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Pull tokens from maker during swap (called by apps)
function pull(
    address maker,
    bytes32 strategyHash,
    address token,
    uint256 amount,
    address to
) external;

// Push tokens to maker's strategy balance during swap
function push(
    address maker,
    address app,
    bytes32 strategyHash,
    address token,
    uint256 amount
) external;

// Queries
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Query virtual balance
function rawBalances(
    address maker,
    address app,
    bytes32 strategyHash,
    address token
) external view returns (uint248 balance, uint8 tokensCount);

// Query multiple token balances with active strategy validation
// Reverts if any token is not part of the active strategy
function safeBalances(
    address maker,
    address app,
    bytes32 strategyHash,
    address token0,
    address token1
) external view returns (uint256 balance0, uint256 balance1);
```

### AquaApp Base Contract

```solidity
// Immutable reference to Aqua registry
IAqua public immutable AQUA;

// Reentrancy locks per strategy (strategyHash already includes maker)
mapping(bytes32 strategyHash => TransientLock) internal _reentrancyLocks;

// Convenient modifier for reentrancy protection
modifier nonReentrantStrategy(bytes32 strategyHash);

// Helper to verify taker deposited tokens (requires reentrancy protection)
function _safeCheckAquaPush(
    address maker,
    bytes32 strategyHash,
    address token,
    uint256 expectedBalance
) internal view;
```

## Getting Started

```bash
# Clone repository
git clone https://github.com/1inch/aqua
cd aqua

# Install dependencies
forge install

# Run tests
forge test
```

## Deployments

The Aqua Protocol is deployed across multiple networks at the same address:

**Contract Address:** `0x499943e74fb0ce105688beee8ef2abec5d936d31`

### Supported Networks

| Network | Contract Address |
|---------|-----------------|
| Ethereum Mainnet | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Base | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Optimism | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Polygon | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Arbitrum | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Avalanche | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Binance Smart Chain | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Linea | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Sonic | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Unichain | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| Gnosis | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |
| zkSync | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |


## License

This project is licensed under the **LicenseRef-Degensoft-Aqua-Source-1.1**

See the [LICENSE](LICENSE) file for details.
See the [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) file for information about third-party software, libraries, and dependencies used in this project.

**Contact for licensing inquiries:**
- 📧 license@degensoft.com 
- 📧 legal@degensoft.com
