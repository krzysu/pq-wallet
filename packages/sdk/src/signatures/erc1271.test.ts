import { type Address, toHex, type Hex, hexToBytes } from 'viem';
import { describe, it, expect } from 'vitest';
import { wrapSignatureWithValidationId } from './erc1271.js';

function dummyHex(byteLength: number): Hex {
  return toHex(new Uint8Array(byteLength).fill(0xab));
}

describe('wrapSignatureWithValidationId', () => {
  it('prepends mode byte 0x01 and validator address', () => {
    const signature = dummyHex(65);
    const validatorAddress: Address = '0x1234567890abcdef1234567890abcdef12345678';

    const wrapped = wrapSignatureWithValidationId(signature, validatorAddress);
    const bytes = hexToBytes(wrapped);

    // First byte: mode 0x01
    expect(bytes[0]).toBe(0x01);
    // Next 20 bytes: validator address
    const addrBytes = bytes.slice(1, 21);
    const expectedAddr = hexToBytes(validatorAddress);
    expect(Buffer.from(addrBytes).toString('hex')).toBe(Buffer.from(expectedAddr).toString('hex'));
    // Remaining bytes: original signature
    const sigBytes = bytes.slice(21);
    expect(sigBytes.length).toBe(65);
  });
});
