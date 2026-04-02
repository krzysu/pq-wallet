import type { SchemeId } from './constants.js';
import type { Address, Hex } from 'viem';

/**
 * Union of all valid scheme ID values.
 */
export type SchemeIdType = (typeof SchemeId)[keyof typeof SchemeId];

/**
 * External PQ signer interface. The SDK does not bundle PQC crypto —
 * callers provide their own signing implementation via this interface.
 *
 * For ECDSA, use viem's LocalAccount directly instead.
 */
export interface PQSigner {
  /** The signature scheme this signer handles */
  readonly scheme: SchemeIdType;
  /** Solidity-format public key (e.g., 1024 bytes for ETHFALCON) */
  readonly publicKey: Hex;
  /** Sign a hash and return the inner signature bytes expected by the adapter */
  sign(hash: Hex): Promise<Hex>;
}

/**
 * Composed (hybrid) signer that combines two sub-signers.
 * The SDK derives the composed keyId from the owner address and the PQ signer's public key.
 */
export interface ComposedSigner {
  /** The composed scheme ID (e.g., ECDSA_ETHFALCON = 101) */
  readonly scheme: SchemeIdType;
  /** First sub-signer (e.g., ECDSA) */
  readonly signerA: { sign(hash: Hex): Promise<Hex> };
  /** Second sub-signer (e.g., ETHFALCON) */
  readonly signerB: { sign(hash: Hex): Promise<Hex> };
}

/**
 * A call to be executed by the smart account.
 */
export interface Call {
  to: Address;
  value?: bigint;
  data?: Hex;
}
