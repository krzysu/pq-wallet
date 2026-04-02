/**
 * Minimal Kernel v3.3 ABI — only functions used by the SDK.
 */
export const kernelV3Abi = [
  {
    type: 'function',
    name: 'initialize',
    inputs: [
      { name: '_rootValidator', type: 'bytes21', internalType: 'ValidationId' },
      { name: 'hook', type: 'address', internalType: 'contract IHook' },
      { name: 'validatorData', type: 'bytes', internalType: 'bytes' },
      { name: 'hookData', type: 'bytes', internalType: 'bytes' },
      { name: 'initConfig', type: 'bytes[]', internalType: 'bytes[]' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'execute',
    inputs: [
      { name: 'execMode', type: 'bytes32', internalType: 'ExecMode' },
      { name: 'executionCalldata', type: 'bytes', internalType: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    name: 'installModule',
    inputs: [
      { name: 'moduleType', type: 'uint256', internalType: 'uint256' },
      { name: 'module', type: 'address', internalType: 'address' },
      { name: 'initData', type: 'bytes', internalType: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    name: 'uninstallModule',
    inputs: [
      { name: 'moduleType', type: 'uint256', internalType: 'uint256' },
      { name: 'module', type: 'address', internalType: 'address' },
      { name: 'deInitData', type: 'bytes', internalType: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'payable',
  },
] as const;
