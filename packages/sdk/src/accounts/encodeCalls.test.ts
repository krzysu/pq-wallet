import { decodeFunctionData, type Address, type Hex } from 'viem';
import { describe, it, expect } from 'vitest';
import { kernelV3Abi } from '../abis/kernelV3Abi.js';
import { EXEC_MODE } from '../constants.js';
import { encodeCalls } from './encodeCalls.js';

const ADDR_1: Address = '0x1234567890abcdef1234567890abcdef12345678';
const ADDR_2: Address = '0x1111111111111111111111111111111111111111';
const ADDR_3: Address = '0x2222222222222222222222222222222222222222';

describe('encodeCalls', () => {
  it('throws for empty calls array', () => {
    expect(() => encodeCalls([])).toThrow('At least one call is required');
  });

  it('encodes a single call with CALLTYPE_SINGLE', () => {
    const calldata: Hex = '0xdeadbeef';
    const calls = [{ to: ADDR_1, value: 1000n, data: calldata }];

    const encoded = encodeCalls(calls);
    const decoded = decodeFunctionData({ abi: kernelV3Abi, data: encoded });

    expect(decoded.functionName).toBe('execute');
    expect(decoded.args[0]).toBe(EXEC_MODE.SINGLE);
  });

  it('encodes batch calls with CALLTYPE_BATCH', () => {
    const calls = [{ to: ADDR_2 }, { to: ADDR_3, value: 100n }];

    const encoded = encodeCalls(calls);
    const decoded = decodeFunctionData({ abi: kernelV3Abi, data: encoded });

    expect(decoded.functionName).toBe('execute');
    expect(decoded.args[0]).toBe(EXEC_MODE.BATCH);
  });
});
