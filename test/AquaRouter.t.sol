// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AquaRouter } from "src/AquaRouter.sol";
import { MockToken } from "./mock/ERC20.sol";

/// @dev Smoke test: verifies rescueFunds works on the real AquaRouter.
/// Constructor and Rescuable logic are covered in solidity-utils.
contract AquaRouterTest is Test {
    function test_RescueFundsERC20() public {
        address owner = address(0xBEEF);
        AquaRouter router = new AquaRouter(owner);
        MockToken token = new MockToken("Stuck");

        uint256 amount = 100e18;
        token.transfer(address(router), amount);

        vm.prank(owner);
        router.rescueFunds(IERC20(address(token)), amount);

        assertEq(token.balanceOf(owner), amount);
        assertEq(token.balanceOf(address(router)), 0);
    }
}
