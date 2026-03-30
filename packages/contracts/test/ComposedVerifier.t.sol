// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ComposedVerifier} from "../src/adapters/ComposedVerifier.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";

/// @notice Mock verifier that accepts any signature where first byte > 0
/// Accepts registerKey from any caller (since ComposedVerifier is the authorized caller)
contract MockVerifier is IPQVerifier {
    mapping(bytes32 keyId => bool registered) public keys;

    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        keyId = keccak256(publicKey);
        keys[keyId] = true;
    }

    function verify(
        bytes32,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        if (!keys[keyId]) return false;
        return signature.length > 0 && uint8(signature[0]) > 0;
    }
}

contract ComposedVerifierTest is Test {
    ComposedVerifier composed;
    MockVerifier verifierA;
    MockVerifier verifierB;
    address authorizedCaller;

    function setUp() public {
        authorizedCaller = makeAddr("router");
        verifierA = new MockVerifier();
        verifierB = new MockVerifier();
        // ComposedVerifier is authorized by the router; sub-adapters accept calls from ComposedVerifier
        composed =
            new ComposedVerifier(IPQVerifier(address(verifierA)), IPQVerifier(address(verifierB)), authorizedCaller);
    }

    function test_registerKey() public {
        bytes memory pkA = hex"aa";
        bytes memory pkB = hex"bb";
        bytes memory composedPk = abi.encode(pkA, pkB);

        vm.prank(authorizedCaller);
        bytes32 keyId = composed.registerKey(composedPk);
        assertTrue(keyId != bytes32(0));

        // Sub-keys should be registered
        assertTrue(verifierA.keys(keccak256(pkA)));
        assertTrue(verifierB.keys(keccak256(pkB)));
    }

    function test_registerKey_revertIfUnauthorized() public {
        bytes memory pkA = hex"aa";
        bytes memory pkB = hex"bb";
        bytes memory composedPk = abi.encode(pkA, pkB);

        vm.expectRevert(ComposedVerifier.OnlyAuthorizedCaller.selector);
        composed.registerKey(composedPk);
    }

    function test_verify_bothPass() public {
        bytes memory pkA = hex"aa";
        bytes memory pkB = hex"bb";
        vm.prank(authorizedCaller);
        bytes32 keyId = composed.registerKey(abi.encode(pkA, pkB));

        // Both sigs valid (first byte > 0)
        bytes memory sigA = hex"01";
        bytes memory sigB = hex"02";
        bytes memory composedSig = abi.encode(sigA, sigB);

        assertTrue(composed.verify(bytes32(0), composedSig, keyId));
    }

    function test_verify_oneFails() public {
        bytes memory pkA = hex"aa";
        bytes memory pkB = hex"bb";
        vm.prank(authorizedCaller);
        bytes32 keyId = composed.registerKey(abi.encode(pkA, pkB));

        // sigA valid, sigB invalid (first byte = 0)
        bytes memory sigA = hex"01";
        bytes memory sigB = hex"00";
        bytes memory composedSig = abi.encode(sigA, sigB);

        assertFalse(composed.verify(bytes32(0), composedSig, keyId));
    }

    function test_verify_bothFail() public {
        bytes memory pkA = hex"aa";
        bytes memory pkB = hex"bb";
        vm.prank(authorizedCaller);
        bytes32 keyId = composed.registerKey(abi.encode(pkA, pkB));

        bytes memory sigA = hex"00";
        bytes memory sigB = hex"00";
        bytes memory composedSig = abi.encode(sigA, sigB);

        assertFalse(composed.verify(bytes32(0), composedSig, keyId));
    }

    function test_verify_unknownKey() public {
        bytes memory sigA = hex"01";
        bytes memory sigB = hex"01";
        bytes memory composedSig = abi.encode(sigA, sigB);

        // Unknown keyId — sub-keys not registered
        assertFalse(composed.verify(bytes32(0), composedSig, bytes32(uint256(999))));
    }
}
