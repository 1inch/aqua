// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title IShipHook
/// @notice Hook interface for apps to handle pre-ship operations
/// @dev Apps can implement this to handle native ETH wrapping or other pre-ship logic
interface IShipHook {
    /// @notice Called by Aqua before processing ship when ETH is sent
    /// @dev The hook receives the ETH and should handle it appropriately
    ///      For ETH wrapping: wrap to WETH and transfer to maker
    /// @param maker The maker address who is shipping the strategy
    /// @param strategyHash The hash of the strategy being shipped
    /// @param tokens Array of token addresses in the strategy
    /// @param amounts Array of amounts for each token
    /// @return success True if hook processed successfully
    function beforeShip(
        address maker,
        bytes32 strategyHash,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (bool success);
}
