// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Aqua} from "src/Aqua.sol";
import {IAqua} from "src/interfaces/IAqua.sol";
import {IShipHook} from "src/interfaces/IShipHook.sol";

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, "MOCK") {
        _mint(msg.sender, 1000000e18);
    }
}

/// @title MockWETH - Minimal WETH for testing
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/// @title MockHookApp - App that implements IShipHook for testing
contract MockHookApp is IShipHook {
    MockWETH public weth;
    
    // Tracking for tests
    bool public beforeShipCalled;
    bool public afterShipCalled;
    address public lastMaker;
    bytes32 public lastStrategyHash;
    uint256 public lastEthReceived;
    
    // Control flags for testing
    bool public shouldRevertBeforeShip;
    bool public shouldRevertAfterShip;
    bool public shouldReturnFalse;

    constructor(address _weth) {
        weth = MockWETH(payable(_weth));
    }

    function beforeShip(
        address maker,
        bytes32 strategyHash,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable override returns (bool success) {
        if (shouldRevertBeforeShip) revert("beforeShip reverted");
        if (shouldReturnFalse) return false;
        
        beforeShipCalled = true;
        lastMaker = maker;
        lastStrategyHash = strategyHash;
        lastEthReceived = msg.value;
        
        // If ETH received, wrap to WETH and send to maker
        if (msg.value > 0) {
            // Find WETH in tokens and verify amount matches
            for (uint256 i = 0; i < tokens.length; i++) {
                if (tokens[i] == address(weth) && amounts[i] == msg.value) {
                    weth.deposit{value: msg.value}();
                    weth.transfer(maker, msg.value);
                    break;
                }
            }
        }
        
        return true;
    }

    function afterShip(
        address maker,
        bytes32 strategyHash,
        address[] calldata,
        uint256[] calldata
    ) external override {
        if (shouldRevertAfterShip) revert("afterShip reverted");
        
        afterShipCalled = true;
        lastMaker = maker;
        lastStrategyHash = strategyHash;
    }

    function reset() external {
        beforeShipCalled = false;
        afterShipCalled = false;
        lastMaker = address(0);
        lastStrategyHash = bytes32(0);
        lastEthReceived = 0;
        shouldRevertBeforeShip = false;
        shouldRevertAfterShip = false;
        shouldReturnFalse = false;
    }

    function setRevertBeforeShip(bool _revert) external {
        shouldRevertBeforeShip = _revert;
    }

    function setRevertAfterShip(bool _revert) external {
        shouldRevertAfterShip = _revert;
    }

    function setReturnFalse(bool _returnFalse) external {
        shouldReturnFalse = _returnFalse;
    }

    receive() external payable {}
}

/// @title MockNonHookApp - App that does NOT implement IShipHook
contract MockNonHookApp {
    // This app doesn't implement IShipHook
}

contract AquaHooksTest is Test {
    Aqua public aqua;
    MockToken public token1;
    MockWETH public weth;
    MockHookApp public hookApp;
    MockNonHookApp public nonHookApp;

    address public maker = address(0x1111);

    function setUp() public {
        aqua = new Aqua();
        token1 = new MockToken("Token1");
        weth = new MockWETH();
        hookApp = new MockHookApp(address(weth));
        nonHookApp = new MockNonHookApp();

        // Setup tokens and approvals
        token1.transfer(maker, 10000e18);
        vm.deal(maker, 100 ether);

        vm.prank(maker);
        token1.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        weth.approve(address(aqua), type(uint256).max);
    }

    // ========== HOOK FLAGS TESTS ==========

    function testShipWithNoHooks() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            "strategy_no_hooks",
            tokens,
            amounts,
            0 // HOOK_NONE
        );

        // Hooks should NOT be called
        assertFalse(hookApp.beforeShipCalled());
        assertFalse(hookApp.afterShipCalled());
    }

    function testShipWithBeforeHookOnly() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            "strategy_before_only",
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );

        // Only beforeShip should be called
        assertTrue(hookApp.beforeShipCalled());
        assertFalse(hookApp.afterShipCalled());
        assertEq(hookApp.lastMaker(), maker);
    }

    function testShipWithAfterHookOnly() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            "strategy_after_only",
            tokens,
            amounts,
            2 // HOOK_AFTER
        );

        // Only afterShip should be called
        assertFalse(hookApp.beforeShipCalled());
        assertTrue(hookApp.afterShipCalled());
        assertEq(hookApp.lastMaker(), maker);
    }

    function testShipWithBothHooks() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            "strategy_both_hooks",
            tokens,
            amounts,
            3 // HOOK_BOTH
        );

        // Both hooks should be called
        assertTrue(hookApp.beforeShipCalled());
        assertTrue(hookApp.afterShipCalled());
        assertEq(hookApp.lastMaker(), maker);
    }

    // ========== ETH WRAPPING TESTS ==========

    function testBeforeShipWrapsETH() public {
        uint256 ethAmount = 10 ether;

        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethAmount;

        vm.prank(maker);
        aqua.ship{value: ethAmount}(
            address(hookApp),
            "strategy_eth_wrap",
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );

        // Maker should have WETH
        assertEq(weth.balanceOf(maker), ethAmount);
        assertEq(hookApp.lastEthReceived(), ethAmount);
    }

    function testETHSentRequiresBeforeHook() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // Try to send ETH without HOOK_BEFORE flag
        vm.prank(maker);
        vm.expectRevert(IAqua.ETHSentWithoutBeforeHook.selector);
        aqua.ship{value: 1 ether}(
            address(hookApp),
            "strategy_eth_no_hook",
            tokens,
            amounts,
            0 // HOOK_NONE - should fail!
        );
    }

    function testETHSentWithAfterHookOnlyFails() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        // Try to send ETH with only HOOK_AFTER flag
        vm.prank(maker);
        vm.expectRevert(IAqua.ETHSentWithoutBeforeHook.selector);
        aqua.ship{value: 1 ether}(
            address(hookApp),
            "strategy_eth_after_only",
            tokens,
            amounts,
            2 // HOOK_AFTER only - should fail!
        );
    }

    function testETHWithBothHooksSucceeds() public {
        uint256 ethAmount = 5 ether;

        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethAmount;

        vm.prank(maker);
        aqua.ship{value: ethAmount}(
            address(hookApp),
            "strategy_eth_both",
            tokens,
            amounts,
            3 // HOOK_BOTH
        );

        assertTrue(hookApp.beforeShipCalled());
        assertTrue(hookApp.afterShipCalled());
        assertEq(weth.balanceOf(maker), ethAmount);
    }

    // ========== HOOK FAILURE TESTS ==========

    function testBeforeShipReturnsFalseReverts() public {
        hookApp.setReturnFalse(true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IAqua.ShipHookFailed.selector, address(hookApp), 1));
        aqua.ship(
            address(hookApp),
            "strategy_false",
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );
    }

    function testBeforeShipRevertsPropagatesToAqua() public {
        hookApp.setRevertBeforeShip(true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        vm.expectRevert("beforeShip reverted");
        aqua.ship(
            address(hookApp),
            "strategy_revert_before",
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );
    }

    function testAfterShipRevertsPropagatesToAqua() public {
        hookApp.setRevertAfterShip(true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        vm.expectRevert("afterShip reverted");
        aqua.ship(
            address(hookApp),
            "strategy_revert_after",
            tokens,
            amounts,
            2 // HOOK_AFTER
        );
    }

    // ========== NON-HOOK APP TESTS ==========

    function testNonHookAppWithNoHooksSucceeds() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // Non-hook app with no hooks flag should work
        vm.prank(maker);
        aqua.ship(
            address(nonHookApp),
            "strategy_non_hook",
            tokens,
            amounts,
            0 // HOOK_NONE
        );

        // Verify strategy was created
        (uint248 balance,) = aqua.rawBalances(maker, address(nonHookApp), keccak256("strategy_non_hook"), address(token1));
        assertEq(balance, 100e18);
    }

    function testNonHookAppWithHooksFails() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // Non-hook app with hooks flag should fail (app doesn't implement IShipHook)
        vm.prank(maker);
        vm.expectRevert();
        aqua.ship(
            address(nonHookApp),
            "strategy_non_hook_fail",
            tokens,
            amounts,
            1 // HOOK_BEFORE - but app doesn't implement it!
        );
    }

    // ========== STRATEGY HASH VERIFICATION ==========

    function testHooksReceiveCorrectStrategyHash() public {
        bytes memory strategy = "unique_strategy_123";
        bytes32 expectedHash = keccak256(strategy);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            strategy,
            tokens,
            amounts,
            3 // HOOK_BOTH
        );

        assertEq(hookApp.lastStrategyHash(), expectedHash);
    }

    // ========== MULTIPLE TOKENS WITH ETH ==========

    function testETHWithMultipleTokens() public {
        uint256 ethAmount = 2 ether;

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(weth);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = ethAmount;

        vm.prank(maker);
        aqua.ship{value: ethAmount}(
            address(hookApp),
            "strategy_multi_eth",
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );

        // Verify both tokens are tracked
        bytes32 strategyHash = keccak256("strategy_multi_eth");
        (uint248 balance1,) = aqua.rawBalances(maker, address(hookApp), strategyHash, address(token1));
        (uint248 balance2,) = aqua.rawBalances(maker, address(hookApp), strategyHash, address(weth));
        
        assertEq(balance1, 100e18);
        assertEq(balance2, ethAmount);
        assertEq(weth.balanceOf(maker), ethAmount);
    }

    // ========== HOOK CONSTANTS TESTS ==========

    function testHookConstants() public view {
        assertEq(aqua.HOOK_NONE(), 0x00);
        assertEq(aqua.HOOK_BEFORE(), 0x01);
        assertEq(aqua.HOOK_AFTER(), 0x02);
        assertEq(aqua.HOOK_BOTH(), 0x03);
    }

    // ========== FUZZ TESTS ==========

    function testFuzz_ShipWithHooksFlags(uint8 hooks) public {
        // Bound to valid flags (0-3)
        hooks = uint8(bound(hooks, 0, 3));

        hookApp.reset();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(maker);
        aqua.ship(
            address(hookApp),
            abi.encodePacked("fuzz_strategy_", hooks),
            tokens,
            amounts,
            hooks
        );

        // Verify correct hooks were called
        bool expectBefore = (hooks & 1) != 0;
        bool expectAfter = (hooks & 2) != 0;
        
        assertEq(hookApp.beforeShipCalled(), expectBefore);
        assertEq(hookApp.afterShipCalled(), expectAfter);
    }

    function testFuzz_ETHAmount(uint256 ethAmount) public {
        // Bound to reasonable range
        ethAmount = bound(ethAmount, 1, 1000 ether);
        vm.deal(maker, ethAmount);

        hookApp.reset();

        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethAmount;

        vm.prank(maker);
        aqua.ship{value: ethAmount}(
            address(hookApp),
            abi.encodePacked("fuzz_eth_", ethAmount),
            tokens,
            amounts,
            1 // HOOK_BEFORE
        );

        assertEq(weth.balanceOf(maker), ethAmount);
        assertEq(hookApp.lastEthReceived(), ethAmount);
    }
}
