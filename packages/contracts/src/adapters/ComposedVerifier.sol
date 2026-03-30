// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPQVerifier} from "./IPQVerifier.sol";

/// @title ComposedVerifier
/// @notice Combines any two IPQVerifier adapters. Both must pass for verification to succeed.
/// Deploy one instance per combination (e.g., ECDSA + ETHFALCON, ECDSA + MLDSA).
///
/// ACCESS CONTROL: registerKey is restricted to the AUTHORIZED_CALLER (typically the router).
/// Sub-adapter registerKey calls originate from this contract, so sub-adapters must authorize
/// this ComposedVerifier address as their caller.
contract ComposedVerifier is IPQVerifier {
    IPQVerifier public immutable VERIFIER_A;
    IPQVerifier public immutable VERIFIER_B;
    address public immutable AUTHORIZED_CALLER;

    /// @notice Maps composed keyId → (keyIdA, keyIdB)
    mapping(bytes32 keyId => bytes32[2] subKeys) private _composedKeys;

    error OnlyAuthorizedCaller();
    error InvalidAddress();

    constructor(
        IPQVerifier verifierA_,
        IPQVerifier verifierB_,
        address authorizedCaller_
    ) {
        if (address(verifierA_) == address(0)) revert InvalidAddress();
        if (address(verifierB_) == address(0)) revert InvalidAddress();
        if (authorizedCaller_ == address(0)) revert InvalidAddress();
        VERIFIER_A = verifierA_;
        VERIFIER_B = verifierB_;
        AUTHORIZED_CALLER = authorizedCaller_;
    }

    /// @notice Register a composed key. publicKey = abi.encode(pkA, pkB)
    /// @param publicKey ABI-encoded pair of public keys for VERIFIER_A and VERIFIER_B
    /// @return keyId The composed key identifier
    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        if (msg.sender != AUTHORIZED_CALLER) revert OnlyAuthorizedCaller();

        (bytes memory pkA, bytes memory pkB) = abi.decode(publicKey, (bytes, bytes));
        // slither-disable-next-line reentrancy-benign
        bytes32 keyIdA = VERIFIER_A.registerKey(pkA);
        bytes32 keyIdB = VERIFIER_B.registerKey(pkB);
        keyId = keccak256(abi.encodePacked(keyIdA, keyIdB));
        _composedKeys[keyId] = [keyIdA, keyIdB];
    }

    /// @notice Verify a composed signature. Both sub-verifiers must pass.
    /// signature = abi.encode(sigA, sigB)
    /// @param hash The message hash
    /// @param signature ABI-encoded pair of signatures
    /// @param keyId The composed key identifier (from registerKey)
    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        bytes32[2] storage subKeys = _composedKeys[keyId];
        bytes32 keyIdA = subKeys[0];
        bytes32 keyIdB = subKeys[1];

        (bytes memory sigA, bytes memory sigB) = abi.decode(signature, (bytes, bytes));

        // Both external calls execute regardless of results (no short-circuit on the calls).
        // Only the final boolean && short-circuits, which is negligible gas difference.
        bool resultA = VERIFIER_A.verify(hash, sigA, keyIdA);
        bool resultB = VERIFIER_B.verify(hash, sigB, keyIdB);
        return resultA && resultB;
    }
}
