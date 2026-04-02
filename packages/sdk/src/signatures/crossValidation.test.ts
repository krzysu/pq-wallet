/**
 * Cross-validation tests: verify SDK signature encoding matches
 * the exact byte format expected by PQValidator on-chain.
 *
 * Uses the same fixtures from packages/contracts/test/fixtures/PQFixtures.sol
 * and the same encoding patterns from packages/contracts/test/Integration.t.sol.
 */
import { decodeAbiParameters, encodeAbiParameters, encodePacked, keccak256, toHex } from 'viem';
import { describe, it, expect } from 'vitest';
import { SchemeId } from '../constants.js';
import {
  encodePQSignature,
  encodeEcdsaSignature,
  encodeComposedSignature,
} from './encodeSignature.js';
import { MESSAGE_HASH, ETHFALCON_PUBLIC_KEY, ETHFALCON_SIGNATURE } from './fixtures.js';
import { computeKeyId, computeComposedKeyId } from './keyId.js';

describe('cross-validation: signature encoding matches Solidity', () => {
  describe('ECDSA fast path', () => {
    it('65-byte ECDSA signature is passed through unchanged', () => {
      // Solidity: abi.encodePacked(r, s, v) = 65 bytes, used directly
      // SDK: encodeEcdsaSignature returns the same 65 bytes
      const rawSig = toHex(
        new Uint8Array([...Array<number>(32).fill(0xab), ...Array<number>(32).fill(0xcd), 0x1b])
      );
      const encoded = encodeEcdsaSignature(rawSig);
      expect(encoded).toBe(rawSig);
      // 65 bytes = ECDSA fast path in PQValidator._verify()
      expect((encoded.length - 2) / 2).toBe(65);
    });
  });

  describe('PQ signature encoding', () => {
    it('matches Solidity abi.encode(uint256, bytes, bytes32) for ETHFALCON', () => {
      const schemeId = SchemeId.ETHFALCON;
      const innerSig = ETHFALCON_SIGNATURE;
      const keyId = computeKeyId(ETHFALCON_PUBLIC_KEY);

      // SDK encoding
      const sdkEncoded = encodePQSignature(schemeId, innerSig, keyId);

      // Solidity equivalent: abi.encode(uint256(1), innerSig, keyId)
      const solidityEncoded = encodeAbiParameters(
        [
          { type: 'uint256', name: 'schemeId' },
          { type: 'bytes', name: 'innerSig' },
          { type: 'bytes32', name: 'keyId' },
        ],
        [BigInt(schemeId), innerSig, keyId]
      );

      expect(sdkEncoded).toBe(solidityEncoded);
    });

    it('produces signatures >= 128 bytes (MIN_ABI_ENCODED_SIG_LENGTH)', () => {
      const keyId = computeKeyId(ETHFALCON_PUBLIC_KEY);
      const encoded = encodePQSignature(SchemeId.ETHFALCON, ETHFALCON_SIGNATURE, keyId);
      expect((encoded.length - 2) / 2).toBeGreaterThanOrEqual(128);
    });

    it('roundtrip: decode matches original inputs', () => {
      const schemeId = SchemeId.ETHFALCON;
      const innerSig = ETHFALCON_SIGNATURE;
      const keyId = computeKeyId(ETHFALCON_PUBLIC_KEY);

      const encoded = encodePQSignature(schemeId, innerSig, keyId);

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
  });

  describe('keyId computation', () => {
    it('matches Solidity keccak256(publicKey) for ETHFALCON', () => {
      // Solidity: bytes32 pqKeyId = keccak256(pqPublicKey)
      const keyId = computeKeyId(ETHFALCON_PUBLIC_KEY);
      const expected = keccak256(ETHFALCON_PUBLIC_KEY);
      expect(keyId).toBe(expected);
    });

    it('matches Solidity keccak256(abi.encodePacked(keyIdA, keyIdB)) for composed', () => {
      const keyIdA = keccak256('0xdeadbeef');
      const keyIdB = computeKeyId(ETHFALCON_PUBLIC_KEY);
      const composed = computeComposedKeyId(keyIdA, keyIdB);

      const expected = keccak256(encodePacked(['bytes32', 'bytes32'], [keyIdA, keyIdB]));
      expect(composed).toBe(expected);
    });
  });

  describe('composed signature encoding', () => {
    it('matches Solidity abi.encode(schemeId, abi.encode(sigA, sigB), composedKeyId)', () => {
      const ecdsaSig = toHex(
        new Uint8Array([...Array<number>(32).fill(0xab), ...Array<number>(32).fill(0xcd), 0x1b])
      );
      const falconSig = ETHFALCON_SIGNATURE;
      const ecdsaKeyId = keccak256('0xdeadbeef');
      const falconKeyId = computeKeyId(ETHFALCON_PUBLIC_KEY);
      const composedKeyId = computeComposedKeyId(ecdsaKeyId, falconKeyId);

      // SDK encoding
      const sdkEncoded = encodeComposedSignature(
        SchemeId.ECDSA_ETHFALCON,
        ecdsaSig,
        falconSig,
        composedKeyId
      );

      // Solidity equivalent
      const innerSig = encodeAbiParameters(
        [
          { type: 'bytes', name: 'sigA' },
          { type: 'bytes', name: 'sigB' },
        ],
        [ecdsaSig, falconSig]
      );
      const solidityEncoded = encodeAbiParameters(
        [
          { type: 'uint256', name: 'schemeId' },
          { type: 'bytes', name: 'innerSig' },
          { type: 'bytes32', name: 'keyId' },
        ],
        [BigInt(SchemeId.ECDSA_ETHFALCON), innerSig, composedKeyId]
      );

      expect(sdkEncoded).toBe(solidityEncoded);
    });
  });

  describe('fixture data integrity', () => {
    it('ETHFALCON public key is exactly 1024 bytes', () => {
      expect((ETHFALCON_PUBLIC_KEY.length - 2) / 2).toBe(1024);
    });

    it('ETHFALCON signature is exactly 1064 bytes (salt 40 + s2 1024)', () => {
      expect((ETHFALCON_SIGNATURE.length - 2) / 2).toBe(1064);
    });

    it('message hash is exactly 32 bytes', () => {
      expect((MESSAGE_HASH.length - 2) / 2).toBe(32);
    });
  });
});
