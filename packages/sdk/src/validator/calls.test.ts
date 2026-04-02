import { decodeFunctionData, toHex, type Address, type Hex } from 'viem';
import { describe, it, expect } from 'vitest';
import { pqValidatorAbi } from '../abis/pqValidatorAbi.js';
import {
  buildRegisterKeyCall,
  buildRevokeKeyCall,
  buildSetSchemeAllowedCall,
  buildDisableEcdsaCall,
} from './calls.js';

const VALIDATOR: Address = '0x1234567890abcdef1234567890abcdef12345678';

function dummyHex(byteLength: number): Hex {
  return toHex(new Uint8Array(byteLength).fill(0xab));
}

describe('buildRegisterKeyCall', () => {
  it('encodes registerPublicKey(schemeId, publicKey)', () => {
    const publicKey = dummyHex(1024);
    const call = buildRegisterKeyCall(VALIDATOR, 1, publicKey);

    expect(call.to).toBe(VALIDATOR);
    const decoded = decodeFunctionData({ abi: pqValidatorAbi, data: call.data! });
    expect(decoded.functionName).toBe('registerPublicKey');
    expect(decoded.args[0]).toBe(1n);
  });
});

describe('buildRevokeKeyCall', () => {
  it('encodes revokeKey(schemeId, keyId)', () => {
    const keyId = dummyHex(32);
    const call = buildRevokeKeyCall(VALIDATOR, 1, keyId);

    const decoded = decodeFunctionData({ abi: pqValidatorAbi, data: call.data! });
    expect(decoded.functionName).toBe('revokeKey');
  });
});

describe('buildSetSchemeAllowedCall', () => {
  it('encodes setSchemeAllowed(schemeId, allowed)', () => {
    const call = buildSetSchemeAllowedCall(VALIDATOR, 1, true);

    const decoded = decodeFunctionData({ abi: pqValidatorAbi, data: call.data! });
    expect(decoded.functionName).toBe('setSchemeAllowed');
    expect(decoded.args[0]).toBe(1n);
    expect(decoded.args[1]).toBe(true);
  });
});

describe('buildDisableEcdsaCall', () => {
  it('encodes disableEcdsa(schemeId, publicKey)', () => {
    const publicKey = dummyHex(1024);
    const call = buildDisableEcdsaCall(VALIDATOR, 1, publicKey);

    const decoded = decodeFunctionData({ abi: pqValidatorAbi, data: call.data! });
    expect(decoded.functionName).toBe('disableEcdsa');
    expect(decoded.args[0]).toBe(1n);
  });
});
