// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPQVerifier} from "./IPQVerifier.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

/// @title EcdsaVerifier
/// @notice ECDSA signature verification adapter using Solady.
/// The "key" for ECDSA is the signer address. registerKey accepts the ABI-encoded
/// signer address and returns it packed as bytes32 so that verify can extract it
/// back. This makes registerKey and verify compatible when used through ComposedVerifier.
contract EcdsaVerifier is IPQVerifier {
    error InvalidPublicKeyLength();

    /// @notice Register an ECDSA signer. publicKey must be the ABI-encoded signer address (20 bytes unpadded or 32 bytes ABI-padded).
    /// @return keyId The signer address packed as bytes32 (address in lower 160 bits)
    function registerKey(
        bytes calldata publicKey
    ) external pure returns (bytes32) {
        if (publicKey.length != 20 && publicKey.length != 32) revert InvalidPublicKeyLength();
        address signer;
        if (publicKey.length == 20) {
            signer = address(bytes20(publicKey));
        } else {
            signer = abi.decode(publicKey, (address));
        }
        return bytes32(uint256(uint160(signer)));
    }

    /// @notice Verify an ECDSA signature.
    /// @param hash The message hash (EIP-191 or raw)
    /// @param signature 65-byte ECDSA signature (r, s, v)
    /// @param keyId The expected signer address packed as bytes32 (from registerKey)
    /// @return True if the recovered address matches keyId
    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        address expectedSigner = address(uint160(uint256(keyId)));
        address recovered = ECDSA.recover(hash, signature);
        return recovered == expectedSigner;
    }
}
