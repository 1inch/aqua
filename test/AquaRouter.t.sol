// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { AquaRouter } from "src/AquaRouter.sol";

/// @dev Minimal constructor tests for AquaRouter: verifies owner is set correctly and zero address reverts.
contract AquaRouterTest is Test {
    function test_ConstructorSetsOwner() public {
        address owner = address(0xBEEF);
        AquaRouter router = new AquaRouter(owner);
        assertEq(router.owner(), owner);
    }

    function test_ConstructorRevertsWithZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AquaRouter(address(0));
    }
}
