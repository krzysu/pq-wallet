// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ISigVerifier} from "../../src/interfaces/IZKNOX.sol";
import {MldsaFixtures} from "../fixtures/MldsaFixtures.sol";

/// @notice Fork test: Standard MLDSA verification against deployed Kohaku verifier on Sepolia.
/// Tests setKey + verify with real noble/post-quantum ML-DSA-44 signatures.
/// Uses the Kohaku deployment at 0x1C789898... (standard MLDSA, SHAKE-based, NOT MLDSAETH).
/// Run with: forge test --match-contract ForkMldsa -vvv (requires SEPOLIA_RPC_URL)
contract ForkMldsaTest is Test {
    /// @notice ZKNOX MLDSA ISigVerifier on Sepolia (from Kohaku deployments)
    address constant ZKNOX_MLDSA_SEPOLIA = 0x1C789898a6141Fd5F840334Bb2E289fB188a3cb6;

    ISigVerifier zknox;
    bool forkActive;

    function setUp() public {
        try vm.createSelectFork("sepolia") {
            forkActive = true;
        } catch {
            return;
        }
        zknox = ISigVerifier(ZKNOX_MLDSA_SEPOLIA);
    }

    modifier onlyFork() {
        if (!forkActive) {
            vm.skip(true);
        }
        _;
    }

    /// @notice Test setKey stores key and returns a valid SSTORE2 pointer
    function test_mldsaSetKey() public onlyFork {
        bytes memory expandedKey = MldsaFixtures.mldsaExpandedKey();
        console.log("Expanded key length:", expandedKey.length);

        bytes memory result = zknox.setKey(expandedKey);
        console.log("setKey result length:", result.length);

        assertTrue(result.length >= 20, "setKey should return PKContract address");

        address pkContract;
        if (result.length >= 32) {
            pkContract = abi.decode(result, (address));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            pkContract = address(bytes20(result));
        }
        console.log("pkContract:", pkContract);
        assertTrue(pkContract != address(0), "pkContract should not be zero");
    }

    /// @notice Full end-to-end: setKey + verify with real MLDSA signature
    function test_mldsaVerify() public onlyFork {
        bytes memory expandedKey = MldsaFixtures.mldsaExpandedKey();
        bytes memory signature = MldsaFixtures.mldsaSignature();
        bytes32 msgHash = MldsaFixtures.messageHash();

        console.log("Signature length:", signature.length);

        // Store key
        bytes memory result = zknox.setKey(expandedKey);
        address pkContract;
        if (result.length >= 32) {
            pkContract = abi.decode(result, (address));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            pkContract = address(bytes20(result));
        }
        console.log("pkContract:", pkContract);

        // Verify
        bytes4 verifyResult = zknox.verify(abi.encodePacked(pkContract), msgHash, signature);
        console.log("verify result:");
        console.logBytes4(verifyResult);

        assertEq(verifyResult, ISigVerifier.verify.selector, "MLDSA signature should be valid");
    }

    /// @notice Wrong hash should fail
    function test_mldsaVerify_wrongHash() public onlyFork {
        bytes memory expandedKey = MldsaFixtures.mldsaExpandedKey();
        bytes memory signature = MldsaFixtures.mldsaSignature();

        bytes memory result = zknox.setKey(expandedKey);
        address pkContract;
        if (result.length >= 32) {
            pkContract = abi.decode(result, (address));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            pkContract = address(bytes20(result));
        }

        bytes4 verifyResult = zknox.verify(abi.encodePacked(pkContract), keccak256("wrong"), signature);
        assertEq(verifyResult, bytes4(0xffffffff), "Wrong hash should fail");
    }
}
