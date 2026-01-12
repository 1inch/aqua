// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Test } from "forge-std/Test.sol";
import { dynamic } from "./utils/Dynamic.sol";
import { StorageAccesses } from "./utils/StorageAccesses.sol";
import { MockToken } from "./mock/ERC20.sol";
import { Aqua } from "src/Aqua.sol";

contract AquaStorageTest is Test {
    Aqua public aqua;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;

    address public maker = address(0x1111);
    address public pusher = address(0x2222);

    function setUp() public {
        aqua = new Aqua();
        token1 = new MockToken("Token1");
        token2 = new MockToken("Token2");
        token3 = new MockToken("Token3");

        // Distribute tokens
        token1.transfer(maker, 10000e18);
        token1.transfer(pusher, 10000e18);
        token2.transfer(maker, 10000e18);
        token3.transfer(maker, 10000e18);

        // Approve Aqua
        vm.prank(maker);
        token1.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        token2.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        token3.approve(address(aqua), type(uint256).max);

        vm.prank(pusher);
        token1.approve(address(aqua), type(uint256).max);
    }

    // ========== PUSH/PULL STORAGE TESTS ==========

    function testPushSingleSloadSstore() public {
        // Initialize strategy with ship
        vm.prank(maker);
        aqua.ship(
            address(this),
            "strategy",
            dynamic([address(token1)]),
            dynamic([uint256(1000e18)])
        );

        // Test push storage operations
        vm.record();
        vm.prank(pusher);
        aqua.push(maker, address(this), keccak256("strategy"), address(token1), 100e18);

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 1, 1, reads, writes, "Push");
    }

    function testPullSingleSloadSstore() public {
        // Initialize strategy with ship
        vm.prank(maker);
        aqua.ship(
            address(this),
            "strategy",
            dynamic([address(token1)]),
            dynamic([uint256(1000e18)])
        );

        // Test pull storage operations (called directly from test contract acting as app)
        vm.record();
        aqua.pull(maker, keccak256("strategy"), address(token1), 100e18, address(this));

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 1, 1, reads, writes, "Pull");
    }

    // ========== SHIP STORAGE TESTS ==========

    function testShip1Token() public {
        vm.record();
        vm.prank(maker);
        aqua.ship(
            address(this),
            "ship1",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 1, 1, reads, writes, "Ship 1 token");
    }

    function testShip2Tokens() public {
        vm.record();
        vm.prank(maker);
        aqua.ship(
            address(this),
            "ship2",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 2, 2, reads, writes, "Ship 2 tokens");
    }

    function testShip3Tokens() public {
        vm.record();
        vm.prank(maker);
        aqua.ship(
            address(this),
            "ship3",
            dynamic([address(token1), address(token2), address(token3)]),
            dynamic([uint256(100e18), uint256(200e18), uint256(300e18)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 3, 3, reads, writes, "Ship 3 tokens");
    }

    // ========== DOCK STORAGE TESTS ==========

    function testDock1Token() public {
        // First ship
        vm.prank(maker);
        aqua.ship(
            address(this),
            "dock1",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Test dock storage operations
        vm.prank(maker);
        vm.record();
        aqua.dock(
            address(this),
            keccak256("dock1"),
            dynamic([address(token1)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 1, 1, reads, writes, "Dock 1 token");
    }

    function testDock2Tokens() public {
        // First ship
        vm.prank(maker);
        aqua.ship(
            address(this),
            "dock2",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Test dock storage operations
        vm.record();
        vm.prank(maker);
        aqua.dock(
            address(this),
            keccak256("dock2"),
            dynamic([address(token1), address(token2)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 2, 2, reads, writes, "Dock 2 tokens");
    }

    function testDock3Tokens() public {
        // First ship
        vm.prank(maker);
        aqua.ship(
            address(this),
            "dock3",
            dynamic([address(token1), address(token2), address(token3)]),
            dynamic([uint256(100e18), uint256(200e18), uint256(300e18)])
        );

        // Test dock storage operations
        vm.record();
        vm.prank(maker);
        aqua.dock(
            address(this),
            keccak256("dock3"),
            dynamic([address(token1), address(token2), address(token3)])
        );

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(aqua));
        StorageAccesses.assertEq(vm, 3, 3, reads, writes, "Dock 3 tokens");
    }
}
