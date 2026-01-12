// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

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
}
