// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.24; // tload/tstore are available since 0.8.24

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { TransientLib, tuint256 } from "./Transient.sol";

struct TransientLock {
    tuint256 _raw;
}

library TransientLockLib {
    using TransientLib for tuint256;

    error UnexpectedLock();
    error UnexpectedUnlock();

    uint256 constant private _UNLOCKED = 0;
    uint256 constant private _LOCKED = 1;
    
    function lock(TransientLock storage self) internal {
        require(self._raw.inc() == _LOCKED, UnexpectedLock());
    }

    function unlock(TransientLock storage self) internal {
        self._raw.dec(UnexpectedUnlock.selector);
    }

    function isLocked(TransientLock storage self) internal view returns (bool) {
        return self._raw.tload() == _LOCKED;
    }
}
