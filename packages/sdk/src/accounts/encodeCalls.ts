import {
  encodeFunctionData,
  encodePacked,
  encodeAbiParameters,
  parseAbiParameters,
  type Hex,
} from 'viem';
import { kernelV3Abi } from '../abis/kernelV3Abi.js';
import { EXEC_MODE } from '../constants.js';
import type { Call } from '../types.js';

/**
 * Encode calls as Kernel v3.3 execute calldata.
 * Uses CALLTYPE_SINGLE for one call, CALLTYPE_BATCH for multiple.
 */
export function encodeCalls(calls: ReadonlyArray<Call>): Hex {
  if (calls.length === 0) {
    throw new Error('At least one call is required');
  }

  if (calls.length === 1) {
    const call = calls[0]!;
    const executionCalldata = encodePacked(
      ['address', 'uint256', 'bytes'],
      [call.to, call.value ?? 0n, call.data ?? '0x']
    );

    return encodeFunctionData({
      abi: kernelV3Abi,
      functionName: 'execute',
      args: [EXEC_MODE.SINGLE, executionCalldata],
    });
  }

  const executionCalldata = encodeAbiParameters(
    parseAbiParameters('(address target, uint256 value, bytes callData)[] executions'),
    [
      calls.map((call) => ({
        target: call.to,
        value: call.value ?? 0n,
        callData: call.data ?? '0x',
      })),
    ]
  );

  return encodeFunctionData({
    abi: kernelV3Abi,
    functionName: 'execute',
    args: [EXEC_MODE.BATCH, executionCalldata],
  });
}
