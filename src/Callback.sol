// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Interaction} from "./types/Interaction.sol";
import {Callback} from "./types/Callback.sol";
import {CallbackLibrary} from "./lib/CallbackLibrary.sol";

/**
 * @title CallbackScheduler
 * @notice A contract that allows users to schedule a callback to be executed
 *         in a specified block at a specified gas price, with the user paying the gas from
 *         a deposit. The sequencer (or anyone) can call `executeCallback`
 *         in the correct block to perform the callback.
 *
 *         The "special" behavior that ensures the callback will be invoked even in
 *         the same block (after the transaction that scheduled the callback)
 *         is purely off-chain logic in the L2 sequencer. This code itself is a normal
 *         Solidity contract.
 */
contract CallbackScheduler {
    using CallbackLibrary for bytes;

    uint256 constant EXTRA_GAS = 50000; // intrinsic gas plus gas for execution before and after callback

    mapping(bytes32 callbackId => bool scheduled) public callbacks;

    event CallbackScheduled(
        bytes32 indexed callbackId,
        address indexed user,
        Interaction interaction,
        uint256 callbackBlock,
        uint256 callbackGasPrice
    );

    event CallbackExecuted(bytes32 indexed callbackId, uint256 gasUsed, uint256 refund);
    /**
     * @notice Schedule a callback to be executed at `_callbackBlock` and `_callbackGasPrice`.
     * @param _interaction The interaction to be executed in the callback.
     * @param _callbackBlock The block at which the callback must execute.
     * @param _callbackGasPrice The gas price of the callback transaction.
     *
     * `msg.value` must be enough to cover expected gas fees.
     */

    function scheduleCallback(Interaction calldata _interaction, uint256 _callbackBlock, uint256 _callbackGasPrice)
        external
        payable
        returns (bytes32 callbackId)
    {
        require(_interaction.target != address(0), "Invalid target address");
        uint256 maxGasCost = (_interaction.gas + EXTRA_GAS) * _callbackGasPrice;
        require(msg.value == maxGasCost + _interaction.value, "Insufficient deposit");

        Callback memory cb = Callback({
            user: payable(msg.sender),
            interaction: _interaction,
            callbackBlock: _callbackBlock,
            callbackGasPrice: _callbackGasPrice
        });

        callbackId = cb.encode();
        require(callbacks[callbackId] == false, "callback already scheduled");
        callbacks[callbackId] = true;

        emit CallbackScheduled(callbackId, msg.sender, _interaction, _callbackBlock, _callbackGasPrice);
    }

    /**
     * @notice Execute the callback in the exact block specified by the user.
     *         The executor (sequencer) is paid from the user's deposit.
     * @param _callbackPayload The encoded callback payload.
     *
     * Requirements:
     * - Must be called in the exact block that the user specified.
     * - Must not have already been executed.
     * todo: Think about whether it would make more sense to specify the transaction priority instead of the gas price.
     * - The current gas price must match exactly the user's callbackGasPrice.
     * - Must provide enough gas to execute the callback.
     */
    function executeCallback(bytes calldata _callbackPayload) external {
        Callback memory cb = _callbackPayload.decode();
        bytes32 callbackId = cb.encode();
        require(callbacks[callbackId] == true, "callback not scheduled");
        require(block.number == cb.callbackBlock, "Wrong block");
        require(tx.gasprice == cb.callbackGasPrice, "Wrong gas price");

        callbacks[cb.encode()] = false;

        uint256 gasBefore = gasleft();

        cb.interaction.execute();

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter + EXTRA_GAS;
        uint256 gasCost = gasUsed * cb.callbackGasPrice;

        uint256 refund = (cb.interaction.gas) * cb.callbackGasPrice - gasCost;
        emit CallbackExecuted(callbackId, gasUsed, refund);
        if (refund > 0) {
            (bool success,) = cb.user.call{value: refund}("");
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @notice Allow user to recover their deposit if the target time for the callback has passed but the callback was not executed.
     */
    function recoverDeposit(bytes calldata _callbackPayload) external {
        Callback memory cb = _callbackPayload.decode();
        bytes32 callbackId = cb.encode();
        require(callbacks[callbackId] == true, "callback not scheduled");
        require(
            block.number > cb.callbackBlock || (block.number == cb.callbackBlock && tx.gasprice < cb.callbackGasPrice),
            "Too early to recover"
        );

        callbacks[callbackId] = false;

        // Refund everything since it wasn't executed
        uint256 refundAmount = (cb.interaction.gas) * cb.callbackGasPrice + cb.interaction.value;
        (bool success,) = payable(cb.user).call{value: refundAmount}("");
        require(success, "ETH transfer failed");
    }
}
