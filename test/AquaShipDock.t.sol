// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaShipDockTest is AquaTestBase {
    // ========== SHIP TESTS ==========

    function testShipCannotBeCalledTwiceForSameStrategy() public {
        // First ship
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy1",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Try to ship again with same strategy
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.StrategiesMustBeImmutable.selector, app, keccak256("strategy1")));
        aqua.ship(
            app,
            "strategy1",
            dynamic([address(token1)]),
            dynamic([uint256(50e18)])
        );
    }

    function testShipCannotHaveDuplicateTokens() public {
        // The contract prevents duplicate tokens in the same ship call
        // because it checks tokensCount == 0 for each token
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.StrategiesMustBeImmutable.selector, app, keccak256("strategy_dup")));
        aqua.ship(
            app,
            "strategy_dup",
            dynamic([address(token1), address(token1)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );
    }

    // ========== DOCK TESTS ==========

    function testDockRequiresAllTokensFromShip() public {
        // Ship with 2 tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy2",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Try to dock with only 1 token
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.DockingShouldCloseAllTokens.selector, app, keccak256("strategy2")));
        aqua.dock(
            app,
            keccak256("strategy2"),
            dynamic([address(token1)])
        );
    }

    function testDockRequiresExactTokensFromShip() public {
        // Ship with specific tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy3",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Try to dock with different token
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.DockingShouldCloseAllTokens.selector, app, keccak256("strategy3")));
        aqua.dock(
            app,
            keccak256("strategy3"),
            dynamic([address(token1), address(token3)])
        );
    }

    function testDockRequiresCorrectTokenCount() public {
        // Ship with 2 tokens
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy4",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Try to dock with 3 tokens
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.DockingShouldCloseAllTokens.selector, app, keccak256("strategy4")));
        aqua.dock(
            app,
            keccak256("strategy4"),
            dynamic([address(token1), address(token2), address(token3)])
        );
    }

    // ========== SHIP + DOCK COMBINED TESTS ==========

    function testShipDockShipSameStrategyReverts() public {
        bytes32 strategyHash = keccak256("reship");

        // 1. Ship with specific tokens and amounts
        vm.prank(maker);
        aqua.ship(
            app,
            "reship",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );

        // Verify initial balances
        (uint256 balance1,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        (uint256 balance2,) = aqua.rawBalances(maker, app, strategyHash, address(token2));
        assertEq(balance1, 100e18);
        assertEq(balance2, 200e18);

        // 2. Dock the strategy
        vm.prank(maker);
        aqua.dock(
            app,
            strategyHash,
            dynamic([address(token1), address(token2)])
        );

        // Verify balances are zero after dock
        (balance1,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        (balance2,) = aqua.rawBalances(maker, app, strategyHash, address(token2));
        assertEq(balance1, 0);
        assertEq(balance2, 0);

        // 3. Attempt to ship again with the same strategy - should revert
        // Strategies are immutable: once docked, cannot be re-shipped with the same salt
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.StrategiesMustBeImmutable.selector, app, strategyHash));
        aqua.ship(
            app,
            "reship",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );
    }
}
