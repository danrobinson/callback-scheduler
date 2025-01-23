// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Callback} from "../types/Callback.sol";

library CallbackLibrary {
    function encode(Callback memory callback) internal pure returns (bytes32) {
        return keccak256(abi.encode(callback));
    }

    function decode(bytes calldata callback) internal pure returns (Callback memory) {
        return abi.decode(callback, (Callback));
    }
}
