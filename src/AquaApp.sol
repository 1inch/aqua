// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { TransientLock, TransientLockLib } from "@1inch/solidity-utils/contracts/libraries/TransientLock.sol";

import { IAqua } from "./interfaces/IAqua.sol";

/// @title AquaApp - Base contract for Aqua applications
/// @notice Using _safeCheckAquaPush() requires using one of the followings reentrancy protections on swap methods:
///         - modifier nonReentrantStrategy(maker, strategyHash)
///         - code _reentrancyLocks[maker][strategyHash].lock(); ... _reentrancyLocks[maker][strategyHash].unlock();
abstract contract AquaApp {
    using TransientLockLib for TransientLock;

    /// @notice Thrown when strategy parameters don't match the expected app address
    /// @param maker The maker address
    /// @param strategyHash The hash of the strategy
    /// @param salt The salt used in the strategy
    /// @param app The expected app address from strategy
    /// @param actualThis The actual contract address
    error InvalidAquaStrategy(address maker, bytes32 strategyHash, bytes32 salt, address app, address actualThis);

    /// @notice Thrown when taker hasn't pushed enough tokens to the maker's balance
    /// @param token The token that was expected to be pushed
    /// @param newBalance The actual new balance after the swap
    /// @param expectedBalance The minimum expected balance
    error MissingTakerAquaPush(address token, uint256 newBalance, uint256 expectedBalance);

    /// @notice Thrown when _safeCheckAquaPush is called without reentrancy protection
    error MissingNonReentrantModifier();

    /// @notice The Aqua protocol contract instance
    IAqua public immutable AQUA;

    /// @dev Reentrancy locks per maker and strategy to prevent nested swaps
    mapping(address maker => mapping(bytes32 strategyHash => TransientLock)) internal _reentrancyLocks;

    /// @notice Prevents reentrancy for a specific maker's strategy
    /// @param maker The maker address
    /// @param strategyHash The hash of the strategy
    modifier nonReentrantStrategy(address maker, bytes32 strategyHash) {
        _reentrancyLocks[maker][strategyHash].lock();
        _;
        _reentrancyLocks[maker][strategyHash].unlock();
    }

    /// @notice Initializes the AquaApp with an Aqua protocol instance
    /// @param aqua The Aqua protocol contract address
    constructor(IAqua aqua) {
        AQUA = aqua;
    }

    /// @notice Verifies that the taker has pushed sufficient tokens to the maker's balance
    /// @dev Must be called within a reentrancy-protected context to prevent nested swaps
    /// @param maker The maker address whose balance to check
    /// @param strategyHash The hash of the strategy
    /// @param token The token address to verify
    /// @param expectedBalance The minimum expected balance after the push
    function _safeCheckAquaPush(address maker, bytes32 strategyHash, address token, uint256 expectedBalance) internal view {
        // Check that the swap function is reentrancy protected to prevent nested swaps
        require(_reentrancyLocks[maker][strategyHash].isLocked(), MissingNonReentrantModifier());

        (uint256 newBalance,) = AQUA.rawBalances(maker, address(this), strategyHash, token);
        require(newBalance >= expectedBalance, MissingTakerAquaPush(token, newBalance, expectedBalance));
    }
}
