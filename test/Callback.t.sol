// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Callback.sol";

contract MockTarget is ISchedulerCallback {
    bool public called;
    bytes public receivedData;

    function handleSchedulerCallback(bytes calldata data) external {
        called = true;
        receivedData = data;
    }
}

contract CallbackSchedulerTest is Test {
    CallbackScheduler public scheduler;
    MockTarget public target;
    address payable public user;
    uint256 public constant GAS_PRICE = 1 gwei;
    uint256 public constant GAS_LIMIT = 200000;
    uint256 public constant EXTRA_GAS = 50000;

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
        uint256 gasUsed,
        uint256 refund
    );

    function setUp() public {
        scheduler = new CallbackScheduler();
        target = new MockTarget();
        user = payable(address(0x2));
        vm.deal(user, 100 ether);
    }

    function testScheduleCallback() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        assertEq(scheduler.callbackCount(), 0);

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit CallbackScheduled(
            1, // callbackId
            user,
            address(target),
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT,
            deposit
        );

        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );
        vm.stopPrank();

        assertEq(callbackId, 1);
        assertEq(scheduler.callbackCount(), 1);
    }

    function testExecuteCallback() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        vm.roll(block.number + 1);
        vm.txGasPrice(GAS_PRICE);

        address payable executor = payable(address(0x2));
        uint256 executorBalanceBefore = executor.balance;

        vm.expectEmit(true, false, false, false);
        emit CallbackExecuted(callbackId, 0, 0);

        vm.prank(executor);
        scheduler.executeCallback{gas: GAS_LIMIT + EXTRA_GAS}(callbackId);

        assertTrue(target.called());
        assertEq(target.receivedData(), data);
        assertTrue(executor.balance > executorBalanceBefore);
    }

    function testExecuteCallbackWrongBlock() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        vm.txGasPrice(GAS_PRICE);
        vm.expectRevert("Wrong block");
        scheduler.executeCallback(callbackId);
    }

    function testExecuteCallbackWrongGasPrice() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        vm.roll(block.number + 1);
        vm.txGasPrice(GAS_PRICE - 1 gwei);
        vm.expectRevert("Wrong gas price");
        scheduler.executeCallback(callbackId);
    }

    function testRecoverDepositAfterTargetBlock() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        uint256 userBalanceBefore = user.balance;
        
        // Move to block after target
        vm.roll(block.number + 2);

        vm.prank(user);
        scheduler.recoverDeposit(callbackId);

        assertEq(user.balance, userBalanceBefore + deposit);
    }

    function testCannotRecoverDepositBeforeTargetBlock() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );
        
        vm.prank(user);
        vm.expectRevert("Too early to recover");
        scheduler.recoverDeposit(callbackId);
    }

    function testCannotRecoverDepositInTargetBlockBeforeGasPrice() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );
        
        vm.roll(block.number + 1);
        vm.txGasPrice(GAS_PRICE);
        
        vm.prank(user);
        vm.expectRevert("Too early to recover");
        scheduler.recoverDeposit(callbackId);
    }

    function testCannotRecoverExecutedDeposit() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        vm.roll(block.number + 1);
        vm.txGasPrice(GAS_PRICE);
        
        vm.expectEmit(true, false, false, false);
        emit CallbackExecuted(callbackId, 0, 0);

        vm.prank(address(0x3));
        scheduler.executeCallback{gas: GAS_LIMIT + EXTRA_GAS}(callbackId);

        vm.roll(block.number + 1);
        vm.prank(user);
        vm.expectRevert("Callback executed");
        scheduler.recoverDeposit(callbackId);
    }

    function testCanRecoverDepositInTargetBlockAfterGasPrice() public {
        uint256 deposit = (GAS_LIMIT + EXTRA_GAS) * GAS_PRICE;
        bytes memory data = abi.encode(42);

        vm.prank(user);
        uint256 callbackId = scheduler.scheduleCallback{value: deposit}(
            address(target),
            data,
            block.number + 1,
            GAS_PRICE,
            GAS_LIMIT
        );

        uint256 userBalanceBefore = user.balance;
        
        vm.roll(block.number + 1);
        vm.txGasPrice(GAS_PRICE - 1);

        vm.prank(user);
        scheduler.recoverDeposit(callbackId);

        assertEq(user.balance, userBalanceBefore + deposit);
    }
}