/**
 * PQValidator ABI — key management, views, and module interface functions.
 */
export const pqValidatorAbi = [
  // Key Management
  {
    type: 'function',
    name: 'registerPublicKey',
    inputs: [
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
      { name: 'publicKey', type: 'bytes', internalType: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'revokeKey',
    inputs: [
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
      { name: 'keyId', type: 'bytes32', internalType: 'bytes32' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'setSchemeAllowed',
    inputs: [
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
      { name: 'allowed', type: 'bool', internalType: 'bool' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'disableEcdsa',
    inputs: [
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
      { name: 'publicKey', type: 'bytes', internalType: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  // Views
  {
    type: 'function',
    name: 'getOwner',
    inputs: [{ name: 'account', type: 'address', internalType: 'address' }],
    outputs: [{ name: '', type: 'address', internalType: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isKeyApproved',
    inputs: [
      { name: 'account', type: 'address', internalType: 'address' },
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
      { name: 'keyId', type: 'bytes32', internalType: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'bool', internalType: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isSchemeAllowed',
    inputs: [
      { name: 'account', type: 'address', internalType: 'address' },
      { name: 'schemeId', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool', internalType: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isInitialized',
    inputs: [{ name: 'smartAccount', type: 'address', internalType: 'address' }],
    outputs: [{ name: '', type: 'bool', internalType: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'ROUTER',
    inputs: [],
    outputs: [{ name: '', type: 'address', internalType: 'contract PQSignatureRouter' }],
    stateMutability: 'view',
  },
] as const;
