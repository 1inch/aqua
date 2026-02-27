// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Test } from "forge-std/Test.sol";
import { dynamic } from "../utils/Dynamic.sol";
import { MockToken } from "../mock/ERC20.sol";
import { Aqua } from "../../src/Aqua.sol";
import { IAqua } from "../../src/interfaces/IAqua.sol";

abstract contract AquaTestBase is Test {
    Aqua public aqua;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;

    address public maker = address(0x1111);
    address public app = address(0x2222);
    address public pusher = address(0x3333);

    function setUp() public virtual {
        aqua = new Aqua();
        token1 = new MockToken("Token1");
        token2 = new MockToken("Token2");
        token3 = new MockToken("Token3");

        // Setup tokens and approvals
        token1.transfer(maker, 10000e18);
        token2.transfer(maker, 10000e18);
        token3.transfer(maker, 10000e18);
        token1.transfer(pusher, 10000e18);

        vm.prank(maker);
        token1.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        token2.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        token3.approve(address(aqua), type(uint256).max);

        vm.prank(pusher);
        token1.approve(address(aqua), type(uint256).max);
    }
}
