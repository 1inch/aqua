// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Vm } from "forge-std/Vm.sol";

// solhint-disable no-console
import { console2 } from "forge-std/console2.sol";

library Config {
    error OwnerAddressDoesNotExist();

    function readAquaRouterParameters(Vm vm) internal view returns (
        address owner
    ) {
        uint256 chain = block.chainid;

        string memory path = string.concat(vm.projectRoot(), "/config/constants.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".", vm.toString(chain));

        owner = vm.parseJsonAddress(json, string.concat(".owner", key));
        if (owner == address(0)) revert OwnerAddressDoesNotExist();
        console2.log("Owner address:", owner);
    }
}
