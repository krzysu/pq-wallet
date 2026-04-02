import { encodeAbiParameters, encodeFunctionData, type Address, type Hex } from 'viem';
import { pqValidatorAbi } from '../abis/pqValidatorAbi.js';
import type { Call, SchemeIdType } from '../types.js';

/**
 * Build a call to register a public key for a PQ scheme.
 * The account must execute this via a UserOperation.
 *
 * @param validatorAddress - PQValidator contract address
 * @param schemeId - The scheme to register the key for
 * @param publicKey - Solidity-format public key bytes
 */
export function buildRegisterKeyCall(
  validatorAddress: Address,
  schemeId: SchemeIdType,
  publicKey: Hex
): Call {
  return {
    to: validatorAddress,
    data: encodeFunctionData({
      abi: pqValidatorAbi,
      functionName: 'registerPublicKey',
      args: [BigInt(schemeId), publicKey],
    }),
  };
}

/**
 * Build a call to revoke a previously registered key.
 *
 * @param validatorAddress - PQValidator contract address
 * @param schemeId - The scheme the key belongs to
 * @param keyId - The key identifier to revoke
 */
export function buildRevokeKeyCall(
  validatorAddress: Address,
  schemeId: SchemeIdType,
  keyId: Hex
): Call {
  return {
    to: validatorAddress,
    data: encodeFunctionData({
      abi: pqValidatorAbi,
      functionName: 'revokeKey',
      args: [BigInt(schemeId), keyId],
    }),
  };
}

/**
 * Build a call to enable or disable a signature scheme.
 *
 * @param validatorAddress - PQValidator contract address
 * @param schemeId - The scheme to configure
 * @param allowed - Whether the scheme should be allowed
 */
export function buildSetSchemeAllowedCall(
  validatorAddress: Address,
  schemeId: SchemeIdType,
  allowed: boolean
): Call {
  return {
    to: validatorAddress,
    data: encodeFunctionData({
      abi: pqValidatorAbi,
      functionName: 'setSchemeAllowed',
      args: [BigInt(schemeId), allowed],
    }),
  };
}

/**
 * Build a call to atomically disable ECDSA and enable a PQ scheme.
 * This registers the PQ key, enables the PQ scheme, and disables ECDSA in one transaction.
 *
 * @param validatorAddress - PQValidator contract address
 * @param schemeId - The PQ scheme to enable (must not be ECDSA)
 * @param publicKey - Solidity-format public key for the PQ scheme
 */
export function buildDisableEcdsaCall(
  validatorAddress: Address,
  schemeId: SchemeIdType,
  publicKey: Hex
): Call {
  return {
    to: validatorAddress,
    data: encodeFunctionData({
      abi: pqValidatorAbi,
      functionName: 'disableEcdsa',
      args: [BigInt(schemeId), publicKey],
    }),
  };
}

/**
 * Build a call to register a composed (hybrid) public key.
 * The composed key is `abi.encode(publicKeyA, publicKeyB)` per ComposedVerifier.
 *
 * @param validatorAddress - PQValidator contract address
 * @param schemeId - The composed scheme ID (e.g., ECDSA_ETHFALCON = 101)
 * @param publicKeyA - First sub-adapter public key (e.g., ECDSA address as bytes)
 * @param publicKeyB - Second sub-adapter public key (e.g., ETHFALCON 1024-byte key)
 */
export function buildRegisterComposedKeyCall(
  validatorAddress: Address,
  schemeId: SchemeIdType,
  publicKeyA: Hex,
  publicKeyB: Hex
): Call {
  // ComposedVerifier expects abi.encode(pkA, pkB)
  const composedPublicKey = encodeAbiParameters(
    [
      { type: 'bytes', name: 'pkA' },
      { type: 'bytes', name: 'pkB' },
    ],
    [publicKeyA, publicKeyB]
  );

  return {
    to: validatorAddress,
    data: encodeFunctionData({
      abi: pqValidatorAbi,
      functionName: 'registerPublicKey',
      args: [BigInt(schemeId), composedPublicKey],
    }),
  };
}
