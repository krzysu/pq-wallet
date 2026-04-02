/**
 * Minimal KernelFactory ABI — only functions used by the SDK.
 */
export const kernelFactoryAbi = [
  {
    type: 'function',
    name: 'createAccount',
    inputs: [
      { name: 'data', type: 'bytes', internalType: 'bytes' },
      { name: 'salt', type: 'bytes32', internalType: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'address', internalType: 'address' }],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    name: 'getAddress',
    inputs: [
      { name: 'data', type: 'bytes', internalType: 'bytes' },
      { name: 'salt', type: 'bytes32', internalType: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'address', internalType: 'address' }],
    stateMutability: 'view',
  },
] as const;
