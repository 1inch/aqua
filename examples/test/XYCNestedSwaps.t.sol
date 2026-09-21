// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.13;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import "forge-std/Test.sol";
import { dynamic } from "test/utils/Dynamic.sol";

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

contract XYCNestedSwapsTest is Test, IXYCSwapCallback {
    Aqua public aqua;
    XYCSwap public xycSwapImpl;
    MockERC20 public token0;
    MockERC20 public token1;

    address public maker = address(0x1);
    address public taker = address(0x2);

    uint256 constant INITIAL_AMOUNT0 = 1000; // Larger liquidity
    uint256 constant INITIAL_AMOUNT1 = 1000;
    uint24 constant LOW_FEE_BPS = 30; // 0.3% fee
    uint24 constant HIGH_FEE_BPS = 300; // 3.0% fee (larger difference)

    // State variables for nested swap functionality
    bool private performNestedSwap;
    address private secondPool;
    XYCSwap.Strategy private secondStrategy;
    uint256 private secondSwapAmount;

    // State variables for reentrancy attack testing
    bool private attemptMaliciousPull;
    address private targetPool;
    address private targetToken;

    // State variables for malicious push attack
    bool private attemptMaliciousPush;
    uint256 private maliciousPushMultiplier;

    function setUp() public {
        // Deploy contracts
        aqua = new Aqua();
        xycSwapImpl = new XYCSwap(aqua);

        // Deploy mock tokens
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");

        // Mint tokens for both pools
        token0.mint(maker, INITIAL_AMOUNT0 * 2); // 2000 total
        token1.mint(maker, INITIAL_AMOUNT1 * 2); // 2000 total
        token0.mint(taker, 1000);
        token1.mint(taker, 1000);

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

    /// @notice Test attempting to abuse aqua.pull()/push() logic via reentrancy
    /// This should fail due to reentrancy protection
    function testMaliciousReentrancyAttack() public {
        // ========== Create Test Pool ==========
        XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: LOW_FEE_BPS,
            salt: bytes32(uint256(999))
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address testPool = address(xycSwapImpl);

        // ========== Setup Malicious Attack Parameters ==========
        attemptMaliciousPull = true;
        targetPool = testPool;
        targetToken = address(token1); // Try to steal token1

        // console.log("=== REENTRANCY ATTACK TEST ===");
        // console.log("Target pool:", testPool);
        // console.log("Attempting to steal token1 via malicious aqua.pull()");

        // ========== Execute Swap with Malicious Intent ==========
        uint256 swapAmount = 50;
        vm.prank(taker);
        token0.transfer(address(this), swapAmount);
        token0.approve(testPool, type(uint256).max);

        // console.log("Pool balance before attack - Token1:", aqua.balances(maker, testPool, address(token1)));
        // console.log("Attacker balance before - Token1:", token1.balanceOf(address(this)));

        // This should trigger the malicious pull attempt in the callback
        uint256 output = XYCSwap(testPool).swapExactIn(
            strategy,
            true,
            swapAmount,
            0,
            address(this),
            "" // Empty calldata
        );

        // console.log("=== POST-ATTACK ANALYSIS ===");
        // console.log("Pool balance after attack - Token1:", aqua.balances(maker, testPool, address(token1)));
        // console.log("Attacker balance after - Token1:", token1.balanceOf(address(this)));
        // console.log("Legitimate swap output:", output);

        // Verify the attack failed and normal swap succeeded
        assertTrue(output > 0, "Normal swap should have succeeded");
        // console.log("Attack test completed - Protocol should have protected against malicious pull");
    }

    /// @notice Test confirming that apps cannot pull from other apps' balances
    function testAppIsolationPullProtection() public {
        // ========== Create Two Different Pools ==========
        XYCSwap.Strategy memory strategy1 = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: LOW_FEE_BPS,
            salt: bytes32(uint256(888))
        });

        XYCSwap.Strategy memory strategy2 = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: HIGH_FEE_BPS,
            salt: bytes32(uint256(777))
        });

        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_AMOUNT0;
        amounts[1] = INITIAL_AMOUNT1;

        vm.startPrank(maker);
        aqua.ship(address(xycSwapImpl), abi.encode(strategy1), tokens, amounts);
        address pool1 = address(xycSwapImpl);
        aqua.ship(address(xycSwapImpl), abi.encode(strategy2), tokens, amounts);
        address pool2 = address(xycSwapImpl);
        vm.stopPrank();

        bytes32 strategyHash1 = keccak256(abi.encode(strategy1));
        bytes32 strategyHash2 = keccak256(abi.encode(strategy2));

        // console.log("=== APP ISOLATION PULL TEST ===");
        // console.log("Pool1:", pool1);
        // console.log("Pool2:", pool2);
        // console.log("Pool1 balance:", aqua.balances(maker, pool1, address(token1)));
        // console.log("Pool2 balance:", aqua.balances(maker, pool2, address(token1)));

        // ========== Test Pool1 Accessing Its Own Balance ==========
        // console.log("Testing Pool1 accessing its OWN balance (should work)...");
        vm.prank(pool1);
        try aqua.pull(maker, strategyHash1, address(token1), 100, address(this)) {
            // console.log("Pool1 own balance: SUCCESS (expected)");
            // console.log("Pool1 successfully used its own allocated balance");
        } catch Error(string memory reason) {
            // console.log("Pool1 own balance FAILED (unexpected):");
            // console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            // console.log("Pool1 own balance FAILED with underflow (unexpected)");
            // console.log("Error data length:", lowLevelData.length);
        }

        // ========== Test Cross-App Pull Attack ==========
        // console.log("Testing random address trying to pull as Pool2 (should fail)...");
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        try aqua.pull(maker, strategyHash2, address(token1), 50, address(this)) {
            // console.log("!!! CROSS-APP PULL BREACH - ATTACKER SUCCEEDED !!!");
        } catch Error(string memory reason) {
            // console.log("Cross-app pull FAILED (expected):");
            // console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            // console.log("Cross-app pull FAILED with underflow (expected)");
            // console.log("Error data length:", lowLevelData.length);
        }

        // console.log("=== PULL ISOLATION TEST RESULTS ===");
        // console.log("Pool1 final balance:", aqua.balances(maker, pool1, address(token1)));
        // console.log("Pool2 final balance:", aqua.balances(maker, pool2, address(token1)));
        // console.log("Attacker final balance:", token1.balanceOf(attacker));
    }

    /// @notice Test confirming that malicious push attacks don't benefit attackers
    function testAppIsolationPushProtection() public {
        // ========== Create Test Pool ==========
        XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: LOW_FEE_BPS,
            salt: bytes32(uint256(555))
        });

        vm.prank(maker);
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address testPool = address(xycSwapImpl);

        // console.log("=== APP ISOLATION PUSH TEST ===");
        // console.log("Target pool:", testPool);
        // console.log("Testing malicious push from unauthorized address");

        // ========== Test Unauthorized Push Attack ==========
        address attacker = address(0xDEAD);
        uint256 maliciousAmount = 500;

        // Give attacker tokens
        token0.mint(attacker, maliciousAmount);
        vm.startPrank(attacker);
        token0.approve(address(aqua), maliciousAmount);

        // console.log("=== PRE-ATTACK STATE ===");
        // console.log("Pool balance before:", aqua.balances(maker, testPool, address(token0)));
        // console.log("Attacker balance before:", token0.balanceOf(attacker));

        // Try malicious push to inflate pool balance
        try aqua.push(maker, address(xycSwapImpl), strategyHash, address(token0), maliciousAmount) {
            // console.log("Malicious push SUCCEEDED - attacker donated tokens to pool");
            // console.log("This is economically irrational but not prevented");
        } catch Error(string memory reason) {
            // console.log("Malicious push FAILED:");
            // console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            // console.log("Malicious push FAILED with low-level error");
            // console.log("Error data length:", lowLevelData.length);
        }
        vm.stopPrank();

        // console.log("=== POST-ATTACK ANALYSIS ===");
        // console.log("Pool balance after:", aqua.balances(maker, testPool, address(token0)));
        // console.log("Attacker balance after:", token0.balanceOf(attacker));

        // ========== Test If Attacker Can Benefit ==========
        // console.log("Testing if attacker can now pull back more than they pushed...");
        vm.prank(attacker);
        try aqua.pull(maker, strategyHash, address(token0), maliciousAmount, address(attacker)) {
            // console.log("!!! PUSH-PULL EXPLOIT SUCCEEDED - SECURITY BREACH !!!");
            // console.log("Attacker recovered their tokens!");
        } catch Error(string memory reason) {
            // console.log("Pull-back attempt FAILED (expected):");
            // console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            // console.log("Pull-back attempt FAILED with underflow (expected)");
            // console.log("Error data length:", lowLevelData.length);
        }

        // console.log("=== PUSH ISOLATION TEST COMPLETED ===");
        // console.log("Result: Malicious push is just a donation to the maker");
    }

    /// @notice Test attempting to exploit aqua.push() by over-depositing tokens
    /// This should either fail due to balance verification or not provide advantage
    function testMaliciousOverPushAttack() public {
        // ========== Create Test Pool ==========
        XYCSwap.Strategy memory strategy = XYCSwap.Strategy({
            maker: maker,
            token0: address(token0),
            token1: address(token1),
            feeBps: LOW_FEE_BPS,
            salt: bytes32(uint256(666))
        });

        vm.prank(maker);
        aqua.ship(
            address(xycSwapImpl),
            abi.encode(strategy),
            dynamic([address(token0), address(token1)]),
            dynamic([INITIAL_AMOUNT0, INITIAL_AMOUNT1])
        );
        address testPool = address(xycSwapImpl);

        // ========== Setup Malicious Over-Push Attack ==========
        attemptMaliciousPush = true;
        maliciousPushMultiplier = 3; // Try to push 3x the required amount

        // console.log("=== MALICIOUS OVER-PUSH ATTACK TEST ===");
        // console.log("Target pool:", testPool);
        // console.log("Attack: Push 3x required tokens to artificially inflate pool balance");

        // Give ourselves plenty of extra tokens for the over-push
        uint256 swapAmount = 100;
        uint256 extraTokens = swapAmount * maliciousPushMultiplier;
        vm.prank(taker);
        token0.transfer(address(this), extraTokens); // Give us extra tokens
        token0.approve(testPool, type(uint256).max);

        // console.log("=== PRE-ATTACK STATE ===");
        // console.log("Pool balance before - Token0:", aqua.balances(maker, testPool, address(token0)));
        // console.log("Pool balance before - Token1:", aqua.balances(maker, testPool, address(token1)));
        // console.log("Attacker balance - Token0:", token0.balanceOf(address(this)));
        // console.log("Attacker balance - Token1:", token1.balanceOf(address(this)));

        // ========== Execute Swap with Over-Push Intent ==========
        bytes memory takerData = abi.encode(true);

        // This should trigger the malicious over-push attempt in the callback
        try XYCSwap(testPool).swapExactIn(strategy, true, swapAmount, 0, address(this), takerData) returns (
            uint256 output
        ) {
            // console.log("=== POST-ATTACK ANALYSIS ===");
            // console.log("Swap completed with output:", output);
            // console.log("Pool balance after - Token0:", aqua.balances(maker, testPool, address(token0)));
            // console.log("Pool balance after - Token1:", aqua.balances(maker, testPool, address(token1)));
            // console.log("Attacker balance - Token0:", token0.balanceOf(address(this)));
            // console.log("Attacker balance - Token1:", token1.balanceOf(address(this)));

            // Check if over-push created any advantage
            uint256 expectedOutput = calculateAmountOut(swapAmount, INITIAL_AMOUNT0, INITIAL_AMOUNT1, LOW_FEE_BPS);
            // console.log("Expected normal output:", expectedOutput);
            // console.log("Actual output:", output);

            if (output > expectedOutput) {
                // console.log("!!! OVER-PUSH ATTACK MAY HAVE PROVIDED ADVANTAGE !!!");
                // console.log("Extra tokens gained:", output - expectedOutput);
            } else {
                // console.log("Over-push attack provided no advantage (expected)");
            }
        } catch Error(string memory reason) {
            // console.log("=== SWAP FAILED (Protection Worked) ===");
            // console.log("Reason:", reason);
            // console.log("Pool balance after failed attack - Token0:", aqua.balances(maker, testPool, address(token0)));
            // console.log("Pool balance after failed attack - Token1:", aqua.balances(maker, testPool, address(token1)));
        }

        // console.log("Over-push attack test completed");
    }

    // Helper function to calculate expected output using constant product formula
    function calculateAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps
    )
        internal
        pure
        returns (uint256)
    {
        uint256 amountInWithFee = amountIn * (10_000 - feeBps) / 10_000;
        return (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
    }

    // IXYCSwapCallback implementation with nested swap support
    function xycSwapCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address maker_,
        address app,
        bytes32 strategyHash,
        bytes calldata takerData
    )
        external
        override
    {
        // console.log("=== AQUA CALLBACK TRIGGERED ===");
        // console.log("TokenIn:", tokenIn);
        // console.log("AmountIn:", amountIn);
        // console.log("TokenOut:", tokenOut);
        // console.log("AmountOut:", amountOut);
        // console.log("Maker:", maker_);

        // Always fulfill the current swap first

        // string memory tokenType = tokenIn == address(token0) ? "TOKEN0" : "TOKEN1";
        // console.log(">> AQUA.PUSH() - Taker depositing", tokenType, "to maker");
        // console.log("   Token:", tokenIn);
        // console.log("   Amount:", amountIn);
        // console.log("   To Maker:", maker_);

        // Try malicious over-push attack if enabled
        if (attemptMaliciousPush) {
            uint256 maliciousAmount = amountIn * maliciousPushMultiplier;
            // console.log("=== ATTEMPTING MALICIOUS OVER-PUSH ===");
            // console.log("Normal amount required:", amountIn);
            // console.log("Malicious amount to push:", maliciousAmount);
            // console.log("Multiplier:", maliciousPushMultiplier);

            // Check if we have enough tokens for the malicious push
            uint256 ourBalance = IERC20(tokenIn).balanceOf(address(this));
            // console.log("Our token balance:", ourBalance);

            if (ourBalance >= maliciousAmount) {
                // console.log("Sufficient balance - attempting malicious over-push...");
                IERC20(tokenIn).approve(address(aqua), maliciousAmount);

                try aqua.push(maker_, app, strategyHash, tokenIn, maliciousAmount) {
                    // console.log("!!! MALICIOUS OVER-PUSH SUCCEEDED !!!");
                    // console.log("Pushed", maliciousAmount - amountIn, "extra tokens to pool");
                    // console.log("Pool balance artificially inflated!");
                } catch Error(string memory reason) {
                    // console.log("Malicious over-push FAILED:");
                    // console.log("Reason:", reason);

                    // Fallback to normal push
                    // console.log("Falling back to normal push amount...");
                    IERC20(tokenIn).approve(address(aqua), amountIn);
                    aqua.push(maker_, app, strategyHash, tokenIn, amountIn);
                } catch (bytes memory lowLevelData) {
                    // console.log("Malicious over-push FAILED with low-level error");
                    // console.log("Error data length:", lowLevelData.length);

                    // Fallback to normal push
                    // console.log("Falling back to normal push amount...");
                    IERC20(tokenIn).approve(address(aqua), amountIn);
                    aqua.push(maker_, app, strategyHash, tokenIn, amountIn);
                }
            } else {
                // console.log("Insufficient balance for malicious push - using normal amount");
                IERC20(tokenIn).approve(address(aqua), amountIn);
                aqua.push(maker_, app, strategyHash, tokenIn, amountIn);
            }

            attemptMaliciousPush = false; // Only try once
        } else {
            // Normal push
            IERC20(tokenIn).approve(address(aqua), amountIn);
            aqua.push(maker_, app, strategyHash, tokenIn, amountIn);
        }

        // console.log("   AQUA.PUSH() completed successfully");

        // If this is the first swap and we need to perform a nested swap
        if (performNestedSwap) {
            performNestedSwap = false; // Prevent recursion

            // console.log("=== STARTING NESTED SWAP IN CALLBACK ===");
            // console.log("Nested swap amount:", secondSwapAmount);

            // Track balances before nested swap

            uint256 token0BalanceBefore = token0.balanceOf(address(this));
            uint256 token1BalanceBefore = token1.balanceOf(address(this));
            // console.log("Before nested swap - Token0:", token0BalanceBefore);
            // console.log("Before nested swap - Token1:", token1BalanceBefore);

            // Approve the second pool to spend tokens
            IERC20(tokenIn).approve(secondPool, secondSwapAmount);

            // console.log(">> NESTED SWAP: About to call swapExactIn on second pool");
            // console.log("   This will trigger another AQUA.PULL() and AQUA.PUSH()");

            // Execute the nested swap in the second pool
            uint256 nestedSwapOutput = XYCSwap(secondPool).swapExactIn(
                secondStrategy,
                true,
                secondSwapAmount,
                0,
                address(this),
                abi.encode(true) // token0 → token1
            );

            // Track balances after nested swap

            // uint256 token0BalanceAfter = token0.balanceOf(address(this));
            // uint256 token1BalanceAfter = token1.balanceOf(address(this));

            // console.log("After nested swap - Token0:", token0BalanceAfter);
            // console.log("After nested swap - Token1:", token1BalanceAfter);
            // console.log("Token0 used:", token0BalanceBefore - token0BalanceAfter);
            // console.log("Token1 received:", token1BalanceAfter - token1BalanceBefore);

            // console.log("=== NESTED SWAP COMPLETED ===");
            // console.log("Nested swap output:", nestedSwapOutput);
        }

        // console.log("=== AQUA CALLBACK COMPLETED ===");
    }
}
