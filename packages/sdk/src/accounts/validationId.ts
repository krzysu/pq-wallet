import { concatHex, type Address, type Hex } from 'viem';

/**
 * Build the root ValidationId for a validator address.
 * Format: 0x00 (VALIDATION_TYPE_ROOT) + address (20 bytes) = 21 bytes
 */
export function buildRootValidationId(validatorAddress: Address): Hex {
  return concatHex(['0x00', validatorAddress]);
}
