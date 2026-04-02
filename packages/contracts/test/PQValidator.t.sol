// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PQValidator} from "../src/PQValidator.sol";
import {PQSignatureRouter} from "../src/PQSignatureRouter.sol";
import {EcdsaVerifier} from "../src/adapters/EcdsaVerifier.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";
import {IPQValidator} from "../src/interfaces/IPQValidator.sol";
import {IModule} from "@zerodev/kernel/interfaces/IERC7579Modules.sol";
import {PackedUserOperation} from "@zerodev/kernel/interfaces/PackedUserOperation.sol";
import {ECDSA_SCHEME, ETHFALCON_SCHEME} from "../src/libraries/SchemeIds.sol";

/// @notice Mock PQ verifier for testing the standard (non-ECDSA) verification path.
/// Accepts signatures where first byte > 0. Stores registered keys.
contract MockPQVerifierForValidator is IPQVerifier {
    mapping(bytes32 keyId => bool registered) public keys;
    address public immutable AUTHORIZED_CALLER;

    constructor(
        address authorizedCaller_
    ) {
        AUTHORIZED_CALLER = authorizedCaller_;
    }

    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        require(msg.sender == AUTHORIZED_CALLER, "unauthorized");
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

contract PQValidatorTest is Test {
    PQSignatureRouter router;
    PQValidator validator;
    EcdsaVerifier ecdsaVerifier;
    MockPQVerifierForValidator mockPqVerifier;

    address owner;
    uint256 ownerKey;
    address account;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        account = makeAddr("account");

        router = new PQSignatureRouter(address(this));
        ecdsaVerifier = new EcdsaVerifier();
        validator = new PQValidator(router);

        // Authorize the validator to call registerKey on the router
        router.setValidator(address(validator));

        // Register a mock PQ verifier for ETHFALCON scheme
        mockPqVerifier = new MockPQVerifierForValidator(address(router));
        router.registerVerifier(ETHFALCON_SCHEME, IPQVerifier(address(mockPqVerifier)));
    }

    function test_onInstall() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        assertEq(validator.getOwner(account), owner);
        assertTrue(validator.isInitialized(account));
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));
    }

    function test_onInstall_revertIfAlreadyInitialized() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(IModule.AlreadyInitialized.selector, account));
        validator.onInstall{value: 0}(abi.encode(owner));
    }

    function test_onInstall_revertIfZeroAddress() public {
        vm.prank(account);
        vm.expectRevert(IPQValidator.InvalidOwner.selector);
        validator.onInstall{value: 0}(abi.encode(address(0)));
    }

    function test_onUninstall() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.onUninstall{value: 0}("");

        assertEq(validator.getOwner(account), address(0));
        assertFalse(validator.isInitialized(account));
    }

    function test_onUninstall_invalidatesSchemeSettings() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Enable a PQ scheme
        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);
        assertTrue(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));

        // Uninstall
        vm.prank(account);
        validator.onUninstall{value: 0}("");

        // After uninstall, the old scheme setting is unreachable
        assertFalse(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));
    }

    function test_reinstall_invalidatesPriorState() public {
        // Install
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Enable a PQ scheme
        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);
        assertTrue(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));

        // Uninstall
        vm.prank(account);
        validator.onUninstall{value: 0}("");

        // Reinstall with new owner
        address newOwner = makeAddr("newOwner");
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(newOwner));

        // New owner is set
        assertEq(validator.getOwner(account), newOwner);
        // ECDSA is re-enabled
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));
        // Previously enabled PQ scheme is NOT carried over (nonce invalidation)
        assertFalse(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));
    }

    function test_isModuleType() public view {
        assertTrue(validator.isModuleType(1)); // VALIDATOR
        assertFalse(validator.isModuleType(2)); // EXECUTOR
    }

    function test_ecdsaValidation() public {
        // Install validator for account
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Sign a hash
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate via ERC-1271 (65-byte ECDSA fast path)
        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_ecdsaValidation_wrongSigner() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        bytes32 hash = keccak256("test message");
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_ecdsaValidation_notInitialized() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_ecdsaValidation_malformedSignature() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        bytes32 hash = keccak256("test message");

        // Too short for ECDSA fast path, too short for ABI-decode
        bytes memory shortSig = hex"deadbeef";
        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, shortSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_ecdsaValidation_reinstallInvalidatesOldSig() public {
        // Install
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Disable ECDSA
        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_SCHEME, false);

        // Uninstall
        vm.prank(account);
        validator.onUninstall{value: 0}("");

        // Reinstall
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // ECDSA should work again (fresh nonce, fresh scheme allowance)
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_schemeManagement() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Disable ECDSA
        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_SCHEME, false);
        assertFalse(validator.isSchemeAllowed(account, ECDSA_SCHEME));

        // ECDSA sig should now fail
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, signature);
        assertEq(result, bytes4(0xffffffff));

        // Re-enable
        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_SCHEME, true);
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));
    }

    function test_disableEcdsa_revertIfEcdsaScheme() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        vm.expectRevert(IPQValidator.EcdsaSchemeNotAllowed.selector);
        validator.disableEcdsa(ECDSA_SCHEME, hex"deadbeef");
    }

    function test_disableEcdsa_revertIfNotInitialized() public {
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(IModule.NotInitialized.selector, account));
        validator.disableEcdsa(ETHFALCON_SCHEME, hex"deadbeef");
    }

    // ========== validateUserOp ==========

    function test_validateUserOp_ecdsaSuccess() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        bytes32 userOpHash = keccak256("userop");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = signature;

        vm.prank(account);
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // SIG_VALIDATION_SUCCESS
    }

    function test_validateUserOp_ecdsaFailure() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        bytes32 userOpHash = keccak256("userop");
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = signature;

        vm.prank(account);
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    // ========== Standard (ABI-encoded) PQ verification path ==========

    function test_pqVerification_standardPath() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Enable PQ scheme and register a key
        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory publicKey = hex"aabbccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);

        // Valid PQ signature (first byte > 0)
        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), encodedSig);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_pqVerification_invalidSignature() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory publicKey = hex"aabbccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);

        // Invalid PQ signature (first byte = 0)
        bytes memory innerSig = hex"00ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), encodedSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_pqVerification_schemeNotAllowed() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // Register key but do NOT enable the scheme
        bytes memory publicKey = hex"aabbccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), encodedSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_pqVerification_keyNotApproved() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        // Use a keyId that was never registered
        bytes32 fakeKeyId = keccak256("unregistered");
        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, fakeKeyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), encodedSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_pqVerification_revokedKey() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory publicKey = hex"aabbccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);

        // Revoke the key
        vm.prank(account);
        validator.revokeKey(ETHFALCON_SCHEME, keyId);

        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), encodedSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_pqVerification_validateUserOp() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory publicKey = hex"aabbccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = encodedSig;

        vm.prank(account);
        uint256 result = validator.validateUserOp(userOp, keccak256("userop"));
        assertEq(result, 0); // SIG_VALIDATION_SUCCESS
    }

    // ========== disableEcdsa happy path ==========

    function test_disableEcdsa_success() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // ECDSA should work before disable
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));

        bytes memory pqPublicKey = hex"aabbccdd";

        vm.prank(account);
        validator.disableEcdsa(ETHFALCON_SCHEME, pqPublicKey);

        // ECDSA should be disabled
        assertFalse(validator.isSchemeAllowed(account, ECDSA_SCHEME));
        // PQ scheme should be enabled
        assertTrue(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));
        // PQ key should be approved
        bytes32 keyId = keccak256(pqPublicKey);
        assertTrue(validator.isKeyApproved(account, ETHFALCON_SCHEME, keyId));

        // ECDSA signature should now fail
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), hash, ecdsaSig);
        assertEq(result, bytes4(0xffffffff));

        // PQ signature should work
        bytes memory innerSig = hex"01ff";
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        result = validator.isValidSignatureWithSender(address(0), hash, encodedSig);
        assertEq(result, bytes4(0x1626ba7e));
    }

    // ========== 65-byte non-ECDSA signature edge case ==========

    function test_65byteSig_alwaysRoutedToEcdsa() public {
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        // A random 65-byte payload that isn't a valid ECDSA sig for owner
        bytes memory fakeSig = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            fakeSig[i] = bytes1(uint8(i + 1));
        }

        // Even though this could hypothetically be a PQ sig, it's routed to ECDSA fast path
        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), keccak256("msg"), fakeSig);
        assertEq(result, bytes4(0xffffffff));
    }

    // ========== EIP-7201 storage slot verification ==========

    function test_storageSlot_matchesEIP7201Derivation() public pure {
        bytes32 derived =
            keccak256(abi.encode(uint256(keccak256("pqwallet.validator.storage")) - 1)) & ~bytes32(uint256(0xff));
        // Must match the hardcoded STORAGE_SLOT in PQStorageLib
        assertEq(derived, 0xb9c87b537fc6962e00fd83451d672e31943c36cc3c6386576bdded54b09ae800);
    }
}
