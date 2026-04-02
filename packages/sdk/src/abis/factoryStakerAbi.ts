/**
 * Minimal FactoryStaker (MetaFactory) ABI — only functions used by the SDK.
 */
export const factoryStakerAbi = [
  {
    type: 'function',
    name: 'deployWithFactory',
    inputs: [
      { name: 'factory', type: 'address', internalType: 'contract KernelFactory' },
      { name: 'createData', type: 'bytes', internalType: 'bytes' },
      { name: 'salt', type: 'bytes32', internalType: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'address', internalType: 'address' }],
    stateMutability: 'payable',
  },
] as const;
