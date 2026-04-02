import { pqValidatorAbi } from '../abis/pqValidatorAbi.js';
import type { SchemeIdType } from '../types.js';
import type { Address, Chain, PublicClient, Transport } from 'viem';

/**
 * Get the ECDSA owner of an account.
 */
export async function getOwner(
  client: PublicClient<Transport, Chain>,
  validatorAddress: Address,
  accountAddress: Address
): Promise<Address> {
  return client.readContract({
    address: validatorAddress,
    abi: pqValidatorAbi,
    functionName: 'getOwner',
    args: [accountAddress],
  });
}

/**
 * Check if a specific key is approved for an account and scheme.
 */
export async function isKeyApproved(
  client: PublicClient<Transport, Chain>,
  validatorAddress: Address,
  accountAddress: Address,
  schemeId: SchemeIdType,
  keyId: `0x${string}`
): Promise<boolean> {
  return client.readContract({
    address: validatorAddress,
    abi: pqValidatorAbi,
    functionName: 'isKeyApproved',
    args: [accountAddress, BigInt(schemeId), keyId],
  });
}

/**
 * Check if a signature scheme is allowed for an account.
 */
export async function isSchemeAllowed(
  client: PublicClient<Transport, Chain>,
  validatorAddress: Address,
  accountAddress: Address,
  schemeId: SchemeIdType
): Promise<boolean> {
  return client.readContract({
    address: validatorAddress,
    abi: pqValidatorAbi,
    functionName: 'isSchemeAllowed',
    args: [accountAddress, BigInt(schemeId)],
  });
}

/**
 * Check if the PQValidator is initialized for an account.
 */
export async function isValidatorInitialized(
  client: PublicClient<Transport, Chain>,
  validatorAddress: Address,
  accountAddress: Address
): Promise<boolean> {
  return client.readContract({
    address: validatorAddress,
    abi: pqValidatorAbi,
    functionName: 'isInitialized',
    args: [accountAddress],
  });
}
