import type { PQSigner, ComposedSigner } from '../types.js';
import type { toKernelSmartAccount } from './toKernelSmartAccount.js';
import type { Address, Chain, LocalAccount, PublicClient, Transport } from 'viem';

/**
 * Parameters for creating a PQ smart account.
 */
export interface CreatePQAccountParams {
  /** Viem public client for reading blockchain state */
  client: PublicClient<Transport, Chain>;
  /** Chain configuration */
  chain: Chain;
  /** ECDSA owner account (viem LocalAccount) — used as the initial root signer */
  owner: LocalAccount;
  /** Account index for deterministic address derivation (default: 0) */
  index?: bigint;
  /** PQValidator contract address */
  validatorAddress: Address;
  /** Optional PQ signers to configure after account creation */
  pqSigners?: ReadonlyArray<PQSigner>;
  /** Optional composed signers for hybrid schemes */
  composedSigners?: ReadonlyArray<ComposedSigner>;
  /** Override Kernel factory address */
  factoryAddress?: Address;
  /** Override Kernel metaFactory (FactoryStaker) address */
  metaFactoryAddress?: Address;
}

/**
 * Extended smart account with PQ-specific methods.
 * Derived from the actual return type of toKernelSmartAccount.
 */
export type PQSmartAccount = Awaited<ReturnType<typeof toKernelSmartAccount>>;

/**
 * Result of createPQAccount — contains the smart account and metadata.
 */
export interface PQAccount {
  /** The viem SmartAccount with PQ extensions */
  smartAccount: PQSmartAccount;
  /** The smart account's counterfactual address */
  address: Address;
  /** Whether the account is already deployed on-chain */
  isDeployed: boolean;
  /** The ECDSA owner used as root signer */
  owner: LocalAccount;
  /** The PQValidator contract address */
  validatorAddress: Address;
}
