// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title IXYCSwapCallback - Callback interface for XYCSwap operations
/// @notice Interface that must be implemented by contracts initiating swaps on XYCSwap
/// @dev The callback is invoked after the output tokens are sent but before input validation
interface IXYCSwapCallback {
    /// @notice Called on the swap initiator after output tokens are transferred
    /// @dev The caller must push the required input tokens to the maker's Aqua balance
    /// @param tokenIn The input token address that needs to be pushed
    /// @param tokenOut The output token address that was pulled
    /// @param amountIn The required input amount to push
    /// @param amountOut The output amount that was sent to recipient
    /// @param maker The maker (liquidity provider) address
    /// @param app The XYCSwap app address
    /// @param strategyHash The hash of the strategy being used
    /// @param takerData Arbitrary data passed through from the swap call
    function xycSwapCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address maker,
        address app,
        bytes32 strategyHash,
        bytes calldata takerData
    ) external;
}
