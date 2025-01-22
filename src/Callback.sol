// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

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
    uint256 constant EXTRA_GAS = 50000; // intrinsic gas plus gas for execution before and after callback

    struct Callback {
        // The user who is scheduling this callback
        address payable user;
        // Contract to be called
        address target;
        // Calldata to forward
        bytes data;
        // The block in which this callback must be executed
        uint256 callbackBlock;
        // The gas price of the callback transaction
        uint256 callbackGasPrice;
        // The gas limit for the callback call
        uint256 callbackGasLimit;
        // The deposit made by the user to pay for gas and optionally forward some ETH
        uint256 deposit;
        // Whether this callback has been executed
        bool executed;
    }

    uint256 public callbackCount;
    mapping(uint256 => Callback) public callbacks;

    event CallbackScheduled(
        uint256 indexed callbackId,
        address indexed user,
        address target,
        uint256 callbackBlock,
        uint256 callbackGasPrice,
        uint256 gasLimit,
        uint256 deposit
    );

    event CallbackExecuted(
        uint256 indexed callbackId,
        bool success,
        uint256 gasUsed,
        uint256 gasCost,
        uint256 refund
    );

    /**
     * @notice Schedule a callback to be executed at `_callbackBlock` and `_callbackGasPrice`.
     * @param _target Address of the contract to call.
     * @param _data Calldata for the contract call.
     * @param _callbackBlock The block at which the callback must execute.
     * @param _callbackGasPrice The gas price of the callback transaction.
     * @param _callbackGasLimit The gas limit for the callback call.
     *
     * `msg.value` must be enough to cover expected gas fees.
     */
    function scheduleCallback(
        address _target,
        bytes calldata _data,
        uint256 _callbackBlock,
        uint256 _callbackGasPrice,
        uint256 _callbackGasLimit
    )
        external
        payable
        returns (uint256 callbackId)
    {
        require(_target != address(0), "Invalid target address");
        uint256 maxGasCost = (_callbackGasLimit + EXTRA_GAS) * _callbackGasPrice;
        require(msg.value >= maxGasCost, "Insufficient deposit");

        callbackId = ++callbackCount;

        callbacks[callbackId] = Callback({
            user: payable(msg.sender),
            target: _target,
            data: _data,
            callbackBlock: _callbackBlock,
            callbackGasPrice: _callbackGasPrice,
            callbackGasLimit: _callbackGasLimit,
            deposit: msg.value,
            executed: false
        });

        emit CallbackScheduled(
            callbackId,
            msg.sender,
            _target,
            _callbackBlock,
            _callbackGasPrice,
            _callbackGasLimit,
            msg.value
        );
    }

    /**
     * @notice Execute the callback in the exact block specified by the user.
     *         The executor (sequencer) is paid from the user's deposit.
     * @param _callbackId The ID of the callback to execute.
     *
     * Requirements:
     * - Must be called in the exact block that the user specified.
     * - Must not have already been executed.
     * - The current gas price must match exactly the user's callbackGasPrice.
     * - Must provide enough gas to execute the callback.
     */
    function executeCallback(uint256 _callbackId) external {
        Callback storage cb = callbacks[_callbackId];

        require(!cb.executed, "Callback already executed");
        require(block.number == cb.callbackBlock, "Wrong block");
        require(tx.gasprice == cb.callbackGasPrice, "Wrong gas price");

        cb.executed = true;

        uint256 gasBefore = gasleft();

        (bool _success, ) = cb.target.call{gas: cb.callbackGasLimit}(cb.data);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter + EXTRA_GAS;
        uint256 gasCost = gasUsed * cb.callbackGasPrice;

        payable(msg.sender).transfer(gasCost);

        uint256 refund = cb.deposit - gasCost;
        if (refund > 0) {
            cb.user.transfer(refund);
        }

        emit CallbackExecuted(_callbackId, _success, gasUsed, gasCost, refund);
    }

    /**
     * @notice Allow user to recover their deposit if the target time for the callback has passed but the callback was not executed.
     */
    function recoverDeposit(uint256 _callbackId) external {
        Callback storage cb = callbacks[_callbackId];
        require(!cb.executed, "Callback executed");
        require(block.number > cb.callbackBlock || (block.number == cb.callbackBlock && tx.gasprice < cb.callbackGasPrice), "Too early to recover");

        cb.executed = true;
        // Refund everything since it wasn't executed
        payable(cb.user).transfer(cb.deposit);
    }
}
