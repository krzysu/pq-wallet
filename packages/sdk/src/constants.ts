import { getAddress, zeroAddress } from 'viem';
import { entryPoint07Abi, entryPoint07Address } from 'viem/account-abstraction';

/**
 * EntryPoint v0.7 configuration for ERC-4337.
 */
export const ENTRY_POINT = {
  address: entryPoint07Address,
  version: '0.7' as const,
  abi: entryPoint07Abi,
};

/**
 * Kernel v3.3 deterministic contract addresses (same on all chains).
 */
export const KERNEL_V3_3 = {
  implementation: getAddress('0xd6CEDDe84be40893d153Be9d467CD6aD37875b28'),
  factory: getAddress('0x2577507b78c2008Ff367261CB6285d44ba5eF2E9'),
  metaFactory: getAddress('0xd703aaE79538628d27099B8c4f621bE4CCd142d5'),
};

/**
 * Signature scheme IDs matching SchemeIds.sol.
 *
 * Single schemes: 0-99
 * Combined (hybrid) schemes: 100 + PQ scheme index
 */
export const SchemeId = {
  ECDSA: 0,
  ETHFALCON: 1,
  MLDSAETH: 2,
  ECDSA_ETHFALCON: 101,
  ECDSA_MLDSAETH: 102,
} as const;

/**
 * Kernel execution mode bytes for single and batch calls.
 * First byte encodes CallType, rest is zero.
 */
export const EXEC_MODE = {
  SINGLE: '0x0000000000000000000000000000000000000000000000000000000000000000',
  BATCH: '0x0100000000000000000000000000000000000000000000000000000000000000',
} as const;

/**
 * Kernel ERC-1271 EIP-712 domain for signature wrapping.
 */
export const KERNEL_ERC1271_DOMAIN = {
  name: 'Kernel',
  version: '0.3.3',
} as const;

/**
 * Address representing "no hook" in Kernel module installation.
 */
export const NO_HOOK = zeroAddress;

/**
 * Single (non-composed) scheme IDs.
 */
export type SingleSchemeId =
  | typeof SchemeId.ECDSA
  | typeof SchemeId.ETHFALCON
  | typeof SchemeId.MLDSAETH;

/**
 * Composed (hybrid) scheme IDs.
 */
export type ComposedSchemeId = typeof SchemeId.ECDSA_ETHFALCON | typeof SchemeId.ECDSA_MLDSAETH;

/**
 * Inner signature sizes in bytes for each single scheme.
 * Used to build correctly-sized stub signatures for gas estimation.
 */
const SIGNATURE_SIZE: Record<SingleSchemeId, number> = {
  [SchemeId.ECDSA]: 65,
  [SchemeId.ETHFALCON]: 1064,
  [SchemeId.MLDSAETH]: 2420,
};

/**
 * Get the inner signature size for a single scheme.
 * Throws if the scheme ID has no known signature size.
 */
export function getSignatureSize(schemeId: number): number {
  const size = SIGNATURE_SIZE[schemeId as SingleSchemeId];
  if (size === undefined) {
    throw new Error(`Unknown signature size for scheme ${schemeId}`);
  }
  return size;
}

/**
 * Type guard: returns true if the scheme ID is a composed (hybrid) scheme.
 */
export function isComposedScheme(schemeId: number): schemeId is ComposedSchemeId {
  return schemeId === SchemeId.ECDSA_ETHFALCON || schemeId === SchemeId.ECDSA_MLDSAETH;
}

/**
 * Type guard: returns true if the scheme ID is a single (non-composed) scheme.
 */
export function isSingleScheme(schemeId: number): schemeId is SingleSchemeId {
  return (
    schemeId === SchemeId.ECDSA || schemeId === SchemeId.ETHFALCON || schemeId === SchemeId.MLDSAETH
  );
}

/**
 * Extract the PQ sub-scheme ID from a composed scheme ID.
 * Composed schemes follow the convention: 100 + PQ scheme index.
 * Throws if the scheme is not composed or the derived PQ scheme is unknown.
 */
export function getPQSchemeFromComposed(composedSchemeId: number): SingleSchemeId {
  if (!isComposedScheme(composedSchemeId)) {
    throw new Error(`Scheme ${composedSchemeId} is not a composed scheme`);
  }
  const pqSchemeId = composedSchemeId - 100;
  if (!isSingleScheme(pqSchemeId) || pqSchemeId === SchemeId.ECDSA) {
    throw new Error(
      `Composed scheme ${composedSchemeId} derives invalid PQ sub-scheme ${pqSchemeId}`
    );
  }
  return pqSchemeId;
}
