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
    /// @notice Loads balance data from storage using exactly 1 SLOAD
    /// @dev Assembly implementation ensures optimal gas usage
    /// @param balance The storage pointer to the Balance struct
    /// @return amount The token balance amount
    /// @return tokensCount The number of tokens in the strategy
    function load(Balance storage balance) internal view returns (uint248 amount, uint8 tokensCount) {
        assembly ("memory-safe") {
            let packed := sload(balance.slot)
            amount := and(packed, 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            tokensCount := shr(248, packed)
        }
    }

    /// @notice Stores balance data to storage using exactly 1 SSTORE
    /// @dev Assembly implementation ensures optimal gas usage
    /// @param balance The storage pointer to the Balance struct
    /// @param amount The token balance amount to store
    /// @param tokensCount The number of tokens in the strategy
    function store(Balance storage balance, uint248 amount, uint8 tokensCount) internal {
        assembly ("memory-safe") {
            let packed := or(amount, shl(248, tokensCount))
            sstore(balance.slot, packed)
        }
    }
}
