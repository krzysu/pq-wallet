// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IPQVerifier
/// @notice Common interface for all post-quantum signature verification adapters.
/// Each adapter wraps a specific cryptographic scheme and handles on-chain key storage.
///
/// ACCESS CONTROL: registerKey should be restricted to the authorized caller
/// (typically PQSignatureRouter). verify is read-only and can be called by anyone.
interface IPQVerifier {
    /// @notice Store a public key on-chain. Called once per key during account setup.
    /// @param publicKey The raw public key bytes (format depends on the adapter)
    /// @return keyId Identifier for the stored key (used in verify)
    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId);

    /// @notice Verify a signature against a stored key.
    /// @param hash The message hash
    /// @param signature The cryptographic signature
    /// @param keyId The key identifier (from registerKey)
    /// @return True if the signature is valid
    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool);
}
