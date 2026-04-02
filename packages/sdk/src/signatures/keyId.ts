import { keccak256, encodePacked, type Hex } from 'viem';

/**
 * Compute the keyId for a single-adapter public key.
 * Matches the on-chain computation: `keccak256(publicKey)`.
 *
 * For ECDSA, the publicKey is the signer address (20 bytes raw or 32 bytes ABI-padded).
 * For ETHFALCON, the publicKey is 1024 bytes (32 packed uint256 NTT coefficients).
 * For MLDSAETH, the publicKey is the ABI-encoded expanded key (>= 2048 bytes).
 */
export function computeKeyId(publicKey: Hex): Hex {
  return keccak256(publicKey);
}

/**
 * Compute the keyId for an ECDSA signer.
 * Matches EcdsaVerifier.registerKey: keccak256 of address packed as bytes32 (lower 160 bits).
 */
export function computeEcdsaKeyId(address: Hex): Hex {
  return keccak256(encodePacked(['uint256'], [BigInt(address)]));
}

/**
 * Compute the composed keyId for a hybrid scheme.
 * Matches ComposedVerifier: `keccak256(abi.encodePacked(keyIdA, keyIdB))`.
 */
export function computeComposedKeyId(keyIdA: Hex, keyIdB: Hex): Hex {
  return keccak256(encodePacked(['bytes32', 'bytes32'], [keyIdA, keyIdB]));
}
