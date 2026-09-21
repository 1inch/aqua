// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";
import { stdError } from "forge-std/StdError.sol";

contract AquaPushPullTest is AquaTestBase {
    // ========== PUSH TESTS ==========

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
        vm.expectRevert(stdError.arithmeticError);
        aqua.pull(maker, keccak256("pull_underflow"), address(token1), 150e18, app);
    }

    function testPullFromNonExistentStrategy() public {
        // Pull from non-existent strategy - balance is 0, so any pull amount will underflow
        vm.prank(app);
        vm.expectRevert(stdError.arithmeticError);
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
        vm.expectRevert(stdError.arithmeticError);
        aqua.pull(maker, keccak256("pull_docked"), address(token1), 50e18, app);
    }

    // ========== OVERFLOW TESTS ==========

    function testPushAccumulatesBalance() public {
        // Test that push correctly accumulates balance without overflow
        // Ship with max available tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_overflow",
            dynamic([address(token1)]),
            dynamic([uint256(9000e18)]) // maker has 10000e18
        );

        bytes32 strategyHash = keccak256("strategy_overflow");

        // Pusher has 10000e18 tokens, push would make balance 19000e18 - this works
        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 1000e18);

        (uint256 balance,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(balance, 10000e18);
    }

    function testPushRevertsOnUint248Overflow() public {
        // This test verifies that pushing an amount that would overflow uint248 reverts
        // The contract uses SafeCast which will revert on overflow

        // Ship a strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_uint248_overflow",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        bytes32 strategyHash = keccak256("strategy_uint248_overflow");

        // Try to push an amount larger than uint248 max
        // This will fail at SafeCast.toUint248() in push function
        uint256 tooLargeAmount = uint256(type(uint248).max) + 1;

        vm.prank(pusher);
        vm.expectRevert(); // SafeCast overflow
        aqua.push(maker, app, strategyHash, address(token1), tooLargeAmount);
    }

    function testPushRevertsOnBalanceOverflow() public {
        // This test verifies that pushing causes overflow when prevBalance + amount > uint248 max
        // Ship with a large initial balance close to uint248 max
        uint256 largeInitialBalance = uint256(type(uint248).max) - 100e18;

        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_balance_overflow",
            dynamic([address(token1)]),
            dynamic([largeInitialBalance])
        );

        bytes32 strategyHash = keccak256("strategy_balance_overflow");

        // Verify initial balance
        (uint256 balance,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(balance, largeInitialBalance);

        // Try to push an amount that would cause prevBalance + amount to overflow uint248
        // 200e18 > 100e18 remaining space, so this should overflow
        vm.prank(pusher);
        vm.expectRevert(stdError.arithmeticError);
        aqua.push(maker, app, strategyHash, address(token1), 200e18);
    }

    function testShipRevertsOnUint248AmountOverflow() public {
        // Test that shipping with amount > uint248 max reverts
        uint256 tooLargeAmount = uint256(type(uint248).max) + 1;

        vm.prank(maker);
        vm.expectRevert(); // SafeCast overflow
        aqua.ship(
            app,
            "strategy_ship_overflow",
            dynamic([address(token1)]),
            dynamic([tooLargeAmount])
        );
    }
}
