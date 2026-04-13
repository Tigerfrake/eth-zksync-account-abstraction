// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "../../src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "../../script/DeployMinimal.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {SendPackedUserOp, PackedUserOperation} from "../../script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccountTest is Test{
    using MessageHashUtils for bytes32;

    DeployMinimal public deployer;
    HelperConfig public helperConfig;
    MinimalAccount public minimalAccount;
    ERC20Mock public usdc;
    SendPackedUserOp public sendPackedUserOp;

    uint256 constant AMOUNT = 1e18;
    address randomUser = makeAddr("rand");

    function setUp() external {
        deployer = new DeployMinimal();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // TEST: USDC mint
    // msg.sender: MinimalAccount
    // Approve some amount
    // come from the EntryPoint,

    function testOwnerCanExecute() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minimalAccount), AMOUNT
        );

        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecute() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minimalAccount), AMOUNT
        );

        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoverSignedOp() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minimalAccount), AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector, dest, value, functionData
        );
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);

        assertEq(actualSigner, minimalAccount.owner());
    }

    // 1. sign user op
    // 2. call validateUserOp 
    // 3. check that the user op is valid and can be executed by the entry point
    function testValidationOfUserOps() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minimalAccount), AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector, dest, value, functionData
        );
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        vm.startPrank(helperConfig.getConfig().entryPoint);
        uint256 missingAccountFunds = 1e18;
        vm.deal(address(minimalAccount), missingAccountFunds);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);

        assertEq(validationData, 0);
    }

    function testEntryPointCanExecute() public {
        // 1. sign user op
        // 2. call handleOps on the entry point
        // 3. check that the user op is executed and the state changes as expected
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minimalAccount), AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector, dest, value, functionData
        );
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        uint256 missingAccountFunds = 5e18;
        vm.deal(address(minimalAccount), missingAccountFunds);

        // this is the bundler calling handleOps on the entry point
        vm.prank(randomUser);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomUser));

        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}