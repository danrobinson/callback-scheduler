// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Interaction} from "../types/Interaction.sol";

library InteractionLibrary {
    function execute(Interaction memory interaction) internal returns (bool success) {
        (success,) = interaction.target.call{value: interaction.value}(interaction.payload);
    }
}
