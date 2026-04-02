import { decodeAbiParameters, toHex, type Hex } from 'viem';
import { describe, it, expect } from 'vitest';
import {
  encodeEcdsaSignature,
  encodePQSignature,
  encodeComposedSignature,
} from './encodeSignature.js';

function dummyHex(byteLength: number): Hex {
  return toHex(new Uint8Array(byteLength).fill(0xab));
}

describe('encodeEcdsaSignature', () => {
  it('returns the signature unchanged (65-byte fast path)', () => {
    const sig = dummyHex(65);
    expect(encodeEcdsaSignature(sig)).toBe(sig);
  });
});

describe('encodePQSignature', () => {
  it('ABI-encodes (schemeId, innerSig, keyId)', () => {
    const schemeId = 1; // ETHFALCON
    const innerSig = dummyHex(1064);
    const keyId = dummyHex(32);

    const encoded = encodePQSignature(schemeId, innerSig, keyId);

    // Decode and verify
    const [decodedScheme, decodedInner, decodedKeyId] = decodeAbiParameters(
      [
        { type: 'uint256', name: 'schemeId' },
        { type: 'bytes', name: 'innerSig' },
        { type: 'bytes32', name: 'keyId' },
      ],
      encoded
    );

    expect(decodedScheme).toBe(BigInt(schemeId));
    expect(decodedInner.toLowerCase()).toBe(innerSig.toLowerCase());
    expect(decodedKeyId.toLowerCase()).toBe(keyId.toLowerCase());
  });

  it('produces signatures >= 128 bytes (MIN_ABI_ENCODED_SIG_LENGTH)', () => {
    const encoded = encodePQSignature(1, '0xaabb', dummyHex(32));
    // Remove 0x prefix, divide by 2 for byte length
    const byteLength = (encoded.length - 2) / 2;
    expect(byteLength).toBeGreaterThanOrEqual(128);
  });
});

describe('encodeComposedSignature', () => {
  it('wraps two signatures in abi.encode(sigA, sigB) as innerSig', () => {
    const schemeId = 101; // ECDSA_ETHFALCON
    const sigA = dummyHex(65);
    const sigB = dummyHex(1064);
    const composedKeyId = dummyHex(32);

    const encoded = encodeComposedSignature(schemeId, sigA, sigB, composedKeyId);

    // Decode outer layer
    const [decodedScheme, innerSig, decodedKeyId] = decodeAbiParameters(
      [
        { type: 'uint256', name: 'schemeId' },
        { type: 'bytes', name: 'innerSig' },
        { type: 'bytes32', name: 'keyId' },
      ],
      encoded
    );

    expect(decodedScheme).toBe(BigInt(schemeId));
    expect(decodedKeyId.toLowerCase()).toBe(composedKeyId.toLowerCase());

    // Decode inner layer
    const [decodedSigA, decodedSigB] = decodeAbiParameters(
      [
        { type: 'bytes', name: 'sigA' },
        { type: 'bytes', name: 'sigB' },
      ],
      innerSig
    );

    expect(decodedSigA.toLowerCase()).toBe(sigA.toLowerCase());
    expect(decodedSigB.toLowerCase()).toBe(sigB.toLowerCase());
  });
});
