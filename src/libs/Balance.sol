// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @notice Packed balance structure for gas-efficient storage
/// @dev Uses a single storage slot: amount (248 bits) + tokensCount (8 bits)
/// @param amount The token balance amount (max 2^248 - 1)
/// @param tokensCount The number of tokens in the strategy (0 = inactive, 0xFF = docked)
struct Balance {
    uint248 amount;
    uint8 tokensCount;
}

/// @title BalanceLib - Gas-optimized balance storage operations
/// @notice Provides single-SLOAD/SSTORE operations for packed Balance struct
library BalanceLib {
    /// @notice Loads packed balance and token count data from storage using exactly 1 SLOAD
    /// @dev Assembly implementation avoids bitmasking `amount` to save gas, returning the unmasked slot word
    /// @param balance The storage pointer to the Balance struct
    /// @return rawSlot The full raw 256-bit storage word (lower 248 bits contain the balance amount)
    /// @return tokensCount The number of tokens in the strategy (extracted from the highest 8 bits)
    function load(Balance storage balance) internal view returns (uint256 rawSlot, uint8 tokensCount) {
        assembly ("memory-safe") {
            rawSlot := sload(balance.slot)
            tokensCount := shr(248, rawSlot)
        }
    }

    /// @notice Stores a new balance and token count, ensuring safe 248-bit boundaries
    /// @dev Replaces SafeCast library with native Yul panic for gas efficiency
    function set(Balance storage balance, uint256 amount, uint8 tokensCount) internal {
        assembly ("memory-safe") {
            let max248 := shr(8, not(0))

            if gt(amount, max248) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(0x11)
                mstore(0x04, 0x11)
                revert(0x00, 0x24)
            }

            let packed := or(amount, shl(248, tokensCount))
            sstore(balance.slot, packed)
        }
    }

    /// @notice Safely increases the packed balance by a specified amount using in-place addition.
    /// @dev Utilizes Yul assembly to bypass bitmasking and repacking overhead.
    /// Reverts with standard Solidity arithmetic Panic (0x11) if the new balance exceeds the 248-bit limit.
    /// @param balance The storage pointer to the packed Balance struct.
    /// @param rawSlot The current unmasked 256-bit storage word (lower 248 bits: balance, upper 8 bits: tokensCount).
    /// @param amount The token amount to add to the current balance.
    function increase(Balance storage balance, uint256 rawSlot, uint256 amount) internal {
        assembly ("memory-safe") {
            let max248 := shr(8, not(0))
            let prevBalance := and(rawSlot, max248)

            if gt(amount, sub(max248, prevBalance)) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(0x11)
                mstore(0x04, 0x11)
                revert(0x00, 0x24)
            }

            sstore(balance.slot, add(rawSlot, amount))
        }
    }

    /// @notice Safely decreases the packed balance by a specified amount using in-place subtraction.
    /// @dev Utilizes Yul assembly to bypass bitmasking and repacking overhead.
    /// Reverts with standard Solidity arithmetic Panic (0x11) if the amount exceeds the current balance.
    /// @param balance The storage pointer to the packed Balance struct.
    /// @param rawSlot The current unmasked 256-bit storage word (lower 248 bits: balance, upper 8 bits: tokensCount).
    /// @param amount The token amount to subtract from the current balance.
    function decrease(Balance storage balance, uint256 rawSlot, uint256 amount) internal {
        assembly ("memory-safe") {
            let max248 := shr(8, not(0))
            let prevBalance := and(rawSlot, max248)

            if gt(amount, prevBalance) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(0x11)
                mstore(0x04, 0x11)
                revert(0x00, 0x24)
            }

            sstore(balance.slot, sub(rawSlot, amount))
        }
    }
}
