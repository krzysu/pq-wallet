import { keccak256, encodePacked, toHex, type Hex } from 'viem';
import { describe, it, expect } from 'vitest';
import { computeKeyId, computeEcdsaKeyId, computeComposedKeyId } from './keyId.js';

function dummyHex(byteLength: number): Hex {
  return toHex(new Uint8Array(byteLength).fill(0xab));
}

describe('computeKeyId', () => {
  it('returns keccak256 of the public key', () => {
    const publicKey = dummyHex(1024);
    expect(computeKeyId(publicKey)).toBe(keccak256(publicKey));
  });
});

describe('computeEcdsaKeyId', () => {
  it('returns keccak256 of address packed as uint256', () => {
    const address = '0x1234567890abcdef1234567890abcdef12345678';
    const packed = encodePacked(['uint256'], [BigInt(address)]);
    expect(computeEcdsaKeyId(address)).toBe(keccak256(packed));
  });
});

describe('computeComposedKeyId', () => {
  it('returns keccak256(abi.encodePacked(keyIdA, keyIdB))', () => {
    const keyIdA = dummyHex(32);
    const keyIdB = toHex(new Uint8Array(32).fill(0xbb));

    const expected = keccak256(encodePacked(['bytes32', 'bytes32'], [keyIdA, keyIdB]));
    expect(computeComposedKeyId(keyIdA, keyIdB)).toBe(expected);
  });
});
