// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Vm } from "forge-std/Vm.sol";

library StorageAccesses {
    function assertEq(
        Vm vm,
        uint256 expectedReads,
        uint256 expectedWrites,
        bytes32[] memory reads,
        bytes32[] memory writes,
        string memory description
    ) internal pure {
        // Account for implicit SLOAD during SSTORE (https://getfoundry.sh/reference/cheatcodes/accesses)
        uint256 netReads = reads.length - writes.length;
        vm.assertEq(netReads, expectedReads, string.concat(description, ": net SLOADs"));
        vm.assertEq(writes.length, expectedWrites, string.concat(description, ": SSTOREs"));
    }
}
