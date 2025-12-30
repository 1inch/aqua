// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { Simulator } from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import { Multicall } from "@1inch/solidity-utils/contracts/mixins/Multicall.sol";

import { Aqua } from "./Aqua.sol";

/// @title AquaRouter - Main deployment entry point for Aqua protocol
/// @notice Combines Aqua core functionality with Simulator for gas estimation and Multicall for batched operations
/// @dev This is the recommended contract to deploy for production use
contract AquaRouter is Aqua, Simulator, Multicall { }
