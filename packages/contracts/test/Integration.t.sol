// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PQValidator} from "../src/PQValidator.sol";
import {PQSignatureRouter} from "../src/PQSignatureRouter.sol";
import {EcdsaVerifier} from "../src/adapters/EcdsaVerifier.sol";
import {ComposedVerifier} from "../src/adapters/ComposedVerifier.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";
import {ISigVerifier} from "../src/interfaces/IZKNOX.sol";
import {PackedUserOperation} from "@zerodev/kernel/interfaces/PackedUserOperation.sol";
import {ECDSA_SCHEME, ETHFALCON_SCHEME} from "../src/libraries/SchemeIds.sol";

/// @notice Mock ZKNOX verifier for integration testing
contract MockZKNOXVerifier is ISigVerifier {
    mapping(address pkContract => bytes publicKey) public storedKeys;
    uint256 private _nonce;

    function setKey(
        bytes calldata key
    ) external returns (bytes memory) {
        _nonce++;
        address pkContract = address(uint160(uint256(keccak256(abi.encodePacked(key, _nonce)))));
        storedKeys[pkContract] = key;
        return abi.encodePacked(pkContract);
    }

    function verify(
        bytes calldata pk,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // Adapters pass abi.encodePacked(pkContract) which is 20 bytes
        address pkContract = address(bytes20(pk[0:20]));
        if (storedKeys[pkContract].length == 0) return bytes4(0xffffffff);
        if (signature.length == 0 || uint8(signature[0]) == 0) return bytes4(0xffffffff);
        if (hash == bytes32(0)) return bytes4(0xffffffff);
        return ISigVerifier.verify.selector;
    }
}

/// @notice Minimal PQ adapter wrapping the mock ZKNOX verifier (same structure as EthFalconAdapter)
contract MockPQAdapter is IPQVerifier {
    ISigVerifier public immutable VERIFIER;
    address public immutable AUTHORIZED_CALLER;
    mapping(bytes32 keyId => address pkContract) private _keys;

    error OnlyAuthorizedCaller();
    error KeyAlreadyRegistered(bytes32 keyId);
    error KeyDeploymentFailed();

    constructor(
        address verifier_,
        address authorizedCaller_
    ) {
        VERIFIER = ISigVerifier(verifier_);
        AUTHORIZED_CALLER = authorizedCaller_;
    }

    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        if (msg.sender != AUTHORIZED_CALLER) revert OnlyAuthorizedCaller();
        keyId = keccak256(publicKey);
        if (_keys[keyId] != address(0)) revert KeyAlreadyRegistered(keyId);
        _keys[keyId] = address(1);
        bytes memory result = VERIFIER.setKey(publicKey);
        if (result.length < 20) revert KeyDeploymentFailed();
        address pkContract = address(bytes20(result));
        if (pkContract == address(0) || pkContract == address(1)) revert KeyDeploymentFailed();
        _keys[keyId] = pkContract;
    }

    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        address pkContract = _keys[keyId];
        if (pkContract == address(0) || pkContract == address(1)) return false;
        bytes4 result = VERIFIER.verify(abi.encodePacked(pkContract), hash, signature);
        return result == ISigVerifier.verify.selector;
    }
}

/// @notice End-to-end integration test covering the full deployment and usage lifecycle.
contract IntegrationTest is Test {
    // Contracts
    PQSignatureRouter router;
    PQValidator validator;
    EcdsaVerifier ecdsaVerifier;
    MockZKNOXVerifier mockZknox;
    MockPQAdapter pqAdapter;
    ComposedVerifier hybridVerifier;

    // Accounts
    address deployer;
    address owner;
    uint256 ownerKey;
    address account;

    function setUp() public {
        deployer = makeAddr("deployer");
        (owner, ownerKey) = makeAddrAndKey("owner");
        account = makeAddr("account");

        // === Step 1: Deploy infrastructure (deployer is admin) ===
        vm.startPrank(deployer);

        router = new PQSignatureRouter(deployer);
        validator = new PQValidator(router);
        router.setValidator(address(validator));

        // === Step 2: Deploy verifier adapters ===
        ecdsaVerifier = new EcdsaVerifier();
        mockZknox = new MockZKNOXVerifier();
        pqAdapter = new MockPQAdapter(address(mockZknox), address(router));

        // === Step 3: Deploy hybrid composed verifier ===
        // ComposedVerifier's sub-adapters must authorize ComposedVerifier as caller.
        // For this test, the MockPQAdapter authorizes the router, not the ComposedVerifier.
        // So we use a separate MockPQAdapter that authorizes the ComposedVerifier.

        // First, we need the ComposedVerifier address — but it's not deployed yet.
        // Solution: deploy ComposedVerifier, then deploy a PQ adapter that authorizes it.
        // We use a two-step approach with a predictable address or just wire it manually.

        // For the hybrid test, we'll register the individual adapters and test composition separately.
        // Register scheme verifiers on the router
        router.registerVerifier(ETHFALCON_SCHEME, IPQVerifier(address(pqAdapter)));

        vm.stopPrank();
    }

    /// @notice Full lifecycle: install → ECDSA sign → register PQ key → PQ sign → disable ECDSA
    function test_fullLifecycle() public {
        // === Phase 1: Account installation with ECDSA ===
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        assertTrue(validator.isInitialized(account));
        assertEq(validator.getOwner(account), owner);
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));

        // === Phase 2: ECDSA signature verification (ERC-4337 validateUserOp) ===
        bytes32 userOpHash = keccak256("user operation 1");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, userOpHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = ecdsaSig;

        vm.prank(account);
        assertEq(validator.validateUserOp(userOp, userOpHash), 0); // SUCCESS

        // === Phase 3: ECDSA signature verification (ERC-1271) ===
        bytes32 msgHash = keccak256("sign this message");
        (v, r, s) = vm.sign(ownerKey, msgHash);
        ecdsaSig = abi.encodePacked(r, s, v);

        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), msgHash, ecdsaSig), bytes4(0x1626ba7e));

        // === Phase 4: Register PQ key and enable PQ scheme ===
        bytes memory pqPublicKey = hex"deadbeefcafebabe0102030405060708";

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, pqPublicKey);

        bytes32 pqKeyId = keccak256(pqPublicKey);
        assertTrue(validator.isKeyApproved(account, ETHFALCON_SCHEME, pqKeyId));
        assertTrue(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));

        // === Phase 5: PQ signature verification ===
        bytes32 pqMsgHash = keccak256("quantum-secure message");
        bytes memory pqInnerSig = hex"01aabbccdd"; // valid mock sig (first byte > 0)
        bytes memory pqEncodedSig = abi.encode(uint256(ETHFALCON_SCHEME), pqInnerSig, pqKeyId);

        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), pqMsgHash, pqEncodedSig), bytes4(0x1626ba7e));

        // PQ via validateUserOp
        userOp.signature = pqEncodedSig;
        vm.prank(account);
        assertEq(validator.validateUserOp(userOp, pqMsgHash), 0); // SUCCESS

        // === Phase 6: Both ECDSA and PQ work simultaneously ===
        bytes32 hash2 = keccak256("another message");
        (v, r, s) = vm.sign(ownerKey, hash2);
        ecdsaSig = abi.encodePacked(r, s, v);

        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash2, ecdsaSig), bytes4(0x1626ba7e));

        // === Phase 7: Disable ECDSA (quantum migration) ===
        // Register a new PQ key and disable ECDSA atomically
        bytes memory newPqKey = hex"1111222233334444";

        vm.prank(account);
        validator.disableEcdsa(ETHFALCON_SCHEME, newPqKey);

        assertFalse(validator.isSchemeAllowed(account, ECDSA_SCHEME));
        assertTrue(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));

        // ECDSA should now fail
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash2, ecdsaSig), bytes4(0xffffffff));

        // PQ should still work (with original key)
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), pqMsgHash, pqEncodedSig), bytes4(0x1626ba7e));

        // PQ should work with new key too
        bytes32 newPqKeyId = keccak256(newPqKey);
        bytes memory newPqSig = hex"01eeff";
        bytes memory newPqEncodedSig = abi.encode(uint256(ETHFALCON_SCHEME), newPqSig, newPqKeyId);
        bytes32 hash3 = keccak256("post-quantum era");

        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash3, newPqEncodedSig), bytes4(0x1626ba7e));
    }

    /// @notice Uninstall and reinstall: all prior state is invalidated
    function test_uninstallReinstallCleansState() public {
        // Install and set up PQ key
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory pqKey = hex"aabb";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, pqKey);
        bytes32 pqKeyId = keccak256(pqKey);

        assertTrue(validator.isKeyApproved(account, ETHFALCON_SCHEME, pqKeyId));

        // Uninstall
        vm.prank(account);
        validator.onUninstall{value: 0}("");

        // All state should be gone
        assertFalse(validator.isInitialized(account));
        assertEq(validator.getOwner(account), address(0));
        assertFalse(validator.isSchemeAllowed(account, ECDSA_SCHEME));
        assertFalse(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));
        assertFalse(validator.isKeyApproved(account, ETHFALCON_SCHEME, pqKeyId));

        // Reinstall with new owner
        address newOwner = makeAddr("newOwner");
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(newOwner));

        // Fresh state
        assertTrue(validator.isInitialized(account));
        assertEq(validator.getOwner(account), newOwner);
        assertTrue(validator.isSchemeAllowed(account, ECDSA_SCHEME));
        // Old PQ state not carried over
        assertFalse(validator.isSchemeAllowed(account, ETHFALCON_SCHEME));
        assertFalse(validator.isKeyApproved(account, ETHFALCON_SCHEME, pqKeyId));
    }

    /// @notice Router admin can disable a scheme — existing signatures stop working
    function test_routerDisableScheme() public {
        // Setup: account with working PQ
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        bytes memory pqKey = hex"ccdd";
        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, pqKey);

        bytes32 pqKeyId = keccak256(pqKey);
        bytes memory pqSig = hex"01ff";
        bytes memory encoded = abi.encode(uint256(ETHFALCON_SCHEME), pqSig, pqKeyId);
        bytes32 hash = keccak256("test");

        // Works before disable
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, encoded), bytes4(0x1626ba7e));

        // Router owner disables the scheme
        vm.prank(deployer);
        router.disableVerifier(ETHFALCON_SCHEME);

        // Now fails (router.verify reverts with UnknownScheme, caught by try/catch)
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, encoded), bytes4(0xffffffff));

        // ECDSA still works (unaffected by PQ scheme disable)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, ecdsaSig), bytes4(0x1626ba7e));
    }

    /// @notice Multiple accounts are fully isolated
    function test_multipleAccountsIsolated() public {
        address account2 = makeAddr("account2");
        (address owner2, uint256 owner2Key) = makeAddrAndKey("owner2");

        // Install for both accounts
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));

        vm.prank(account2);
        validator.onInstall{value: 0}(abi.encode(owner2));

        // Each account's ECDSA only works for its own owner
        bytes32 hash = keccak256("shared message");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        bytes memory sig1 = abi.encodePacked(r, s, v);

        (v, r, s) = vm.sign(owner2Key, hash);
        bytes memory sig2 = abi.encodePacked(r, s, v);

        // owner1's sig works for account1
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, sig1), bytes4(0x1626ba7e));

        // owner1's sig fails for account2
        vm.prank(account2);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, sig1), bytes4(0xffffffff));

        // owner2's sig works for account2
        vm.prank(account2);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, sig2), bytes4(0x1626ba7e));

        // owner2's sig fails for account1
        vm.prank(account);
        assertEq(validator.isValidSignatureWithSender(address(0), hash, sig2), bytes4(0xffffffff));
    }
}
