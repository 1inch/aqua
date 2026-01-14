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
/// ## Hook Flags
/// Hooks are optional and controlled via the `hooks` flags parameter in ship():
///   - HOOK_NONE (0x00): No hooks called
///   - HOOK_BEFORE (0x01): Call beforeShip before balance storage
///   - HOOK_AFTER (0x02): Call afterShip after balance storage  
///   - HOOK_BOTH (0x03): Call both hooks
///
/// ## Interface Validation
/// Aqua does NOT verify that the app implements IShipHook before calling hooks.
/// If an app address is used with hooks enabled but doesn't implement IShipHook,
/// the call will revert. This is intentional to avoid gas overhead of ERC-165 checks.
/// Apps should only set hook flags if they implement the corresponding hook methods.
///
/// ## Error Handling
/// - beforeShip: MUST return true on success. Returning false or reverting will
///   cause the entire ship() transaction to revert. Use this for critical validation.
/// - afterShip: Any revert will propagate and cause ship() to fail. Since afterShip
///   is called AFTER balances are stored, apps should handle errors gracefully
///   if the hook failure shouldn't block the ship operation.
///
/// ## When to Return False vs Revert in beforeShip
/// - Return false: For expected failures that should block ship with a clear error
/// - Revert with custom error: For unexpected failures with detailed error info
/// Both will cause ship() to revert, but returning false uses ShipHookFailed error.
interface IShipHook {
    /// @notice Called by Aqua BEFORE processing ship (when HOOK_BEFORE flag is set)
    /// @dev Use for: ETH wrapping, pre-validation, setup
    ///
    /// ## ETH Handling
    /// The hook receives ETH via msg.value if sent with ship(). For ETH wrapping:
    /// 1. Wrap ETH to WETH: WETH.deposit{value: msg.value}()
    /// 2. Transfer WETH to maker: WETH.transfer(maker, msg.value)
    /// This allows the maker to have WETH for the strategy without pre-wrapping.
    ///
    /// ## Return Value
    /// - Return true: Hook succeeded, continue with ship
    /// - Return false: Hook failed, revert ship with ShipHookFailed error
    /// - Revert: Propagates to ship() caller
    ///
    /// ## Security
    /// This hook is called BEFORE balances are stored. Any state changes made here
    /// will be reverted if the ship fails. The hook is protected by reentrancy guard.
    ///
    /// @param maker The maker address who is shipping the strategy
    /// @param strategyHash The hash of the strategy being shipped (keccak256 of strategy bytes)
    /// @param tokens Array of token addresses in the strategy
    /// @param amounts Array of amounts for each token
    /// @return success True if hook processed successfully, false to revert ship
    function beforeShip(
        address maker,
        bytes32 strategyHash,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (bool success);

    /// @notice Called by Aqua AFTER ship is completed (when HOOK_AFTER flag is set)
    /// @dev Use for: notifications, additional state setup, external calls
    ///
    /// ## Execution Context
    /// Called AFTER balances are stored, so strategy is already active in Aqua.
    /// If this hook reverts, the entire ship() transaction reverts, including
    /// the balance storage. Apps should handle non-critical failures gracefully.
    ///
    /// ## No Return Value
    /// Unlike beforeShip, afterShip has no return value. This is intentional:
    /// - afterShip is for side effects (notifications, external calls)
    /// - If it fails, it should revert (no silent failures)
    /// - The pattern matches common callback patterns (no boolean dance)
    ///
    /// ## Security
    /// This hook is called AFTER state changes but still within the reentrancy guard.
    /// Reentering ship() from this hook will revert.
    ///
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
