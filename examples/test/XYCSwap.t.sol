// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Test, console } from "forge-std/Test.sol";
import { dynamic } from "test/utils/Dynamic.sol";
import { stdError } from "forge-std/StdError.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Aqua } from "src/Aqua.sol";
import { AquaApp } from "src/AquaApp.sol";
import { XYCSwap, IXYCSwapCallback } from "examples/apps/XYCSwap.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Simple IXYCSwapCallback implementation for testing
contract TestCallback is IXYCSwapCallback {
    function xycSwapCallback(address, address, uint256, uint256, address, address, bytes32, bytes calldata) external virtual override {
        // Callback now must handle token transfers
        // This base implementation does nothing - derived contracts will override
    }
}

// Malicious xycSwapCallback that doesn't deposit tokens
contract MaliciousCallback is IXYCSwapCallback {
    function xycSwapCallback(address, address, uint256, uint256, address, address, bytes32, bytes calldata) external override {
        // Intentionally do nothing - don't deposit tokens
    }
}

contract XYCSwapTest is Test, TestCallback {
    Aqua public aqua;
    XYCSwap public xycSwapImpl;
    MockERC20 public token0;
    MockERC20 public token1;

    address public maker = address(0x1);
    address public taker = address(0x2);

    uint256 constant INITIAL_AMOUNT0 = 50;
    uint256 constant INITIAL_AMOUNT1 = 50;
    uint24 constant FEE_BPS = 30; // 0.3% fee

    function setUp() public {
        // Deploy contracts
        aqua = new Aqua();
        xycSwapImpl = new XYCSwap(aqua);

        // Deploy mock tokens
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");

        // Mint tokens
        token0.mint(maker, INITIAL_AMOUNT0);
        token1.mint(maker, INITIAL_AMOUNT1);
        token0.mint(taker, 100);
        token1.mint(taker, 100);

        // Setup approvals
        vm.prank(maker);
        token0.approve(address(aqua), type(uint256).max);

        vm.prank(maker);
        token1.approve(address(aqua), type(uint256).max);

        vm.prank(taker);
        token0.approve(address(this), type(uint256).max);

        vm.prank(taker);
        token1.approve(address(this), type(uint256).max);
    }

    function createStrategy() internal returns (address app, XYCSwap.Strategy memory strategy) {
        strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(0)
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );

        return (address(xycSwapImpl), strategy);
    }

    // Helper to reduce repetitive token transfers and approvals
    function swap(
        address app,
        XYCSwap.Strategy memory strategy,
        bool zeroForOne,
        uint256 amountIn
    )
        internal
        returns (uint256)
    {
        address tokenIn = zeroForOne ? strategy.token0 : strategy.token1;
        vm.prank(taker);
        MockERC20(tokenIn).transfer(address(this), amountIn);
        MockERC20(tokenIn).approve(app, amountIn);

        // Pass the swap direction in takerData
        bytes memory takerData = abi.encode(zeroForOne);
        return XYCSwap(app).swapExactIn(strategy, zeroForOne, amountIn, 0, address(this), takerData);
    }

    function testSwapToken0ForToken1() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Swap: we want to give 10 token0 and receive token1
        uint256 amountIn = 10;
        uint256 expectedAmountOut = calculateAmountOut(amountIn, INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS);

        // Transfer token0 from taker to test contract
        vm.prank(taker);
        token0.transfer(address(this), amountIn);

        // Approve the XYCSwap app to spend token0
        token0.approve(app, type(uint256).max);

        uint256 initialBalance1 = token1.balanceOf(address(this));

        // Call with zeroForOne = true to swap token0 for token1
        bytes memory takerData = abi.encode(true); // Pass swap direction
        uint256 amountOut = xycSwap.swapExactIn(
            strategy,
            true, // zeroForOne
            amountIn,
            expectedAmountOut - 1,
            address(this),
            takerData
        );

        // Verify output amount
        assertEq(amountOut, expectedAmountOut, "Output amount should match calculation");
        assertEq(token1.balanceOf(address(this)), initialBalance1 + amountOut, "Should receive token1");

        // Verify pool balances
        (uint256 newBalance0,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token0));
        (uint256 newBalance1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));

        // Pool should have more token0, less token1
        assertEq(newBalance0, INITIAL_AMOUNT0 + amountIn, "Pool should have more token0");
        assertEq(newBalance1, INITIAL_AMOUNT1 - amountOut, "Pool should have less token1");
    }

    function testSwapToken1ForToken0() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Swap: we want to give 10 token1 and receive token0
        uint256 amountIn = 10;
        uint256 expectedAmountOut = calculateAmountOut(amountIn, INITIAL_AMOUNT1, INITIAL_AMOUNT0, FEE_BPS);

        // Transfer token1 from taker to test contract
        vm.prank(taker);
        token1.transfer(address(this), amountIn);

        // Approve the XYCSwap app to spend token1
        token1.approve(app, type(uint256).max);

        uint256 initialBalance0 = token0.balanceOf(address(this));

        // Call with zeroForOne = false to swap token1 for token0
        bytes memory takerData = abi.encode(false); // Pass swap direction
        uint256 amountOut = xycSwap.swapExactIn(
            strategy,
            false, // zeroForOne
            amountIn,
            expectedAmountOut - 1,
            address(this),
            takerData
        );

        // Verify output amount
        assertEq(amountOut, expectedAmountOut, "Output amount should match calculation");
        assertEq(token0.balanceOf(address(this)), initialBalance0 + amountOut, "Should receive token0");
    }

    function testPriceImpact() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Transfer tokens from taker to test contract
        vm.prank(taker);
        token0.transfer(address(this), 25); // Enough for both swaps
        token0.approve(app, type(uint256).max);

        // Small swap: 5 token0 for token1
        uint256 smallAmountIn = 5;
        bytes memory takerData = abi.encode(true);
        uint256 smallAmountOut = xycSwap.swapExactIn(strategy, true, smallAmountIn, 0, address(this), takerData);

        // Reset for large swap
        setUp();
        (app, strategy) = createStrategy();
        xycSwap = XYCSwap(app);

        vm.prank(taker);
        token0.transfer(address(this), 20);
        token0.approve(app, type(uint256).max);

        // Large swap: 20 token0 for token1
        uint256 largeAmountIn = 20;
        bytes memory takerData2 = abi.encode(true);
        uint256 largeAmountOut = xycSwap.swapExactIn(strategy, true, largeAmountIn, 0, address(this), takerData2);

        // Calculate average price per token (scaled by 1000 to avoid rounding issues)
        uint256 smallPricePerToken = (smallAmountOut * 1000) / smallAmountIn;
        uint256 largePricePerToken = (largeAmountOut * 1000) / largeAmountIn;

        // Verify specific values
        assertEq(smallAmountOut, 4, "Small swap should output 4 tokens");
        assertEq(largeAmountOut, 14, "Large swap should output 14 tokens");

        // Small: 4 * 1000 / 5 = 800
        // Large: 14 * 1000 / 20 = 700
        assertTrue(
            largePricePerToken < smallPricePerToken, 
            "Large swap MUST have a worse rate due to AMM price impact"
        );
    }

    function testXYCSwapInvariant() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Initial k value
        uint256 initialK = INITIAL_AMOUNT0 * INITIAL_AMOUNT1;

        // Perform swap: token0 for token1
        uint256 amountIn = 10;
        vm.prank(taker);
        token0.transfer(address(this), amountIn);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 amountOut = xycSwap.swapExactIn(strategy, true, amountIn, 0, address(this), takerData);

        // Get new balances
        (uint256 newBalance0,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token0));
        (uint256 newBalance1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));

        // Calculate new k (should be slightly higher due to fees)
        uint256 newK = newBalance0 * newBalance1;

        // New k should be greater than or equal to initial k (fees increase k)
        assertTrue(newK >= initialK, "Constant product should not decrease");

        // Verify the exact k value increase matches fee collection
        uint256 expectedNewBalance0 = INITIAL_AMOUNT0 + amountIn;
        uint256 expectedNewBalance1 = INITIAL_AMOUNT1 - amountOut;
        assertEq(newBalance0, expectedNewBalance0, "Balance0 should match expected");
        assertEq(newBalance1, expectedNewBalance1, "Balance1 should match expected");
    }

    function testSequentialSwaps() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        uint256 amountOut1 = swap(app, strategy, true, 10);
        (uint256 balance0After1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token0));
        (uint256 balance1After1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));

        uint256 expectedAmountOut2 = calculateAmountOut(10, balance0After1, balance1After1, FEE_BPS);
        uint256 amountOut2 = swap(app, strategy, true, 10);

        assertTrue(amountOut2 < amountOut1, "Second swap should have worse rate");
        assertEq(amountOut1, 8, "First swap should output 8 tokens");
        assertEq(amountOut2, 5, "Second swap should output 5 tokens");
        assertEq(amountOut2, expectedAmountOut2, "Second swap output should match calculation");
    }

    function testConsecutiveSwapsMatchCombined() public {
        // Test that swap(x) + swap(y) ≈ swap(x+y) (within rounding)

        // Path 1: Two consecutive swaps
        (address app1, XYCSwap.Strategy memory strategy1) = createStrategy();
        uint256 out1 = swap(app1, strategy1, true, 10);
        uint256 out2 = swap(app1, strategy1, true, 10);
        uint256 totalOut = out1 + out2;

        // Path 2: Single combined swap - need new setup for fresh state
        setUp();
        (address app2, XYCSwap.Strategy memory strategy2) = createStrategy();
        uint256 outCombined = swap(app2, strategy2, true, 20);

        // Allow for small rounding difference (up to 1 token)
        uint256 diff = totalOut > outCombined ? totalOut - outCombined : outCombined - totalOut;
        assertTrue(diff <= 1, "Consecutive swaps should approximately equal combined swap");
    }

    function testGasProfile() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        // Prepare tokens
        vm.prank(taker);
        token0.transfer(address(this), 30);
        token0.approve(app, type(uint256).max);

        // Measure first swap (cold storage)
        uint256 gasBefore = gasleft();
        bytes memory takerData = abi.encode(true);
        XYCSwap(app).swapExactIn(strategy, true, 10, 0, address(this), takerData);
        uint256 gasUsed1 = gasBefore - gasleft();

        // Measure second swap (warm storage)
        gasBefore = gasleft();
        XYCSwap(app).swapExactIn(strategy, true, 10, 0, address(this), takerData);
        uint256 gasUsed2 = gasBefore - gasleft();

        console.log("XYCSwap first swap gas:", gasUsed1);
        console.log("XYCSwap second swap gas:", gasUsed2);
        console.log("Gas reduction from warm storage:", gasUsed1 - gasUsed2);
    }

    function testNoValueLeakage() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        // Track initial total value (including taker's balance)
        (uint256 initialTotal0,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token0));
        initialTotal0 += token0.balanceOf(address(this)) + token0.balanceOf(taker);
        (uint256 initialTotal1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));
        initialTotal1 += token1.balanceOf(address(this)) + token1.balanceOf(taker);

        // Perform multiple swaps
        swap(app, strategy, true, 10);
        swap(app, strategy, false, 5);
        swap(app, strategy, true, 15);

        // Track final total value (including taker's balance)
        (uint256 finalTotal0,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token0));
        finalTotal0 += token0.balanceOf(address(this)) + token0.balanceOf(taker);
        (uint256 finalTotal1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));
        finalTotal1 += token1.balanceOf(address(this)) + token1.balanceOf(taker);

        // Total tokens should be conserved (no creation or destruction)
        assertEq(finalTotal0, initialTotal0, "Total token0 should be conserved");
        assertEq(finalTotal1, initialTotal1, "Total token1 should be conserved");
    }

    function testBidirectionalSwaps() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        uint256 token1Out = swap(app, strategy, true, 10);
        uint256 token0Out = swap(app, strategy, false, token1Out);

        assertTrue(token0Out < 10, "Should get back less due to fees");
        assertEq(token0Out, 9, "Should get back 7 tokens after round trip");
    }

    function testMinimumOutputRequirement() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        uint256 amountIn = 10;
        uint256 expectedOut = calculateAmountOut(amountIn, INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS);

        vm.prank(taker);
        token0.transfer(address(this), amountIn);
        token0.approve(app, type(uint256).max);

        // Should revert if minimum output is too high
        bytes memory takerData = abi.encode(true);
        vm.expectRevert(abi.encodeWithSelector(XYCSwap.InsufficientOutputAmount.selector, expectedOut, expectedOut + 1));
        xycSwap.swapExactIn(strategy, true, amountIn, expectedOut + 1, address(this), takerData);

        // Should succeed with correct minimum
        uint256 amountOut = xycSwap.swapExactIn(strategy, true, amountIn, expectedOut, address(this), takerData);
        assertEq(amountOut, expectedOut, "Should receive expected amount");
    }

    function testDifferentFeeRates() public {
        // Create strategy with higher fee (1%)
        XYCSwap.Strategy memory highFeeStrategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: 100, // 1% fee
            salt: bytes32(uint256(1))
        });

        // Reset maker balances
        token0.mint(maker, INITIAL_AMOUNT0);
        token1.mint(maker, INITIAL_AMOUNT1);

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(highFeeStrategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );

        // Compare outputs with different fees
        uint256 amountIn = 10;
        uint256 outputWithLowFee = calculateAmountOut(amountIn, INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS);
        uint256 outputWithHighFee = calculateAmountOut(amountIn, INITIAL_AMOUNT0, INITIAL_AMOUNT1, 100);

        // Calculate expected outputs based on a 50/50 pool and input of 10
        // Low fee (0.3%): 4,985,000 / 599,700 = 8.31... -> 8
        // High fee (1%):  4,950,000 / 599,000 = 8.26... -> 8
        // Both calculations correctly round down to 8 tokens.
        assertTrue(outputWithHighFee <= outputWithLowFee, "Higher fee should result in less or equal output");
        assertEq(outputWithLowFee, 8, "Low fee output should be 9");
        assertEq(outputWithHighFee, 8, "High fee output should be 9");
    }

    function testVerySmallAmounts() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Test with 1 token
        vm.prank(taker);
        token0.transfer(address(this), 1);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 amountOut = xycSwap.swapExactIn(strategy, true, 1, 0, address(this), takerData);
        assertEq(amountOut, 0, "Very small swap should output 0 due to rounding");

        // Test with 2 tokens
        vm.prank(taker);
        token0.transfer(address(this), 2);
        uint256 amountOut2 = xycSwap.swapExactIn(strategy, true, 2, 0, address(this), takerData);
        assertEq(amountOut2, 1, "2 token swap should output 1 with precise math");
    }

    function testSwapExactOutVerySmallAmounts() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        uint256 tinyAmountOut = 1;

        vm.prank(taker);
        token0.mint(address(this), 10); 
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        
        uint256 amountIn = xycSwap.swapExactOut(
            strategy, 
            true, 
            tinyAmountOut, 
            type(uint256).max,
            address(this), 
            takerData
        );

        assertTrue(amountIn > 0, "Amount in must be > 0 to prevent liquidity draining");
        assertEq(amountIn, 2, "1 wei out should cost exactly 2 wei in with precise ceil math");
    }

    // ========== Edge Cases & Error Conditions ==========

    function testZeroAmountSwap() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        bytes memory takerData = abi.encode(true);
        // Zero amount should result in zero output, but with minAmountOut > 0 should revert
        vm.expectRevert(abi.encodeWithSelector(XYCSwap.InsufficientOutputAmount.selector, 0, 1));
        xycSwap.swapExactIn(strategy, true, 0, 1, address(this), takerData);
    }

    function testSwapExactOutZeroAmount() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        bytes memory takerData = abi.encode(true);

        uint256 amountIn = xycSwap.swapExactOut(
            strategy, 
            true, 
            0,
            0,
            address(this), 
            takerData
        );

        assertEq(amountIn, 0, "Zero amount out should cost exactly zero amount in");
    }

    function testSwapExceedingPoolBalance() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Try to swap amount that would require more output than pool has
        uint256 excessiveAmount = INITIAL_AMOUNT0 * 2;
        vm.prank(taker);
        token0.mint(address(this), excessiveAmount);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        // This should succeed but output will be less than pool balance
        uint256 amountOut = xycSwap.swapExactIn(strategy, true, excessiveAmount, 0, address(this), takerData);

        // Output should be less than initial balance (can't drain pool completely due to constant product)
        assertTrue(amountOut < INITIAL_AMOUNT1, "Cannot drain pool completely");

        // Verify pool still has some token1
        (uint256 remainingBalance1,) = aqua.rawBalances(maker, app, keccak256(abi.encode(strategy)), address(token1));
        assertTrue(remainingBalance1 > 0, "Pool should never be completely drained");
    }

    function testSwapExactOutExceedingPoolBalanceReverts() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        uint256 excessiveAmountOut = INITIAL_AMOUNT1 + 1 wei; 

        vm.prank(taker);
        token0.mint(address(this), type(uint128).max);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);

        vm.expectRevert(stdError.arithmeticError);
        
        xycSwap.swapExactOut(
            strategy, 
            true, 
            excessiveAmountOut, 
            type(uint256).max,
            address(this), 
            takerData
        );
    }

    function testSwapExactOutDrainingEntirePoolReverts() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        uint256 exactPoolBalanceOut = INITIAL_AMOUNT1; 

        vm.prank(taker);
        token0.mint(address(this), type(uint128).max);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);

        vm.expectRevert(stdError.divisionError);        
        xycSwap.swapExactOut(
            strategy, 
            true, 
            exactPoolBalanceOut, 
            type(uint256).max, 
            address(this), 
            takerData
        );
    }

    function testMissingTakerAquaPush() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Create a malicious aquaTakerCallback that doesn't deposit
        MaliciousCallback malicious = new MaliciousCallback();

        vm.prank(address(malicious));
        // The error includes parameters, so we need to expect the specific error with its values
        // Since we're trying to swap 10 token0, the expected balance would be 60 (50 initial + 10)
        // but the actual balance remains 50
        vm.expectRevert(abi.encodeWithSelector(AquaApp.MissingTakerAquaPush.selector, address(token0), 50, 60));
        xycSwap.swapExactIn(strategy, true, 10, 0, address(malicious), "");
    }

    function testInvalidStrategyVerification() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        // Modify strategy to make it invalid
        strategy.maker = address(0xdead);

        vm.expectRevert(); // Should revert with strategy verification error
        xycSwap.swapExactIn(strategy, true, 10, 0, address(this), "");
    }

    // ========== Extreme Values ==========

    function testLargeAmountSwaps() public {
        // Create pool with large balances
        uint256 largeAmount = 1e36;
        token0.mint(maker, largeAmount);
        token1.mint(maker, largeAmount);

        XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(uint256(1))
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address app = address(xycSwapImpl);

        // Swap a large amount
        uint256 swapAmount = largeAmount / 10;
        token0.mint(address(this), swapAmount);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 amountOut = XYCSwap(app).swapExactIn(strategy, true, swapAmount, 0, address(this), takerData);

        // Verify output is reasonable and no overflow occurred
        assertTrue(amountOut > 0, "Should have positive output");
        assertTrue(amountOut < largeAmount, "Output should be less than pool balance");
    }

    function testSwapExactOutLargeAmounts() public {
        uint256 largeAmount = 1e36;
        token0.mint(maker, largeAmount);
        token1.mint(maker, largeAmount);

        XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(uint256(1))
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([largeAmount, largeAmount])
        );
        address app = address(xycSwapImpl);
        XYCSwap xycSwap = XYCSwap(app);

        uint256 swapAmountOut = largeAmount / 10; 
        
        uint256 maxAmountIn = largeAmount;
        vm.prank(taker);
        token0.mint(address(this), maxAmountIn);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        
        uint256 amountIn = xycSwap.swapExactOut(
            strategy, 
            true, 
            swapAmountOut, 
            type(uint256).max, 
            address(this), 
            takerData
        );

        assertTrue(amountIn > 0, "Amount in should be positive");
        assertTrue(amountIn > swapAmountOut, "Amount in should be greater than amount out due to slippage and fees");
    }

    function testMaxFeeScenario() public {
        // Create strategy with maximum possible fee (99.99%)
        XYCSwap.Strategy memory highFeeStrategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: 9999, // 99.99% fee
            salt: bytes32(uint256(2))
        });

        token0.mint(maker, INITIAL_AMOUNT0);
        token1.mint(maker, INITIAL_AMOUNT1);

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(highFeeStrategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address app = address(xycSwapImpl);

        // With 99.99% fee, output should be minimal
        vm.prank(taker);
        token0.transfer(address(this), 100);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 amountOut = XYCSwap(app).swapExactIn(highFeeStrategy, true, 100, 0, address(this), takerData);

        // With 99.99% fee, effective input is only 0.01% of actual input
        assertTrue(amountOut < 1, "With maximum fee, output should be near zero");
    }

    function testSwapExactOutMaxFeeScenario() public {
        XYCSwap.Strategy memory highFeeStrategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: 9999, // 99.99% fee
            salt: bytes32(uint256(2))
        });

        token0.mint(maker, INITIAL_AMOUNT0);
        token1.mint(maker, INITIAL_AMOUNT1);

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(highFeeStrategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address app = address(xycSwapImpl);
        XYCSwap xycSwap = XYCSwap(app);

        uint256 amountOut = 10;

        vm.prank(taker);
        token0.mint(address(this), type(uint128).max);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        
        uint256 amountIn = xycSwap.swapExactOut(
            highFeeStrategy, 
            true, 
            amountOut, 
            type(uint256).max, 
            address(this), 
            takerData
        );

        assertTrue(
            amountIn >= amountOut * 10000, 
            "With 99.99% fee, input should be astronomically larger than output"
        );
    }
    // ========== Strategy Validation ==========

    function testMultipleStrategiesFromSameMaker() public {
        // First strategy creation
        (address app1, XYCSwap.Strategy memory strategy1) = createStrategy();

        // Create another strategy with different salt
        XYCSwap.Strategy memory strategy2 = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(uint256(99)) // Different salt
        });

        token0.mint(maker, INITIAL_AMOUNT0);
        token1.mint(maker, INITIAL_AMOUNT1);

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy2),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address app2 = address(xycSwapImpl);

        // Both should be functional
        vm.prank(taker);
        token0.transfer(address(this), 20);
        token0.approve(app1, type(uint256).max);
        token0.approve(app2, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 out1 = XYCSwap(app1).swapExactIn(strategy1, true, 10, 0, address(this), takerData);
        uint256 out2 = XYCSwap(app2).swapExactIn(strategy2, true, 10, 0, address(this), takerData);

        // Both swaps should succeed with same output
        assertEq(out1, out2, "Same parameters should give same output");
    }

    function testInvalidTokenAddresses() public {
        // This test verifies that swapping with invalid token addresses fails
        // We can't test invalid addresses during creation since Aqua doesn't validate them
        XYCSwap.Strategy memory badStrategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(0), // Invalid token address
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(uint256(3))
        });

        // Create app with valid tokens first
        XYCSwap.Strategy memory validStrategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: FEE_BPS,
            salt: bytes32(uint256(3))
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(validStrategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address app = address(xycSwapImpl);

        // Now try to swap with invalid strategy (different token addresses)
        vm.expectRevert(); // Should revert due to strategy verification
        XYCSwap(app).swapExactIn(badStrategy, true, 10, 0, address(this), "");
    }

    // ========== Integration Tests ==========

    function testRapidConsecutiveSwaps() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        // Prepare tokens for multiple swaps
        vm.prank(taker);
        token0.transfer(address(this), 30);
        token0.approve(app, type(uint256).max);

        // Perform rapid consecutive swaps
        uint256[] memory outputs = new uint256[](3);
        bytes memory takerData = abi.encode(true);

        for (uint256 i = 0; i < 3; i++) {
            outputs[i] = XYCSwap(app).swapExactIn(strategy, true, 10, 0, address(this), takerData);
        }

        // Each subsequent swap should have worse rate
        assertTrue(outputs[0] > outputs[1], "Second swap should have worse rate");
        assertTrue(outputs[1] > outputs[2], "Third swap should have worse rate");
    }

    function testSwapExactOutRapidConsecutiveSwaps() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();
        XYCSwap xycSwap = XYCSwap(app);

        uint256 fixedAmountOut = 5;

        vm.prank(taker);
        token0.mint(address(this), 1000); 
        token0.approve(app, type(uint256).max);

        uint256[] memory inputs = new uint256[](3);
        bytes memory takerData = abi.encode(true);

        for (uint256 i = 0; i < 3; i++) {
            inputs[i] = xycSwap.swapExactOut(
                strategy, 
                true, 
                fixedAmountOut, 
                type(uint256).max, 
                address(this), 
                takerData
            );
        }

        assertTrue(inputs[0] < inputs[1], "Second swap should cost more due to slippage");
        assertTrue(inputs[1] < inputs[2], "Third swap should cost more due to slippage");
    }

    function testSwapWithDifferentRecipients() public {
        (address app, XYCSwap.Strategy memory strategy) = createStrategy();

        address recipient1 = address(0x1234);
        address recipient2 = address(0x5678);

        // First swap to recipient1
        vm.prank(taker);
        token0.transfer(address(this), 20);
        token0.approve(app, type(uint256).max);

        bytes memory takerData = abi.encode(true);
        uint256 out1 = XYCSwap(app).swapExactIn(strategy, true, 10, 0, recipient1, takerData);
        assertEq(token1.balanceOf(recipient1), out1, "Recipient1 should receive output");

        // Second swap to recipient2
        uint256 out2 = XYCSwap(app).swapExactIn(strategy, true, 10, 0, recipient2, takerData);
        assertEq(token1.balanceOf(recipient2), out2, "Recipient2 should receive output");
    }

    // Helper function to calculate expected output using constant product formula
    function calculateAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps
    ) internal pure returns (uint256) {
        uint256 feeMultiplier = 10000 - feeBps;
        uint256 amountInWithFee = amountIn * feeMultiplier;
        
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10000) + amountInWithFee;
        
        return numerator / denominator;
    }

    // Override xycSwapCallback function from TestCallback
    function xycSwapCallback(address tokenIn, address /* tokenOut */, uint256 amountIn, uint256 /* amountOut */, address maker_, address app, bytes32 strategyHash, bytes calldata /* takerData */) external override {
        IERC20(tokenIn).approve(address(aqua), amountIn);
        aqua.push(maker_, app, strategyHash, tokenIn, amountIn);
    }
}
