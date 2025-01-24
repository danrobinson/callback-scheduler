// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {CallbackScheduler} from "../src/Callback.sol";
import {Interaction} from "../src/types/Interaction.sol";
import {Callback} from "../src/types/Callback.sol";
import {MockTarget} from "./mocks/MockTarget.sol";

contract CallbackSchedulerTest is Test {
    CallbackScheduler public scheduler;
    MockTarget public target;

    uint256 constant EXTRA_GAS = 50000;
    uint256 constant CALLBACK_GAS = 100000;
    uint256 constant GAS_PRICE = 1 gwei;
    uint256 constant CALLBACK_VALUE = 0.1 ether;

    function setUp() public {
        scheduler = new CallbackScheduler();
        target = new MockTarget();
    }

    function test_ScheduleCallback() public {
        // Create interaction
        Interaction memory interaction = Interaction({
            target: address(target),
            payload: abi.encodeWithSignature("setValue(uint256)", 42),
            value: CALLBACK_VALUE,
            gas: CALLBACK_GAS
        });

        uint256 callbackBlock = block.number + 1;
        uint256 deposit = (CALLBACK_GAS + EXTRA_GAS) * GAS_PRICE + CALLBACK_VALUE;

        // Schedule callback
        vm.deal(address(this), deposit);
        bytes32 callbackId = scheduler.scheduleCallback{value: deposit}(interaction, callbackBlock, GAS_PRICE);

        assertTrue(scheduler.callbacks(callbackId), "Callback should be scheduled");
    }

    function test_ExecuteCallback() public {
        // Schedule callback first
        Interaction memory interaction = Interaction({
            target: address(target),
            payload: abi.encodeWithSignature("setValue(uint256)", 42),
            value: CALLBACK_VALUE,
            gas: CALLBACK_GAS
        });

        uint256 callbackBlock = block.number + 1;
        uint256 deposit = (CALLBACK_GAS + EXTRA_GAS) * GAS_PRICE + CALLBACK_VALUE;

        vm.deal(address(this), deposit);
        scheduler.scheduleCallback{value: deposit}(interaction, callbackBlock, GAS_PRICE);

        // Create callback payload
        Callback memory cb = Callback({
            user: payable(address(this)),
            interaction: interaction,
            callbackBlock: callbackBlock,
            callbackGasPrice: GAS_PRICE
        });

        // Execute callback
        vm.roll(callbackBlock);
        vm.txGasPrice(GAS_PRICE);
        scheduler.executeCallback(abi.encode(cb));

        assertEq(target.value(), 42, "Callback execution failed");
    }

    function test_RecoverDeposit() public {
        Interaction memory interaction = Interaction({
            target: address(target),
            payload: abi.encodeWithSignature("setValue(uint256)", 42),
            value: CALLBACK_VALUE,
            gas: CALLBACK_GAS
        });

        uint256 callbackBlock = block.number + 1;
        uint256 deposit = (CALLBACK_GAS + EXTRA_GAS) * GAS_PRICE + CALLBACK_VALUE;

        vm.deal(address(this), deposit);
        scheduler.scheduleCallback{value: deposit}(interaction, callbackBlock, GAS_PRICE);

        Callback memory cb = Callback({
            user: payable(address(this)),
            interaction: interaction,
            callbackBlock: callbackBlock,
            callbackGasPrice: GAS_PRICE
        });

        // Move to block after callback block
        vm.roll(callbackBlock + 1);

        uint256 balanceBefore = address(this).balance;
        scheduler.recoverDeposit(abi.encode(cb));
        uint256 balanceAfter = address(this).balance;

        assertEq(balanceAfter - balanceBefore, CALLBACK_GAS * GAS_PRICE + CALLBACK_VALUE, "Incorrect refund amount");
    }

    function testFail_ExecuteCallback_WrongBlock() public {
        Interaction memory interaction = Interaction({
            target: address(target),
            payload: abi.encodeWithSignature("setValue(uint256)", 42),
            value: CALLBACK_VALUE,
            gas: CALLBACK_GAS
        });

        uint256 callbackBlock = block.number + 1;
        uint256 deposit = (CALLBACK_GAS + EXTRA_GAS) * GAS_PRICE + CALLBACK_VALUE;

        vm.deal(address(this), deposit);
        scheduler.scheduleCallback{value: deposit}(interaction, callbackBlock, GAS_PRICE);

        Callback memory cb = Callback({
            user: payable(address(this)),
            interaction: interaction,
            callbackBlock: callbackBlock,
            callbackGasPrice: GAS_PRICE
        });

        // Try to execute in wrong block
        vm.roll(callbackBlock + 1);
        scheduler.executeCallback(abi.encode(cb));
    }

    function testFail_ExecuteCallback_WrongGasPrice() public {
        // Schedule callback first
        Interaction memory interaction = Interaction({
            target: address(target),
            payload: abi.encodeWithSignature("setValue(uint256)", 42),
            value: CALLBACK_VALUE,
            gas: CALLBACK_GAS
        });

        uint256 callbackBlock = block.number + 1;
        uint256 deposit = (CALLBACK_GAS + EXTRA_GAS) * GAS_PRICE + CALLBACK_VALUE;

        vm.deal(address(this), deposit);
        scheduler.scheduleCallback{value: deposit}(interaction, callbackBlock, GAS_PRICE);

        // Create callback payload
        Callback memory cb = Callback({
            user: payable(address(this)),
            interaction: interaction,
            callbackBlock: callbackBlock,
            callbackGasPrice: GAS_PRICE
        });

        // Try to execute with wrong gas price
        vm.roll(callbackBlock);
        vm.txGasPrice(GAS_PRICE * 2); // Set different gas price
        scheduler.executeCallback(abi.encode(cb));
    }

    receive() external payable {}
}
