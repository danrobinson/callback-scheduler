// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {InteractionLibrary} from "../lib/InteractionLibrary.sol";

using InteractionLibrary for Interaction global;

struct Interaction {
    address target;
    bytes payload;
    uint256 value;
    uint256 gas;
}
