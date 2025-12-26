// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

/// @title Balance Struct
/// @notice Represents a maker's balance allocation for a specific token in a strategy
/// @dev Packed into a single storage slot: 248 bits for amount (sufficient for token balances) and 8 bits for tokensCount
struct Balance {
    /// @notice The token balance amount
    uint248 amount;
    /// @notice The number of tokens in the strategy (0xff indicates docked/inactive)
    uint8 tokensCount;
}

/// @title Balance Library
/// @notice Library for efficient storage operations on Balance structs
/// @dev Uses inline assembly to ensure single SLOAD/SSTORE operations for gas efficiency
library BalanceLib {
    /// @notice Loads a Balance from storage
    /// @dev Uses assembly to ensure exactly 1 SLOAD is performed
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

    /// @notice Stores a Balance to storage
    /// @dev Uses assembly to ensure exactly 1 SSTORE is performed
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
