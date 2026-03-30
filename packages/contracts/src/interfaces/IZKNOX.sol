// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IZKNOX
/// @notice Interface for ZKNOX on-chain verifiers (ETHFALCON, MLDSAETH).
/// Matches the deployed ISigVerifier interface from ZKNOX InterfaceVerifier.
/// Both ZKNOX_ethfalcon and ZKNOX_ethdilithium implement this interface,
/// providing SSTORE2-based key storage and unified verification.

/// @notice Standard ZKNOX signature verifier interface (ISigVerifier).
/// Used by all ZKNOX verifier contracts for key storage and signature verification.
interface ISigVerifier {
    /// @notice Store a public key on-chain via SSTORE2. Returns the PKContract address.
    /// @param key The public key bytes (format depends on verifier)
    /// @return Encoded PKContract address
    function setKey(
        bytes calldata key
    ) external returns (bytes memory);

    /// @notice Verify a signature against a stored key.
    /// @param key The PKContract address (as bytes, left-padded)
    /// @param hash The message hash
    /// @param signature The cryptographic signature
    /// @return verify.selector on success, 0xFFFFFFFF on failure
    function verify(
        bytes calldata key,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);
}
