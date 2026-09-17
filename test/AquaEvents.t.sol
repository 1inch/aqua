// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { dynamic } from "./utils/Dynamic.sol";
import { AquaTestBase } from "./base/AquaTestBase.sol";
import { IAqua } from "src/interfaces/IAqua.sol";

contract AquaEventsTest is AquaTestBase {
    // ========== SHIP EVENTS ==========

    function testShipEmitsShippedEvent() public {
        bytes memory strategy = "strategy_shipped";
        bytes32 strategyHash = keccak256(strategy);

        vm.expectEmit(true, true, true, true);
        emit IAqua.Shipped(maker, app, strategyHash, strategy);

        vm.prank(maker);
        aqua.ship(app, strategy, dynamic([address(token1)]), dynamic([uint256(100e18)]));
    }

    function testShipEmitsPushedEventForEachToken() public {
        bytes memory strategy = "strategy_push_events";
        bytes32 strategyHash = keccak256(strategy);

        // Expect Shipped event first
        vm.expectEmit(true, true, true, true);
        emit IAqua.Shipped(maker, app, strategyHash, strategy);

        // Expect Pushed event for token1
        vm.expectEmit(true, true, true, true);
        emit IAqua.Pushed(maker, app, strategyHash, address(token1), 100e18);

        // Expect Pushed event for token2
        vm.expectEmit(true, true, true, true);
        emit IAqua.Pushed(maker, app, strategyHash, address(token2), 200e18);

        vm.prank(maker);
        aqua.ship(
            app,
            strategy,
            dynamic([address(token1), address(token2)]),
            dynamic([uint256(100e18), uint256(200e18)])
        );
    }

    // ========== DOCK EVENTS ==========

    function testDockEmitsDockedEvent() public {
        bytes memory strategy = "strategy_docked";
        bytes32 strategyHash = keccak256(strategy);

        // First ship the strategy
        vm.prank(maker);
        aqua.ship(app, strategy, dynamic([address(token1)]), dynamic([uint256(100e18)]));

        // Expect Docked event
        vm.expectEmit(true, true, true, true);
        emit IAqua.Docked(maker, app, strategyHash);

        vm.prank(maker);
        aqua.dock(app, strategyHash, dynamic([address(token1)]));
    }

    // ========== PUSH EVENTS ==========

    function testPushEmitsPushedEvent() public {
        bytes memory strategy = "strategy_push";
        bytes32 strategyHash = keccak256(strategy);

        // First ship the strategy
        vm.prank(maker);
        aqua.ship(app, strategy, dynamic([address(token1)]), dynamic([uint256(100e18)]));

        // Expect Pushed event
        vm.expectEmit(true, true, true, true);
        emit IAqua.Pushed(maker, app, strategyHash, address(token1), 50e18);

        vm.prank(pusher);
        aqua.push(maker, app, strategyHash, address(token1), 50e18);
    }

    // ========== PULL EVENTS ==========

    function testPullEmitsPulledEvent() public {
        bytes memory strategy = "strategy_pull";
        bytes32 strategyHash = keccak256(strategy);

        // First ship the strategy
        vm.prank(maker);
        aqua.ship(app, strategy, dynamic([address(token1)]), dynamic([uint256(100e18)]));

        // Expect Pulled event
        vm.expectEmit(true, true, true, true);
        emit IAqua.Pulled(maker, app, strategyHash, address(token1), 30e18);

        vm.prank(app);
        aqua.pull(maker, strategyHash, address(token1), 30e18, app);
    }
}
