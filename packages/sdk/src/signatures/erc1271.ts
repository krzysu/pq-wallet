import { encodePacked, hashTypedData, type Address, type Hex } from 'viem';
import { KERNEL_ERC1271_DOMAIN } from '../constants.js';

/**
 * Wrap a message hash with Kernel's EIP-712 domain separation for ERC-1271 verification.
 * Kernel's isValidSignature() expects signatures over this wrapped hash, not the raw hash.
 *
 * Domain: { name: "Kernel", version: "0.3.3", chainId, verifyingContract: accountAddress }
 * Type: Kernel(bytes32 hash)
 */
export function wrapHashForERC1271(hash: Hex, accountAddress: Address, chainId: number): Hex {
  return hashTypedData({
    domain: {
      ...KERNEL_ERC1271_DOMAIN,
      chainId,
      verifyingContract: accountAddress,
    },
    types: {
      Kernel: [{ name: 'hash', type: 'bytes32' }],
    },
    primaryType: 'Kernel',
    message: { hash },
  });
}

/**
 * Wrap a signature with Kernel's ValidationId prefix for ERC-1271 routing.
 * Kernel needs to know which validator should verify the signature.
 *
 * Format: mode(1 byte) || validatorAddress(20 bytes) || signature
 * Mode 0x01 = validator mode
 */
export function wrapSignatureWithValidationId(signature: Hex, validatorAddress: Address): Hex {
  return encodePacked(['bytes1', 'address', 'bytes'], ['0x01', validatorAddress, signature]);
}
