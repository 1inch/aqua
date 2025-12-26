// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.24;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { TransientLock, TransientLockLib } from "./TransientLock.sol";

/// @title ReentrancyGuard - Transient Storage-Based Protection
/// @notice Abstract contract providing reentrancy guards using transient storage for gas efficiency.
/// @dev Requires Solidity >=0.8.24 for transient storage support (tload/tstore operations).
///
/// Use private _lock defined in this contract:
/// ```solidity
/// function swap(...) external nonReentrant {
/// function doMagic(...) external onlyNonReentrantCall {
/// ```
///
/// Or use your own locks for more granular control:
/// ```solidity
/// TransientLock private _myLock;
/// function swap(...) external nonReentrantLock(_myLock) {
/// function doMagic(...) external onlyNonReentrantCallLock(_myLock) {
/// ```
///
abstract contract ReentrancyGuard {
    using TransientLockLib for TransientLock;

    error MissingNonReentrantModifier();

    TransientLock private _lock;

    modifier nonReentrant {
        _lock.lock();
        _;
        _lock.unlock();
    }

    modifier onlyNonReentrantCall {
        require(_inNonReentrantCall(), MissingNonReentrantModifier());
        _;
    }

    modifier nonReentrantLock(TransientLock storage lock) {
        lock.lock();
        _;
        lock.unlock();
    }

    modifier onlyNonReentrantCallLock(TransientLock storage lock) {
        require(lock.isLocked(), MissingNonReentrantModifier());
        _;
    }

    function _inNonReentrantCall() internal view returns (bool) {
        return _lock.isLocked();
    }
}
