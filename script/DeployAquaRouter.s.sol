// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Script } from "forge-std/Script.sol";

import { Config } from "./utils/Config.sol";

import { AquaRouter } from "../src/AquaRouter.sol";

// solhint-disable no-console
import { console2 } from "forge-std/console2.sol";

contract DeployAquaRouter is Script {
    using Config for *;

    function run() external {
        (address owner) = vm.readAquaRouterParameters();

        vm.startBroadcast();
        AquaRouter aquaRouter = new AquaRouter(owner);
        vm.stopBroadcast();

        console2.log("AquaRouter deployed at: ", address(aquaRouter));
    }
}
// solhint-enable no-console
