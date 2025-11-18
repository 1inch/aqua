// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

contract Multicall {
    error MsgValueNotAllowedForMulticall();

    function multicall(bytes[] calldata data) external {
        if (msg.value != 0 && data.length > 1) {
            revert MsgValueNotAllowedForMulticall();
        }

        uint256 length = data.length;
        for (uint256 i = 0; i < length;) {
            (bool success,) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }

            unchecked { ++i; }
        }
    }
}
