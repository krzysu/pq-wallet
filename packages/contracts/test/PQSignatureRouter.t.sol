// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PQSignatureRouter} from "../src/PQSignatureRouter.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";

contract MockPQVerifier is IPQVerifier {
    function registerKey(
        bytes calldata publicKey
    ) external pure returns (bytes32) {
        return keccak256(publicKey);
    }

    function verify(
        bytes32,
        bytes calldata signature,
        bytes32
    ) external pure returns (bool) {
        return signature.length > 0 && uint8(signature[0]) > 0;
    }
}

contract PQSignatureRouterTest is Test {
    PQSignatureRouter router;
    MockPQVerifier mockVerifier;
    address routerOwner;
    address validatorAddr;

    function setUp() public {
        routerOwner = makeAddr("routerOwner");
        validatorAddr = makeAddr("validator");
        router = new PQSignatureRouter(routerOwner);
        mockVerifier = new MockPQVerifier();

        // Set the validator
        vm.prank(routerOwner);
        router.setValidator(validatorAddr);
    }

    function test_registerVerifier() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        assertEq(address(router.verifiers(1)), address(mockVerifier));
    }

    function test_registerVerifier_onlyOwner() public {
        vm.expectRevert();
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));
    }

    function test_registerVerifier_revertIfAlreadyRegistered() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        MockPQVerifier anotherVerifier = new MockPQVerifier();
        vm.prank(routerOwner);
        vm.expectRevert(abi.encodeWithSelector(PQSignatureRouter.VerifierAlreadyRegistered.selector, 1));
        router.registerVerifier(1, IPQVerifier(address(anotherVerifier)));
    }

    function test_registerVerifier_revertIfReregisteredAfterDisable() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        vm.prank(routerOwner);
        router.disableVerifier(1);

        // Attempt to re-register a new verifier for the same scheme — must fail
        MockPQVerifier anotherVerifier = new MockPQVerifier();
        vm.prank(routerOwner);
        vm.expectRevert(abi.encodeWithSelector(PQSignatureRouter.VerifierAlreadyRegistered.selector, 1));
        router.registerVerifier(1, IPQVerifier(address(anotherVerifier)));
    }

    function test_registerVerifier_revertIfZeroAddress() public {
        vm.prank(routerOwner);
        vm.expectRevert(PQSignatureRouter.InvalidVerifierAddress.selector);
        router.registerVerifier(1, IPQVerifier(address(0)));
    }

    function test_registerVerifier_revertIfEOA() public {
        vm.prank(routerOwner);
        vm.expectRevert(PQSignatureRouter.InvalidVerifierAddress.selector);
        router.registerVerifier(1, IPQVerifier(makeAddr("eoa")));
    }

    function test_disableVerifier() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        vm.prank(routerOwner);
        router.disableVerifier(1);

        assertEq(address(router.verifiers(1)), address(0));
    }

    function test_registerKey() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        vm.prank(validatorAddr);
        bytes32 keyId = router.registerKey(1, hex"deadbeef");
        assertEq(keyId, keccak256(hex"deadbeef"));
    }

    function test_registerKey_revertIfNotValidator() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        vm.expectRevert(PQSignatureRouter.OnlyValidator.selector);
        router.registerKey(1, hex"deadbeef");
    }

    function test_registerKey_unknownScheme() public {
        vm.prank(validatorAddr);
        vm.expectRevert(abi.encodeWithSelector(PQSignatureRouter.UnknownScheme.selector, 99));
        router.registerKey(99, hex"deadbeef");
    }

    function test_verify() public {
        vm.prank(routerOwner);
        router.registerVerifier(1, IPQVerifier(address(mockVerifier)));

        // Valid sig (first byte > 0)
        assertTrue(router.verify(1, bytes32(0), hex"01", bytes32(0)));

        // Invalid sig (first byte = 0)
        assertFalse(router.verify(1, bytes32(0), hex"00", bytes32(0)));
    }

    function test_verify_unknownScheme() public {
        vm.expectRevert(abi.encodeWithSelector(PQSignatureRouter.UnknownScheme.selector, 99));
        router.verify(99, bytes32(0), hex"01", bytes32(0));
    }

    function test_setValidator_onlyOnce() public {
        // validator was already set in setUp, trying again should fail
        vm.prank(routerOwner);
        vm.expectRevert(PQSignatureRouter.ValidatorAlreadySet.selector);
        router.setValidator(makeAddr("anotherValidator"));
    }

    function test_setValidator_revertIfZeroAddress() public {
        // Deploy a fresh router to test zero address
        PQSignatureRouter freshRouter = new PQSignatureRouter(routerOwner);
        vm.prank(routerOwner);
        vm.expectRevert(PQSignatureRouter.InvalidVerifierAddress.selector);
        freshRouter.setValidator(address(0));
    }

    function test_transferOwnership_disabled() public {
        vm.prank(routerOwner);
        vm.expectRevert(PQSignatureRouter.TransferOwnershipDisabled.selector);
        router.transferOwnership(makeAddr("newOwner"));
    }
}
