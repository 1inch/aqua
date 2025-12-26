// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import "forge-std/Test.sol";
import { dynamic } from "./utils/Dynamic.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/Aqua.sol";
import "src/interfaces/IAqua.sol";

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, "MOCK") {
        _mint(msg.sender, 1000000e18);
    }
}

contract AquaTest is Test {
    Aqua public aqua;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;

    address public maker = address(0x1111);
    address public app = address(0x2222);
    address public pusher = address(0x3333);

    function setUp() public {
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

    // ========== SHIP CONSISTENCY TESTS ==========

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

    // ========== DOCK CONSISTENCY TESTS ==========

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

    // ========== PUSH CONSISTENCY TESTS ==========

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

    // ========== BALANCES AND SAFEBALANCES TESTS ==========

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
