import { encodeAbiParameters, type Hex } from 'viem';
import type { SchemeIdType } from '../types.js';

/**
 * Encode a raw ECDSA signature for the PQValidator fast path.
 * PQValidator detects 65-byte signatures and uses ECDSA recovery directly.
 *
 * @param signature - 65-byte ECDSA signature (r || s || v)
 * @returns The signature unchanged (already in the correct format)
 */
export function encodeEcdsaSignature(signature: Hex): Hex {
  return signature;
}

/**
 * Encode a PQ signature in the ABI format expected by PQValidator._verify().
 * Format: `abi.encode(uint256 schemeId, bytes innerSig, bytes32 keyId)`
 *
 * @param schemeId - The scheme identifier (e.g., ETHFALCON = 1)
 * @param innerSignature - Adapter-specific signature bytes
 * @param keyId - The registered key identifier
 */
export function encodePQSignature(schemeId: SchemeIdType, innerSignature: Hex, keyId: Hex): Hex {
  return encodeAbiParameters(
    [
      { type: 'uint256', name: 'schemeId' },
      { type: 'bytes', name: 'innerSig' },
      { type: 'bytes32', name: 'keyId' },
    ],
    [BigInt(schemeId), innerSignature, keyId]
  );
}

/**
 * Encode a composed (hybrid) signature for schemes like ECDSA+ETHFALCON.
 * The inner signature is `abi.encode(sigA, sigB)` per ComposedVerifier.verify().
 *
 * @param schemeId - The composed scheme ID (e.g., ECDSA_ETHFALCON = 101)
 * @param signatureA - First sub-adapter signature
 * @param signatureB - Second sub-adapter signature
 * @param composedKeyId - The composed key identifier
 */
export function encodeComposedSignature(
  schemeId: SchemeIdType,
  signatureA: Hex,
  signatureB: Hex,
  composedKeyId: Hex
): Hex {
  const innerSignature = encodeAbiParameters(
    [
      { type: 'bytes', name: 'sigA' },
      { type: 'bytes', name: 'sigB' },
    ],
    [signatureA, signatureB]
  );

  return encodePQSignature(schemeId, innerSignature, composedKeyId);
}
