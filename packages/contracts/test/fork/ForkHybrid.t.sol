// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PQValidator} from "../../src/PQValidator.sol";
import {PQSignatureRouter} from "../../src/PQSignatureRouter.sol";
import {EthFalconAdapter} from "../../src/adapters/EthFalconAdapter.sol";
import {EcdsaVerifier} from "../../src/adapters/EcdsaVerifier.sol";
import {ComposedVerifier} from "../../src/adapters/ComposedVerifier.sol";
import {IPQVerifier} from "../../src/adapters/IPQVerifier.sol";
import {PackedUserOperation} from "@zerodev/kernel/interfaces/PackedUserOperation.sol";
import {ECDSA_ETHFALCON_SCHEME} from "../../src/libraries/SchemeIds.sol";
import {PQFixtures} from "../fixtures/PQFixtures.sol";
import {ZKNOX_ethfalcon} from "../../src/vendor/zknox/ZKNOX_ethfalcon.sol";

/// @notice Fork test: Hybrid ECDSA + ETHFALCON composed verification.
/// Deploys the full stack: ZKNOX_ethfalcon verifier, EcdsaVerifier, EthFalconAdapter,
/// ComposedVerifier, PQSignatureRouter, PQValidator. Verifies that a signature composed
/// of both ECDSA (vm.sign) and ETHFALCON (bedrock-wasm fixtures) passes on-chain.
/// Run with: forge test --match-contract ForkHybrid -vvv (requires SEPOLIA_RPC_URL)
contract ForkHybridTest is Test {
    PQSignatureRouter router;
    PQValidator validator;
    EcdsaVerifier ecdsaVerifier;
    EthFalconAdapter ethfalconAdapter;
    ComposedVerifier hybridVerifier;

    address deployer;
    address owner;
    uint256 ownerKey;
    address account;

    bool forkActive;

    function setUp() public {
        try vm.createSelectFork("sepolia") {
            forkActive = true;
        } catch {
            return;
        }

        deployer = makeAddr("deployer");
        (owner, ownerKey) = makeAddrAndKey("owner");
        account = makeAddr("account");

        vm.startPrank(deployer);

        // Deploy ZKNOX ETHFALCON verifier from source
        ZKNOX_ethfalcon zknoxVerifier = new ZKNOX_ethfalcon();

        // Deploy core contracts
        router = new PQSignatureRouter(deployer);
        validator = new PQValidator(router);
        router.setValidator(address(validator));

        // Deploy ECDSA verifier (no authorized caller needed — registerKey is pure)
        ecdsaVerifier = new EcdsaVerifier();

        // Deploy ETHFALCON adapter — authorized by the ComposedVerifier (not the router directly)
        // We need a two-step deploy: first ComposedVerifier, then adapters that authorize it.
        // But ComposedVerifier needs adapter addresses... chicken-and-egg.
        // Solution: EthFalconAdapter authorizes the ComposedVerifier address.
        // We predict the ComposedVerifier address using CREATE nonce.

        // Deploy EthFalconAdapter with router as authorized caller temporarily.
        // ComposedVerifier will call sub-adapters, so sub-adapters need to authorize the ComposedVerifier.
        // For EcdsaVerifier: registerKey is pure, no auth needed.
        // For EthFalconAdapter: registerKey requires AUTHORIZED_CALLER.

        // Deploy ComposedVerifier first to get its address, then deploy EthFalconAdapter authorizing it.
        // But ComposedVerifier takes adapter addresses in constructor...
        // The simplest approach: deploy EthFalconAdapter authorizing the router, and have the
        // ComposedVerifier call registerKey through the router path.

        // Actually, ComposedVerifier calls VERIFIER_A.registerKey and VERIFIER_B.registerKey directly.
        // So sub-adapters must authorize the ComposedVerifier address, not the router.
        // EcdsaVerifier has no auth check on registerKey (it's pure).
        // EthFalconAdapter checks AUTHORIZED_CALLER.

        // We can compute the address of ComposedVerifier before deploying it if we use CREATE.
        // deployer nonce: after deploying zknoxVerifier(0), router(1), validator(2), ecdsaVerifier(3)
        // next nonce = 4 → ethfalconAdapter, nonce 5 → hybridVerifier
        // But vm.getNonce is simpler:
        uint256 nextNonce = vm.getNonce(deployer);
        // nextNonce deployments: ethfalconAdapter, then hybridVerifier
        address predictedHybrid = vm.computeCreateAddress(deployer, nextNonce + 1);

        ethfalconAdapter = new EthFalconAdapter(address(zknoxVerifier), predictedHybrid);
        hybridVerifier = new ComposedVerifier(
            IPQVerifier(address(ecdsaVerifier)), IPQVerifier(address(ethfalconAdapter)), address(router)
        );
        require(address(hybridVerifier) == predictedHybrid, "address prediction mismatch");

        // Register hybrid scheme on router
        router.registerVerifier(ECDSA_ETHFALCON_SCHEME, IPQVerifier(address(hybridVerifier)));

        vm.stopPrank();

        // Install validator for the test account
        vm.prank(account);
        validator.onInstall{value: 0}(abi.encode(owner));
    }

    modifier onlyFork() {
        if (!forkActive) {
            vm.skip(true);
        }
        _;
    }

    /// @notice Register a hybrid ECDSA + ETHFALCON key pair
    function test_registerHybridKey() public onlyFork {
        bytes memory ecdsaPk = abi.encodePacked(owner); // 20-byte address
        bytes memory falconPk = PQFixtures.ethfalconPublicKey(); // 1024 bytes

        // Composed key = abi.encode(pkA, pkB)
        bytes memory composedKey = abi.encode(ecdsaPk, falconPk);

        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ECDSA_ETHFALCON_SCHEME, composedKey);

        bytes32 keyId = keccak256(composedKey);
        assertTrue(validator.isKeyApproved(account, ECDSA_ETHFALCON_SCHEME, keyId));
    }

    /// @notice Full hybrid verification: ECDSA + ETHFALCON both pass (ERC-1271)
    function test_verifyHybridSignature() public onlyFork {
        bytes memory ecdsaPk = abi.encodePacked(owner);
        bytes memory falconPk = PQFixtures.ethfalconPublicKey();
        bytes memory falconSig = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        // Register composed key
        bytes memory composedKey = abi.encode(ecdsaPk, falconPk);

        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ECDSA_ETHFALCON_SCHEME, composedKey);

        bytes32 keyId = keccak256(composedKey);

        // Create ECDSA signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, msgHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        // Compose: innerSig = abi.encode(ecdsaSig, falconSig)
        bytes memory innerSig = abi.encode(ecdsaSig, falconSig);

        // Wrap in PQ format: abi.encode(schemeId, innerSig, keyId)
        bytes memory encodedSig = abi.encode(uint256(ECDSA_ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), msgHash, encodedSig);
        assertEq(result, bytes4(0x1626ba7e), "Hybrid ECDSA+ETHFALCON signature should be valid");
    }

    /// @notice Hybrid verification via validateUserOp (ERC-4337)
    function test_validateUserOp_hybrid() public onlyFork {
        bytes memory ecdsaPk = abi.encodePacked(owner);
        bytes memory falconPk = PQFixtures.ethfalconPublicKey();
        bytes memory falconSig = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        bytes memory composedKey = abi.encode(ecdsaPk, falconPk);

        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ECDSA_ETHFALCON_SCHEME, composedKey);

        bytes32 keyId = keccak256(composedKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, msgHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory innerSig = abi.encode(ecdsaSig, falconSig);
        bytes memory encodedSig = abi.encode(uint256(ECDSA_ETHFALCON_SCHEME), innerSig, keyId);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = encodedSig;

        vm.prank(account);
        uint256 result = validator.validateUserOp(userOp, msgHash);
        assertEq(result, 0, "validateUserOp should return SIG_VALIDATION_SUCCESS");
    }

    /// @notice Hybrid fails if ECDSA part is wrong signer
    function test_hybridFails_wrongEcdsaSigner() public onlyFork {
        bytes memory ecdsaPk = abi.encodePacked(owner);
        bytes memory falconPk = PQFixtures.ethfalconPublicKey();
        bytes memory falconSig = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        bytes memory composedKey = abi.encode(ecdsaPk, falconPk);

        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ECDSA_ETHFALCON_SCHEME, composedKey);

        bytes32 keyId = keccak256(composedKey);

        // Sign with a different key
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, msgHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory innerSig = abi.encode(ecdsaSig, falconSig);
        bytes memory encodedSig = abi.encode(uint256(ECDSA_ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), msgHash, encodedSig);
        assertEq(result, bytes4(0xffffffff), "Wrong ECDSA signer should fail hybrid verification");
    }

    /// @notice Hybrid fails if ETHFALCON part has wrong hash
    function test_hybridFails_wrongFalconHash() public onlyFork {
        bytes memory ecdsaPk = abi.encodePacked(owner);
        bytes memory falconPk = PQFixtures.ethfalconPublicKey();
        bytes memory falconSig = PQFixtures.ethfalconSignature();

        bytes memory composedKey = abi.encode(ecdsaPk, falconPk);

        vm.prank(account);
        validator.setSchemeAllowed(ECDSA_ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ECDSA_ETHFALCON_SCHEME, composedKey);

        bytes32 keyId = keccak256(composedKey);

        // Use a different hash — ECDSA signs the wrong hash, Falcon sig was for the fixture hash
        bytes32 wrongHash = keccak256("wrong message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, wrongHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory innerSig = abi.encode(ecdsaSig, falconSig);
        bytes memory encodedSig = abi.encode(uint256(ECDSA_ETHFALCON_SCHEME), innerSig, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), wrongHash, encodedSig);
        assertEq(result, bytes4(0xffffffff), "Wrong hash should fail Falcon part of hybrid");
    }
}
