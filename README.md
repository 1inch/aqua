# Aqua Protocol

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

## Overview

Traditional DeFi protocols fragment liquidity by locking it in isolated pools. Aqua solves this through a registry-based allowance system where liquidity providers maintain a single token approval while distributing virtual balances across multiple strategies.

**Key Benefits:**
- **Unified Liquidity**: Single approval enables participation in unlimited strategies
- **Capital Efficiency**: Share liquidity across protocols without redeployment
- **Granular Control**: Per-strategy balance management
- **Gas Optimized**: Minimal storage overhead using balance packing

## Architecture

### Components

**Aqua.sol** - Core registry contract
- Stores virtual balances: `balances[maker][app][strategyHash][token]`
- Manages lifecycle: `ship()`, `dock()`
- Provides access interface: `pull()`, `push()`

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

### Strategy Hash

Uniquely identifies strategy configurations:

```solidity
bytes32 strategyHash = keccak256(abi.encode(strategy));
```

Ensures same parameters always produce same identifier.

### Pull/Push Interface

**Pull**: App withdraws tokens from maker to trader
```solidity
aqua.pull(maker, strategyHash, tokenOut, amountOut, recipient);
```

**Push**: Anyone deposits tokens into maker's strategy balance
```solidity
aqua.push(maker, app, strategyHash, tokenIn, amountIn);
```

## Usage

### For Liquidity Providers

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

**3. Manage balances**
```solidity
// Check balance
uint256 balance = aqua.balances(maker, app, strategyHash, token);

// Deactivate strategy
aqua.dock(app, strategyHash, tokens);
```

### For Traders

**1. Implement callback interface**
```solidity
contract Trader is IAquaTakerCallback {
    function aquaTakerCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata data
    ) external override {
        // Transfer tokenIn to complete the swap (requires token approval)
        aqua.push(maker, app, strategyHash, tokenIn, amountIn);
    }
}
```

**2. Execute trades**
```solidity
xycSwap.swapExactIn(
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
        // ... strategy parameters
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

    uint256 balanceIn = AQUA.balances(strategy.maker, address(this), strategyHash, tokenIn);
    uint256 balanceOut = AQUA.balances(strategy.maker, address(this), strategyHash, tokenOut);

    amountOut = // ... compute output amount based on AMM logic
    uint256 expectedBalanceIn = balanceIn + amountIn;
    
    // Pull output tokens to recipient
    AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, recipient);
    
    // Callback for input tokens
    IAquaTakerCallback(msg.sender).aquaTakerCallback(
        tokenIn, tokenOut, amountIn, amountOut,
        strategy.maker, address(this), strategyHash, takerData
    );
    
    // Verify input received
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

    uint256 balanceIn = AQUA.balances(strategy.maker, address(this), strategyHash, tokenIn);
    uint256 balanceOut = AQUA.balances(strategy.maker, address(this), strategyHash, tokenOut);

    amountOut = // ... compute output amount based on AMM logic
    
    // Pull output tokens to recipient
    AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, recipient);

    // Transfer input tokens from taker and push to Aqua
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenIn).approve(address(AQUA), amountIn);
    AQUA.push(strategy.maker, address(this), strategyHash, tokenIn, amountIn);
}
```

**Taker Implementation**
```solidity
contract SimpleTrader is IAquaTakerCallback {
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
    
    function aquaTakerCallback(
        address tokenIn,
        address,  // tokenOut
        uint256 amountIn,
        uint256,  // amountOut
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata
    ) external override {
        // Transfer input tokens to complete swap
        AQUA.push(maker, app, strategyHash, tokenIn, amountIn);
    }
}
```

## API Reference

### Aqua Core

```solidity
// Ship new strategy with initial balances
function ship(
    address app,
    bytes calldata strategy,
    address[] calldata tokens,
    uint256[] calldata amounts
) external returns(bytes32 strategyHash);

// Deactivate strategy
function dock(
    address app,
    bytes32 strategyHash,
    address[] calldata tokens
) external;

// Pull tokens from maker (called by apps)
function pull(
    address maker,
    bytes32 strategyHash,
    address token,
    uint256 amount,
    address to
) external;

// Push tokens to maker's strategy balance
function push(
    address maker,
    address app,
    bytes32 strategyHash,
    address token,
    uint256 amount
) external;

// Query balance
function balances(
    address maker,
    address app,
    bytes32 strategyHash,
    address token
) external view returns (uint256);
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

### Callback Interfaces

```solidity
interface IAquaTakerCallback {
    function aquaTakerCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata data
    ) external;
}
```

## Getting Started

```bash
# Clone repository
git clone https://github.com/1inch/aqua
cd aqua

# Install dependencies
forge install

# Build project
forge build

# Run tests
forge test

# Run specific test
forge test --match-test testXYCSwap -vvv
```

## License

LicenseRef-Degensoft-ARSL-1.0-Audit
