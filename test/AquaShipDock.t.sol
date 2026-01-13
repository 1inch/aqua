// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaShipDockTest is AquaTestBase {
    // ========== SHIP TESTS ==========

    function testShipRevertsWhenTokenCountEquals255() public {
        // Create arrays with 255 tokens (which equals _DOCKED constant)
        address[] memory tokens = new address[](255);
        uint256[] memory amounts = new uint256[](255);

        for (uint256 i = 0; i < 255; i++) {
            tokens[i] = address(uint160(i + 1000)); // unique addresses
            amounts[i] = 1e18;
        }

        // Should revert with MaxNumberOfTokensExceeded
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.MaxNumberOfTokensExceeded.selector, 255, 255));
        aqua.ship(app, "strategy_255", tokens, amounts);
    }

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

    function testShipWithLargeAmountsPreservesTokenCount() public {
        // Ship with large amounts to verify tokensCount is not overwritten by balance
        // The Balance struct packs amount (uint248) and tokensCount (uint8) in one slot
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_large",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(1000e18), uint256(2000e18)])
        );

        bytes32 strategyHash = keccak256("strategy_large");

        // Verify tokensCount is preserved correctly
        (uint256 balance1, uint8 tokensCount1) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        (uint256 balance2, uint8 tokensCount2) = aqua.rawBalances(maker, app, strategyHash, address(token2));

        assertEq(balance1, 1000e18);
        assertEq(balance2, 2000e18);
        assertEq(tokensCount1, 2, "tokensCount should be 2, not overwritten by amount");
        assertEq(tokensCount2, 2, "tokensCount should be 2, not overwritten by amount");

        // Push more tokens and verify tokensCount still preserved
        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 500e18);

        (balance1, tokensCount1) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(balance1, 1500e18);
        assertEq(tokensCount1, 2, "tokensCount should remain 2 after push");
    }

    function testFuzzShipAmountDoesNotOverwriteTokenCount(uint248 amount1, uint248 amount2) public {
        // Bound amounts to what maker has available (10000e18 each token)
        amount1 = uint248(bound(amount1, 0, 10000e18));
        amount2 = uint248(bound(amount2, 0, 10000e18));

        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_fuzz",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(amount1), uint256(amount2)])
        );

        bytes32 strategyHash = keccak256("strategy_fuzz");

        // Verify tokensCount is always 2 regardless of amounts
        (, uint8 tokensCount1) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        (, uint8 tokensCount2) = aqua.rawBalances(maker, app, strategyHash, address(token2));

        assertEq(tokensCount1, 2, "tokensCount must be 2 for any amount");
        assertEq(tokensCount2, 2, "tokensCount must be 2 for any amount");
    }

    function testShipWithZeroAmounts() public {
        // Ship with zero amounts - should succeed (no require check for zero)
        vm.prank(maker);
        aqua.ship(
            app,
            "strategy_zero",
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(0), uint256(0)])
        );

        bytes32 strategyHash = keccak256("strategy_zero");

        // Verify balances are zero but strategy is active
        (uint256 balance1, uint8 tokensCount1) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        (uint256 balance2, uint8 tokensCount2) = aqua.rawBalances(maker, app, strategyHash, address(token2));

        assertEq(balance1, 0);
        assertEq(balance2, 0);
        assertEq(tokensCount1, 2); // Strategy is active with 2 tokens
        assertEq(tokensCount2, 2);

        // Push should still work on this strategy
        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 50e18);

        (balance1,) = aqua.rawBalances(maker, app, strategyHash, address(token1));
        assertEq(balance1, 50e18);
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

    function testDockNonExistentStrategyReverts() public {
        // Try to dock a strategy that was never shipped
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.DockingShouldCloseAllTokens.selector, app, keccak256("nonexistent")));
        aqua.dock(
            app,
            keccak256("nonexistent"),
            dynamic([address(token1)])
        );
    }

    function testDockAlreadyDockedStrategyReverts() public {
        // Ship a strategy
        vm.prank(maker);
        aqua.ship(
            app,
            "dock_twice",
            dynamic([address(token1)]),
            dynamic([uint256(100e18)])
        );

        // Dock the strategy
        vm.prank(maker);
        aqua.dock(
            app,
            keccak256("dock_twice"),
            dynamic([address(token1)])
        );

        // Try to dock again - should fail because tokensCount is now _DOCKED (255)
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.DockingShouldCloseAllTokens.selector, app, keccak256("dock_twice")));
        aqua.dock(
            app,
            keccak256("dock_twice"),
            dynamic([address(token1)])
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
