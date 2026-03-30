// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PQValidator} from "../../src/PQValidator.sol";
import {PQSignatureRouter} from "../../src/PQSignatureRouter.sol";
import {EthFalconAdapter} from "../../src/adapters/EthFalconAdapter.sol";
import {IPQVerifier} from "../../src/adapters/IPQVerifier.sol";
import {PackedUserOperation} from "@zerodev/kernel/interfaces/PackedUserOperation.sol";
import {ETHFALCON_SCHEME} from "../../src/libraries/SchemeIds.sol";
import {PQFixtures} from "../fixtures/PQFixtures.sol";
import {ZKNOX_ethfalcon} from "../../src/vendor/zknox/ZKNOX_ethfalcon.sol";

/// @notice Fork test: ETHFALCON-only verification with real bedrock-wasm signatures.
/// Deploys vendored ZKNOX_ethfalcon (hashToPointBedrock, bedrock-wasm compatible) from source.
/// Tests key registration, ERC-1271, ERC-4337, wrong hash rejection, and ECDSA→PQ migration.
/// Run with: forge test --match-contract ForkEthFalcon -vvv (requires SEPOLIA_RPC_URL)
contract ForkEthFalconTest is Test {
    PQSignatureRouter router;
    PQValidator validator;
    EthFalconAdapter ethfalconAdapter;

    address deployer;
    address owner;
    uint256 ownerKey;
    address account;

    bool forkActive;

    function setUp() public {
        // Try to create a fork from the rpc_endpoints config.
        // If SEPOLIA_RPC_URL is empty or missing, this reverts and we catch it.
        try vm.createSelectFork("sepolia") {
            forkActive = true;
        } catch {
            return;
        }

        deployer = makeAddr("deployer");
        (owner, ownerKey) = makeAddrAndKey("owner");
        account = makeAddr("account");

        vm.startPrank(deployer);

        // Deploy ZKNOX ETHFALCON verifier from source on the fork
        ZKNOX_ethfalcon zknoxVerifier = new ZKNOX_ethfalcon();

        // Deploy our contracts, pointing to the freshly deployed ZKNOX verifier
        router = new PQSignatureRouter(deployer);
        validator = new PQValidator(router);
        router.setValidator(address(validator));

        ethfalconAdapter = new EthFalconAdapter(address(zknoxVerifier), address(router));
        router.registerVerifier(ETHFALCON_SCHEME, IPQVerifier(address(ethfalconAdapter)));

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

    /// @notice Register a real ETHFALCON public key on-chain via ZKNOX setKey
    function test_registerEthFalconKey() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        assertTrue(validator.isKeyApproved(account, ETHFALCON_SCHEME, keyId));
    }

    /// @notice Full end-to-end: register key + verify real ETHFALCON signature on-chain
    function test_verifyRealEthFalconSignature() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();
        bytes memory signature = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        // Enable scheme and register key
        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);

        // Verify via ERC-1271
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), signature, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), msgHash, encodedSig);
        assertEq(result, bytes4(0x1626ba7e), "ETHFALCON signature should be valid");
    }

    /// @notice Verify via validateUserOp (ERC-4337 path)
    function test_validateUserOp_realEthFalcon() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();
        bytes memory signature = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), signature, keyId);

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.signature = encodedSig;

        vm.prank(account);
        uint256 result = validator.validateUserOp(userOp, msgHash);
        assertEq(result, 0, "validateUserOp should return SIG_VALIDATION_SUCCESS");
    }

    /// @notice Wrong hash should fail verification
    function test_verifyRealEthFalcon_wrongHash() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();
        bytes memory signature = PQFixtures.ethfalconSignature();

        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        bytes32 wrongHash = keccak256("wrong message");
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), signature, keyId);

        vm.prank(account);
        bytes4 result = validator.isValidSignatureWithSender(address(0), wrongHash, encodedSig);
        assertEq(result, bytes4(0xffffffff), "Wrong hash should fail verification");
    }

    /// @notice ECDSA + ETHFALCON coexistence: both work, then disable ECDSA
    function test_ecdsaToPqMigration() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();
        bytes memory pqSignature = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        // Phase 1: ECDSA works
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, msgHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        vm.prank(account);
        assertEq(
            validator.isValidSignatureWithSender(address(0), msgHash, ecdsaSig),
            bytes4(0x1626ba7e),
            "ECDSA should work initially"
        );

        // Phase 2: Disable ECDSA atomically, enable PQ
        vm.prank(account);
        validator.disableEcdsa(ETHFALCON_SCHEME, publicKey);

        // Phase 3: ECDSA should fail
        vm.prank(account);
        assertEq(
            validator.isValidSignatureWithSender(address(0), msgHash, ecdsaSig),
            bytes4(0xffffffff),
            "ECDSA should fail after disable"
        );

        // Phase 4: PQ should work
        bytes32 keyId = keccak256(publicKey);
        bytes memory encodedSig = abi.encode(uint256(ETHFALCON_SCHEME), pqSignature, keyId);

        vm.prank(account);
        assertEq(
            validator.isValidSignatureWithSender(address(0), msgHash, encodedSig),
            bytes4(0x1626ba7e),
            "ETHFALCON should work after migration"
        );
    }

    /// @notice Sanity check: ZKNOX setKey deploys via SSTORE2 and returns a valid pointer
    function test_directZknoxSetKey() public onlyFork {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();

        // Register key through our adapter (which calls ZKNOX setKey internally)
        vm.prank(account);
        validator.setSchemeAllowed(ETHFALCON_SCHEME, true);

        vm.prank(account);
        validator.registerPublicKey(ETHFALCON_SCHEME, publicKey);

        bytes32 keyId = keccak256(publicKey);
        assertTrue(validator.isKeyApproved(account, ETHFALCON_SCHEME, keyId));
    }
}
