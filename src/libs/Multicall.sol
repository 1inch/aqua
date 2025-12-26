// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title Multicall - Batch Execution Utility
/// @notice Allows batching multiple calls to this contract via delegatecall for atomic operations
/// @dev Intended for inheritance. Be cautious of recursion in batched calldata.
contract Multicall {
    /// @notice Execute multiple calls in a single transaction
    /// @dev Each call is executed via delegatecall. If any call fails, the entire transaction reverts.
    /// @param data Array of encoded function calls to execute
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success,) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
        }
    }
}
