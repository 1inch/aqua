// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaBalancesTest is AquaTestBase {
    // ========== RAW BALANCES TESTS ==========

    function testBalancesReturnsZeroForNonExistentStrategy() public view {
        // Query balance for non-existent strategy
        (uint256 balance,) = aqua.rawBalances(maker, app, keccak256("nonexistent"), address(token1));
        assertEq(balance, 0);
    }

    function testBalancesReturnsZeroForTokenNotInStrategy() public {
        // Ship with token1 only
        vm.prank(maker);
        aqua.ship(
            app,
            "balances_test",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Query balance for token2 (not in strategy) - should return 0
        (uint256 balance,) = aqua.rawBalances(maker, app, keccak256("balances_test"), address(token2));
        assertEq(balance, 0);
    }

    function testBalancesReturnsCorrectAmounts() public {
        // Ship with multiple tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "balances_multi",
            dynamic([address(token1), address(token2), address(token3)]),
            dynamic([uint256(100e18), uint256(200e18), uint256(300e18)])
        );

        bytes32 strategyHash = keccak256("balances_multi");

        // Check all balances
        (uint256 newBalance1,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(newBalance1, 100e18);
        (uint256 newBalance2,) = aqua.rawBalances(maker, app, strategyHash, address(token2));
        assertEq(newBalance2, 200e18);
        (uint256 newBalance3,) = aqua.rawBalances(maker, app, strategyHash, address(token3));
        assertEq(newBalance3, 300e18);
    }

    // ========== SAFE BALANCES TESTS ==========

    function testSafeBalancesReturnsCorrectAmountsForActiveStrategy() public {
        // Ship with multiple tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "safe_balances",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(150e18), uint256(250e18)])
        );

        bytes32 strategyHash = keccak256("safe_balances");

        // Query safeBalances
        (uint256 balance0, uint256 balance1) = aqua.safeBalances(
            maker,
            app,
            strategyHash,
            address(token1),
            address(token2)
        );

        assertEq(balance0, 150e18);
        assertEq(balance1, 250e18);
    }

    function testSafeBalancesRevertsForNonExistentStrategy() public {
        // Try to query safeBalances for non-existent strategy
        vm.expectRevert(
            abi.encodeWithSelector(
                IAqua.SafeBalancesForTokenNotInActiveStrategy.selector,
                maker,
                app,
                keccak256("nonexistent"),
                address(token1)
            )
        );
        aqua.safeBalances(
            maker,
            app,
            keccak256("nonexistent"),
            address(token1),
            address(token2)
        );
    }

    function testSafeBalancesRevertsIfAnyTokenNotInStrategy() public {
        // Ship with token1 and token2
        vm.prank(maker);
        aqua.ship(
            app,
            "safe_partial",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        bytes32 strategyHash = keccak256("safe_partial");

        // Try to query with token3 (not in strategy)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAqua.SafeBalancesForTokenNotInActiveStrategy.selector,
                maker,
                app,
                strategyHash,
                address(token3)
            )
        );
        aqua.safeBalances(
            maker,
            app,
            strategyHash,
            address(token1),
            address(token3)
        );
    }

    function testSafeBalancesRevertsAfterDock() public {
        // Ship and then dock
        vm.prank(maker);
        aqua.ship(
            app,
            "safe_docked",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        bytes32 strategyHash = keccak256("safe_docked");

        // Dock the strategy
        vm.prank(maker);
        aqua.dock(
            app,
            strategyHash,
            dynamic([address(token1)])
        );

        // Try to query safeBalances after dock
        vm.expectRevert(
            abi.encodeWithSelector(
                IAqua.SafeBalancesForTokenNotInActiveStrategy.selector,
                maker,
                app,
                strategyHash,
                address(token1)
            )
        );
        aqua.safeBalances(
            maker,
            app,
            strategyHash,
            address(token1),
            address(token2)
        );
    }

    function testSafeBalancesTracksChangesFromPushPull() public {
        // Ship strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "safe_changes",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        bytes32 strategyHash = keccak256("safe_changes");

        // Push some tokens
        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 50e18);

        // Pull some tokens
        vm.prank(app);
        aqua.pull(maker, strategyHash, address(token2), 50e18, app);

        // Verify safeBalances reflects the changes
        (uint256 balance0, uint256 balance1) = aqua.safeBalances(
            maker,
            app,
            strategyHash,
            address(token1),
            address(token2)
        );

        assertEq(balance0, 150e18); // 100 + 50 pushed
        assertEq(balance1, 150e18); // 200 - 50 pulled
    }
}
