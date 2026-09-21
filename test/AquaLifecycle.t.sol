// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaLifecycleTest is AquaTestBase {
    // ========== COMPLEX LIFECYCLE TESTS ==========

    function testFullLifecycle() public {
        bytes32 strategyHash = keccak256("lifecycle");
        uint256 newBalance;

        // 1. Ship with 2 tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "lifecycle",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // 2. Push to token1
        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 50e18);
        (newBalance,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(newBalance, 150e18);

        // 3. Pull from app
        vm.prank(app);
        aqua.pull(maker, strategyHash, address(token1), 30e18, app);
        (newBalance,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(newBalance, 120e18);

        // 4. Dock all tokens
        vm.prank(maker);
        aqua.dock(
            app,
            strategyHash,
            dynamic([address(token1), address(token2)])
        );

        // 5. Verify can't push after dock
        vm.prank(pusher);
        vm.expectRevert(abi.encodeWithSelector(IAqua.PushToNonActiveStrategyPrevented.selector, maker, app, strategyHash, address(token1)));
        aqua.push(maker, app, strategyHash, address(token1), 10e18);

        // 6. Verify balances are zero after dock
        (newBalance,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(newBalance, 0);
        (newBalance,) = aqua.rawBalances(maker, app, strategyHash, address(token2));
        assertEq(newBalance, 0);
    }

    function testMultipleStrategiesSameTokens() public {
        uint256 newBalance;

        // Ship strategy 1
        vm.prank(maker);
        aqua.ship(
            app,
            "multi1",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Ship strategy 2 with same tokens but different salt
        vm.prank(maker);
        aqua.ship(
            app,
            "multi2",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(300e18), uint256(400e18)])
        );

        // Verify both strategies work independently
        bytes32 hash1 = keccak256("multi1");
        bytes32 hash2 = keccak256("multi2");

        (newBalance,) = aqua.rawBalances(maker, app, hash1, address(token1));
        assertEq(newBalance, 100e18);
        (newBalance,) = aqua.rawBalances(maker, app, hash2, address(token1));
        assertEq(newBalance, 300e18);

        // Push to strategy 1 doesn't affect strategy 2
        vm.prank(pusher);
        aqua.push(maker, app, hash1, address(token1), 50e18);

        (newBalance,) = aqua.rawBalances(maker, app, hash1, address(token1));
        assertEq(newBalance, 150e18);
        (newBalance,) = aqua.rawBalances(maker, app, hash2, address(token1));
        assertEq(newBalance, 300e18);

        // Can dock strategies independently
        vm.prank(maker);
        aqua.dock(app, hash1, dynamic([address(token1), address(token2)]));

        // Strategy 1 is docked, strategy 2 still active
        (newBalance,) = aqua.rawBalances(maker, app, hash1, address(token1));
        assertEq(newBalance, 0);
        (newBalance,) = aqua.rawBalances(maker, app, hash2, address(token1));
        assertEq(newBalance, 300e18);
    }
}
