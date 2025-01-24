// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CallbackLibrary} from "../lib/CallbackLibrary.sol";
import {Interaction} from "./Interaction.sol";

using CallbackLibrary for Callback global;

struct Callback {
    // The user who is scheduling this callback
    address payable user;
    // Interaction to be executed
    Interaction interaction;
    // The block in which this callback must be executed
    uint256 callbackBlock;
    // The gas price of the callback transaction
    uint256 callbackGasPrice;
}
