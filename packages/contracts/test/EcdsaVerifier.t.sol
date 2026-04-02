// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EcdsaVerifier} from "../src/adapters/EcdsaVerifier.sol";
import {ComposedVerifier} from "../src/adapters/ComposedVerifier.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";

/// @notice Mock PQ verifier for hybrid composition tests
contract MockPQVerifierForEcdsa is IPQVerifier {
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

contract EcdsaVerifierTest is Test {
    EcdsaVerifier ecdsaVerifier;
    address signer;
    uint256 signerKey;

    function setUp() public {
        ecdsaVerifier = new EcdsaVerifier();
        (signer, signerKey) = makeAddrAndKey("signer");
    }

    function test_registerKey_with20Bytes() public view {
        bytes memory pk = abi.encodePacked(signer);
        assertEq(pk.length, 20);
        bytes32 keyId = ecdsaVerifier.registerKey(pk);
        assertEq(address(uint160(uint256(keyId))), signer);
    }

    function test_registerKey_with32Bytes() public view {
        bytes memory pk = abi.encode(signer);
        assertEq(pk.length, 32);
        bytes32 keyId = ecdsaVerifier.registerKey(pk);
        assertEq(address(uint160(uint256(keyId))), signer);
    }

    function test_registerKey_revertIfInvalidLength() public {
        vm.expectRevert(EcdsaVerifier.InvalidPublicKeyLength.selector);
        ecdsaVerifier.registerKey(hex"deadbeef");
    }

    function test_verify_success() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 keyId = bytes32(uint256(uint160(signer)));
        assertTrue(ecdsaVerifier.verify(hash, signature, keyId));
    }

    function test_verify_wrongSigner() public {
        bytes32 hash = keccak256("test message");
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 keyId = bytes32(uint256(uint160(signer)));
        assertFalse(ecdsaVerifier.verify(hash, signature, keyId));
    }

    function test_registerKey_and_verify_compatible() public view {
        // registerKey and verify must produce/consume compatible keyIds
        bytes memory pk = abi.encodePacked(signer);
        bytes32 keyId = ecdsaVerifier.registerKey(pk);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(ecdsaVerifier.verify(hash, signature, keyId));
    }

    function test_verify_malformedSignature_returnsFalse() public view {
        bytes32 hash = keccak256("test message");
        // Completely invalid 65-byte signature (not a valid ECDSA recovery)
        bytes memory malformed = new bytes(65);
        bytes32 keyId = bytes32(uint256(uint160(signer)));
        assertFalse(ecdsaVerifier.verify(hash, malformed, keyId));
    }

    function test_verify_emptySignature_returnsFalse() public view {
        bytes32 hash = keccak256("test message");
        bytes memory empty = "";
        bytes32 keyId = bytes32(uint256(uint160(signer)));
        assertFalse(ecdsaVerifier.verify(hash, empty, keyId));
    }

    function test_composedVerifier_ecdsaPlusPQ() public {
        MockPQVerifierForEcdsa mockPq = new MockPQVerifierForEcdsa();
        address authorizedCaller = makeAddr("router");

        ComposedVerifier composed =
            new ComposedVerifier(IPQVerifier(address(ecdsaVerifier)), IPQVerifier(address(mockPq)), authorizedCaller);

        // Register composed key: ECDSA address + PQ public key
        bytes memory ecdsaPk = abi.encodePacked(signer);
        bytes memory pqPk = hex"aabbccdd";
        bytes memory composedPk = abi.encode(ecdsaPk, pqPk);

        vm.prank(authorizedCaller);
        bytes32 composedKeyId = composed.registerKey(composedPk);
        assertTrue(composedKeyId != bytes32(0));

        // Sign with ECDSA + valid PQ sig
        bytes32 hash = keccak256("hybrid test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory pqSig = hex"01ff"; // valid mock PQ sig (first byte > 0)

        bytes memory composedSig = abi.encode(ecdsaSig, pqSig);
        assertTrue(composed.verify(hash, composedSig, composedKeyId));
    }

    function test_composedVerifier_ecdsaFails() public {
        MockPQVerifierForEcdsa mockPq = new MockPQVerifierForEcdsa();
        address authorizedCaller = makeAddr("router");

        ComposedVerifier composed =
            new ComposedVerifier(IPQVerifier(address(ecdsaVerifier)), IPQVerifier(address(mockPq)), authorizedCaller);

        bytes memory ecdsaPk = abi.encodePacked(signer);
        bytes memory pqPk = hex"aabbccdd";

        vm.prank(authorizedCaller);
        bytes32 composedKeyId = composed.registerKey(abi.encode(ecdsaPk, pqPk));

        // Sign with wrong ECDSA key + valid PQ sig
        bytes32 hash = keccak256("hybrid test");
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory pqSig = hex"01ff";

        bytes memory composedSig = abi.encode(ecdsaSig, pqSig);
        assertFalse(composed.verify(hash, composedSig, composedKeyId));
    }
}
