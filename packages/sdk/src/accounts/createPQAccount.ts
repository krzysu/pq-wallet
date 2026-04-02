import { encodeFunctionData, encodeAbiParameters, toHex } from 'viem';
import { kernelFactoryAbi } from '../abis/kernelFactoryAbi.js';
import { kernelV3Abi } from '../abis/kernelV3Abi.js';
import { KERNEL_V3_3, NO_HOOK } from '../constants.js';
import { toKernelSmartAccount } from './toKernelSmartAccount.js';
import { buildRootValidationId } from './validationId.js';
import type { CreatePQAccountParams, PQAccount } from './types.js';

/**
 * Create a PQ Wallet smart account.
 *
 * This creates a Kernel v3.3 account with PQValidator as the root validator.
 * The account starts with ECDSA signing and can be upgraded to PQ schemes
 * via registerPublicKey + setSchemeAllowed.
 *
 * @example
 * ```ts
 * import { createPQAccount } from '@pq-wallet/sdk';
 * import { privateKeyToAccount } from 'viem/accounts';
 * import { sepolia } from 'viem/chains';
 *
 * const owner = privateKeyToAccount('0x...');
 * const account = await createPQAccount({
 *   client: publicClient,
 *   chain: sepolia,
 *   owner,
 *   validatorAddress: '0x...',
 * });
 * ```
 */
export async function createPQAccount(params: CreatePQAccountParams): Promise<PQAccount> {
  const {
    client,
    chain,
    owner,
    index = 0n,
    validatorAddress,
    pqSigners = [],
    composedSigners = [],
    factoryAddress = KERNEL_V3_3.factory,
    metaFactoryAddress = KERNEL_V3_3.metaFactory,
  } = params;

  const salt = toHex(index, { size: 32 });

  // Build the initialize calldata to predict the account address
  const validatorInitData = encodeAbiParameters(
    [{ type: 'address', name: 'owner' }],
    [owner.address]
  );

  const initializeData = encodeFunctionData({
    abi: kernelV3Abi,
    functionName: 'initialize',
    args: [buildRootValidationId(validatorAddress), NO_HOOK, validatorInitData, '0x', []],
  });

  // Predict account address via factory's getAddress
  const accountAddress = await client.readContract({
    address: factoryAddress,
    abi: kernelFactoryAbi,
    functionName: 'getAddress',
    args: [initializeData, salt],
  });

  // Check if already deployed
  const code = await client.getCode({ address: accountAddress });
  const isDeployed = code !== undefined && code !== '0x';

  // Create the smart account
  const smartAccount = await toKernelSmartAccount({
    client,
    chain,
    owner,
    validatorAddress,
    salt,
    factoryAddress,
    metaFactoryAddress,
    accountAddress,
    pqSigners,
    composedSigners,
  });

  return {
    smartAccount,
    address: accountAddress,
    isDeployed,
    owner,
    validatorAddress,
  };
}
