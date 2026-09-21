// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAqua } from "../../src/interfaces/IAqua.sol";
import { IXYCSwapCallback } from "../apps/interfaces/IXYCSwapCallback.sol";
import { AquaApp } from "../../src/AquaApp.sol";

/// @title XYCSwap - Example constant product AMM implementation using Aqua
/// @notice Demonstrates how to build a swap app on top of Aqua protocol
/// @dev Uses x*y=k formula with fee deduction for price calculation
contract XYCSwap is AquaApp {
    using Math for uint256;

    /// @notice Thrown when the output amount is less than the minimum specified
    /// @param amountOut The actual output amount
    /// @param amountOutMin The minimum output amount required
    error InsufficientOutputAmount(uint256 amountOut, uint256 amountOutMin);

    /// @notice Thrown when the input amount exceeds the maximum specified
    /// @param amountIn The actual input amount required
    /// @param amountInMax The maximum input amount allowed
    error ExcessiveInputAmount(uint256 amountIn, uint256 amountInMax);

    /// @notice Strategy configuration for a liquidity pool
    /// @param maker The liquidity provider's address
    /// @param token0 The first token in the pair
    /// @param token1 The second token in the pair
    /// @param feeBps The swap fee in basis points (1 bps = 0.01%)
    /// @param salt Unique identifier to allow multiple strategies with same parameters
    struct Strategy {
        address maker;
        address token0;
        address token1;
        uint256 feeBps;
        bytes32 salt;
    }

    /// @notice Base for basis points calculations (100% = 10_000 bps)
    uint256 internal constant BPS_BASE = 10_000;

    /// @notice Initializes the XYCSwap app with an Aqua protocol instance
    /// @param aqua_ The Aqua protocol contract address
    constructor(IAqua aqua_) AquaApp(aqua_) { }

    /// @notice Calculates the output amount for a given input amount
    /// @param strategy The strategy configuration
    /// @param zeroForOne If true, swap token0 for token1; otherwise swap token1 for token0
    /// @param amountIn The input amount
    /// @return amountOut The calculated output amount
    function quoteExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountOut = _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
    }

    /// @notice Calculates the input amount required for a given output amount
    /// @param strategy The strategy configuration
    /// @param zeroForOne If true, swap token0 for token1; otherwise swap token1 for token0
    /// @param amountOut The desired output amount
    /// @return amountIn The required input amount
    function quoteExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountIn = _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
    }

    /// @notice Executes a swap with exact input amount
    /// @param strategy The strategy configuration
    /// @param zeroForOne If true, swap token0 for token1; otherwise swap token1 for token0
    /// @param amountIn The exact input amount
    /// @param amountOutMin The minimum acceptable output amount
    /// @param to The recipient address for output tokens
    /// @param takerData Arbitrary data passed to the callback
    /// @return amountOut The actual output amount
    function swapExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        bytes calldata takerData
    )
        external
        nonReentrantStrategy(strategy.maker, keccak256(abi.encode(strategy)))
        returns (uint256 amountOut)
    {
        bytes32 strategyHash = keccak256(abi.encode(strategy));

        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountOut = _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
        require(amountOut >= amountOutMin, InsufficientOutputAmount(amountOut, amountOutMin));

        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        IXYCSwapCallback(msg.sender).xycSwapCallback(tokenIn, tokenOut, amountIn, amountOut, strategy.maker, address(this), strategyHash, takerData);
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
    }

    /// @notice Executes a swap with exact output amount
    /// @param strategy The strategy configuration
    /// @param zeroForOne If true, swap token0 for token1; otherwise swap token1 for token0
    /// @param amountOut The exact output amount desired
    /// @param amountInMax The maximum acceptable input amount
    /// @param to The recipient address for output tokens
    /// @param takerData Arbitrary data passed to the callback
    /// @return amountIn The actual input amount used
    function swapExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        bytes calldata takerData
    )
        external
        nonReentrantStrategy(strategy.maker, keccak256(abi.encode(strategy)))
        returns (uint256 amountIn)
    {
        bytes32 strategyHash = keccak256(abi.encode(strategy));

        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountIn = _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
        require(amountIn <= amountInMax, ExcessiveInputAmount(amountIn, amountInMax));

        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        IXYCSwapCallback(msg.sender).xycSwapCallback(tokenIn, tokenOut, amountIn, amountOut, strategy.maker, address(this), strategyHash, takerData);
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
    }

    /// @dev Calculates output using constant product formula with fee
    /// @param strategy The strategy configuration
    /// @param balanceIn Current balance of input token
    /// @param balanceOut Current balance of output token
    /// @param amountIn The input amount
    /// @return amountOut The calculated output amount
    function _quoteExactIn(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountIn
    ) internal view virtual returns (uint256 amountOut) {
        // Use constant product formula (x*y=const) after fee deduction:
        // balanceIn * balanceOut == (balanceIn + amountIn) * (balanceOut - amountOut)
        uint256 amountInWithFee = amountIn * (BPS_BASE - strategy.feeBps) / BPS_BASE;
        amountOut = (amountInWithFee * balanceOut) / (balanceIn + amountInWithFee);
    }

    /// @dev Calculates input using constant product formula with fee
    /// @param strategy The strategy configuration
    /// @param balanceIn Current balance of input token
    /// @param balanceOut Current balance of output token
    /// @param amountOut The desired output amount
    /// @return amountIn The required input amount
    function _quoteExactOut(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountOut
    ) internal view virtual returns (uint256 amountIn) {
        // Use constant product formula (x*y=const) after fee deduction:
        // balanceIn * balanceOut == (balanceIn + amountIn) * (balanceOut - amountOut)
        uint256 amountOutWithFee = amountOut * BPS_BASE / (BPS_BASE - strategy.feeBps);
        amountIn = (balanceIn * amountOutWithFee).ceilDiv(balanceOut - amountOutWithFee);
    }

    /// @dev Determines input/output tokens and their balances based on swap direction
    function _getInAndOut(Strategy calldata strategy, bytes32 strategyHash, bool zeroForOne) private view returns (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) {
        tokenIn = zeroForOne ? strategy.token0 : strategy.token1;
        tokenOut = zeroForOne ? strategy.token1 : strategy.token0;
        (balanceIn, balanceOut) = AQUA.safeBalances(strategy.maker, address(this), strategyHash, tokenIn, tokenOut);
    }
}
