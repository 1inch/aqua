// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.0;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { IAqua } from "./interfaces/IAqua.sol";
import { TransientLock, TransientLockLib } from "./libs/TransientLock.sol";

/// @title AquaApp - Base contract for Aqua applications.
/// @notice Using _safeCheckAquaPush() requires using one of the followings reentrancy protections on swap methods:
///         - modifier nonReentrantStrategy(keccak256(abi.encode(strategy)))
///         - modifier nonReentrantLock(_reentrancyLocks[strategyHash])
///         - code _reentrancyLocks[strategyHash].lock(); ... _reentrancyLocks[strategyHash].unlock();
abstract contract AquaApp {
    using TransientLockLib for TransientLock;

    error MissingTakerAquaPush(address token, uint256 newBalance, uint256 expectedBalance);
    error MissingNonReentrantModifier();

    IAqua public immutable AQUA;

    mapping(address maker => mapping(bytes32 strategyHash => TransientLock)) internal _reentrancyLocks;

    modifier nonReentrantStrategy(address maker, bytes32 strategyHash) {
        _reentrancyLocks[maker][strategyHash].lock();
        _;
        _reentrancyLocks[maker][strategyHash].unlock();
    }

    constructor(IAqua aqua) {
        AQUA = aqua;
    }

    /// @dev Use reentrancy protection when calling this function to prevent nested swaps
    function _safeCheckAquaPush(address maker, bytes32 strategyHash, address token, uint256 expectedBalance) internal view {
        // Check that the swap function is reentrancy protected to prevent nested swaps
        require(_reentrancyLocks[maker][strategyHash].isLocked(), MissingNonReentrantModifier());

        (uint256 newBalance,) = AQUA.rawBalances(maker, address(this), strategyHash, token);
        require(newBalance >= expectedBalance, MissingTakerAquaPush(token, newBalance, expectedBalance));
    }
}
