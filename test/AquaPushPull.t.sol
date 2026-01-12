// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaPushPullTest is AquaTestBase {
    // ========== PUSH TESTS ==========

    function testPushSucceedsForActiveStrategy() public {
        // Ship a strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "push_success",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Push should succeed
        vm.prank(pusher);
        aqua.push(maker, app, keccak256("push_success"), address(token1), 50e18);

        // Verify balance increased
        (uint256 balance,) = aqua.rawBalances(maker, app, keccak256("push_success"), address(token1));
        assertEq(balance, 150e18);
    }

    function testPushRequiresActiveStrategy() public {
        // Try to push without ship
        vm.prank(pusher);
        vm.expectRevert(abi.encodeWithSelector(IAqua.PushToNonActiveStrategyPrevented.selector, maker, app, keccak256("nonexistent"), address(token1)));
        aqua.push(maker, app, keccak256("nonexistent"), address(token1), 100e18);
    }

    function testPushFailsAfterDock() public {
        // Ship and then dock
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy5",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        vm.prank(maker);
        aqua.dock(
            app,
            keccak256("strategy5"),
            dynamic([address(token1)])
        );

        // Try to push after dock
        vm.prank(pusher);
        vm.expectRevert(abi.encodeWithSelector(IAqua.PushToNonActiveStrategyPrevented.selector, maker, app, keccak256("strategy5"), address(token1)));
        aqua.push(maker, app, keccak256("strategy5"), address(token1), 50e18);
    }

    function testPushOnlyForShippedTokens() public {
        // Ship with token1 only
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy6",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Try to push token2 (not shipped)
        vm.prank(pusher);
        vm.expectRevert(abi.encodeWithSelector(IAqua.PushToNonActiveStrategyPrevented.selector, maker, app, keccak256("strategy6"), address(token2)));
        aqua.push(maker, app, keccak256("strategy6"), address(token2), 50e18);
    }

    // ========== PULL TESTS ==========

    function testPullSucceedsForActiveStrategy() public {
        // Ship a strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "pull_success",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Pull should succeed (called by app)
        vm.prank(app);
        aqua.pull(maker, keccak256("pull_success"), address(token1), 30e18, app);

        // Verify balance decreased
        (uint256 balance,) = aqua.rawBalances(maker, app, keccak256("pull_success"), address(token1));
        assertEq(balance, 70e18);
    }

    function testPullRevertsOnInsufficientBalance() public {
        // Ship a strategy with 100 tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "pull_underflow",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Try to pull more than available - should revert (arithmetic underflow)
        vm.prank(app);
        vm.expectRevert(); // SafeCast or arithmetic underflow
        aqua.pull(maker, keccak256("pull_underflow"), address(token1), 150e18, app);
    }

    function testPullFromNonExistentStrategy() public {
        // Pull from non-existent strategy - balance is 0, so any pull amount will underflow
        vm.prank(app);
        vm.expectRevert(); // Arithmetic underflow
        aqua.pull(maker, keccak256("nonexistent_pull"), address(token1), 1e18, app);
    }

    function testPullAfterDockRevertsOnUnderflow() public {
        // Ship and dock a strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "pull_docked",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        vm.prank(maker);
        aqua.dock(
            app,
            keccak256("pull_docked"),
            dynamic([address(token1)])
        );

        // Try to pull after dock - balance is 0, so will underflow
        vm.prank(app);
        vm.expectRevert(); // Arithmetic underflow
        aqua.pull(maker, keccak256("pull_docked"), address(token1), 50e18, app);
    }
}
