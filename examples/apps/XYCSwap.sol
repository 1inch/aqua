// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAqua } from "../../src/interfaces/IAqua.sol";
import { IXYCSwapCallback } from "../apps/interfaces/IXYCSwapCallback.sol";
import { TransientLock, TransientLockLib } from "../../src/libs/ReentrancyGuard.sol";
import { AquaApp } from "../../src/AquaApp.sol";

contract XYCSwap is AquaApp {
    using Math for uint256;
    using TransientLockLib for TransientLock;

    error InsufficientOutputAmount(uint256 amountOut, uint256 amountOutMin);
    error ExcessiveInputAmount(uint256 amountIn, uint256 amountInMax);

    struct Strategy {
        address maker;
        address token0;
        address token1;
        uint256 feeBps;
        bytes32 salt;
    }

    uint256 internal constant BPS_BASE = 10_000;

    constructor(IAqua aqua_) AquaApp(aqua_) { }

    function quoteExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountOut = _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
    }

    function quoteExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountIn = _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
    }

    function swapExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        bytes calldata takerData
    ) external returns (uint256 amountOut) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        return _swapExactIn(strategy, strategyHash, zeroForOne, amountIn, amountOutMin, to, takerData);
    }

    function _swapExactIn(
        Strategy calldata strategy,
        bytes32 strategyHash,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        bytes calldata takerData
    )
        private
        nonReentrantStrategy(strategyHash)
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountOut = _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
        require(amountOut >= amountOutMin, InsufficientOutputAmount(amountOut, amountOutMin));

        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        IXYCSwapCallback(msg.sender).xycSwapCallback(tokenIn, tokenOut, amountIn, amountOut, strategy.maker, address(this), strategyHash, takerData);
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
    }

    function swapExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        bytes calldata takerData
    ) external returns (uint256 amountIn) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        return _swapExactOut(strategy, strategyHash, zeroForOne, amountOut, amountInMax, to, takerData);
    }

    function _swapExactOut(
        Strategy calldata strategy,
        bytes32 strategyHash,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        bytes calldata takerData
    )
        private
        nonReentrantStrategy(strategyHash)
        returns (uint256 amountIn)
    {
        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = _getInAndOut(strategy, strategyHash, zeroForOne);
        amountIn = _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
        require(amountIn <= amountInMax, ExcessiveInputAmount(amountIn, amountInMax));

        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        IXYCSwapCallback(msg.sender).xycSwapCallback(tokenIn, tokenOut, amountIn, amountOut, strategy.maker, address(this), strategyHash, takerData);
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
    }

    function _quoteExactIn(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountIn
    ) internal view virtual returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * (BPS_BASE - strategy.feeBps) / BPS_BASE;
        amountOut = Math.mulDiv(amountInWithFee, balanceOut, balanceIn + amountInWithFee);
    }

    function _quoteExactOut(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountOut
    ) internal view virtual returns (uint256 amountIn) {
        uint256 amountOutWithFee = amountOut * BPS_BASE / (BPS_BASE - strategy.feeBps);
        amountIn = Math.mulDiv(balanceIn, amountOutWithFee, balanceOut - amountOutWithFee, Math.Rounding.Ceil);
    }

    function _getInAndOut(Strategy calldata strategy, bytes32 strategyHash, bool zeroForOne) private view returns (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) {
        tokenIn = zeroForOne ? strategy.token0 : strategy.token1;
        tokenOut = zeroForOne ? strategy.token1 : strategy.token0;
        (balanceIn, balanceOut) = AQUA.safeBalances(strategy.maker, address(this), strategyHash, tokenIn, tokenOut);
    }
}
