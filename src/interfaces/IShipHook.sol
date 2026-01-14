// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title IShipHook
/// @notice Hook interface for apps to handle ship lifecycle operations
/// @dev Apps can implement these hooks to handle:
///      - beforeShip: Native ETH wrapping, pre-validation, setup
///      - afterShip: Notifications, additional state setup, external calls
///
/// Hooks are optional and controlled via the `hooks` flags parameter in ship():
///   - HOOK_BEFORE (0x01): Call beforeShip before balance storage
///   - HOOK_AFTER (0x02): Call afterShip after balance storage
///   - HOOK_BOTH (0x03): Call both hooks
interface IShipHook {
    /// @notice Called by Aqua BEFORE processing ship (when HOOK_BEFORE flag is set)
    /// @dev Use for: ETH wrapping, pre-validation, setup
    ///      The hook receives ETH if msg.value > 0 and should handle it appropriately
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

    /// @notice Called by Aqua AFTER ship is completed (when HOOK_AFTER flag is set)
    /// @dev Use for: notifications, additional state setup, external calls
    ///      Called after balances are stored, so strategy is already active
    /// @param maker The maker address who shipped the strategy
    /// @param strategyHash The hash of the strategy that was shipped
    /// @param tokens Array of token addresses in the strategy
    /// @param amounts Array of amounts for each token
    function afterShip(
        address maker,
        bytes32 strategyHash,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;
}
