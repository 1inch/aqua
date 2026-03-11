// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Simulator } from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import { Multicall } from "@1inch/solidity-utils/contracts/mixins/Multicall.sol";
import { Rescuable } from "@1inch/solidity-utils/contracts/mixins/Rescuable.sol";

import { Aqua } from "./Aqua.sol";

/// @title AquaRouter - Main deployment entry point for Aqua protocol
/// @notice Combines Aqua core functionality with Simulator for gas estimation, Multicall for batched operations, and Rescuable for token recovery
/// @dev This is the recommended contract to deploy for production use
/// @dev This contract is Ownable via Rescuable mixin
contract AquaRouter is Aqua, Simulator, Multicall, Rescuable {

    /// @notice owner is used only to rescue funds
    /// @param owner The owner of the contract, the reciever of the rescued funds, authorized to rescue stuck tokens and ETH
    constructor(address owner) Rescuable(owner) { }
}
