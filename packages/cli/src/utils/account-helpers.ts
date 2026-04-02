import { createPQAccount, createPQClient } from '@pq-wallet/sdk';
import { createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';
import type { PQAccount, PQClient } from '@pq-wallet/sdk';
import { getAccountConfig, readConfig } from './config.js';
import { loadKeystores } from './keys-storage.js';
import { buildSignersFromKeys } from './signers.js';
import type { AccountConfig } from './config.js';
import type { Address, Chain, PublicClient, Transport } from 'viem';

const SUPPORTED_CHAINS: Record<string, Chain> = {
  sepolia,
};

export function getChain(name: string): Chain {
  const chain = SUPPORTED_CHAINS[name];
  if (!chain) {
    throw new Error(
      `Unsupported chain: ${name}. Supported: ${Object.keys(SUPPORTED_CHAINS).join(', ')}`
    );
  }
  return chain;
}

export function validateChain(name: string): void {
  getChain(name);
}

export function createRpcClient(chain: Chain, rpcUrl?: string): PublicClient<Transport, Chain> {
  return createPublicClient({
    chain,
    transport: http(rpcUrl),
  });
}

export async function getRequiredConfig(): Promise<{
  bundlerUrl: string;
  validatorAddress: Address;
  chain: Chain;
  rpcUrl?: string;
  paymasterUrl?: string;
}> {
  const config = await readConfig();

  if (!config.bundlerUrl) {
    throw new Error('Bundler URL not configured. Run: pqwallet configure --bundler-url <url>');
  }
  if (!config.validatorAddress) {
    throw new Error(
      'Validator address not configured. Run: pqwallet configure --validator-address <address>'
    );
  }

  const chainName = config.chain ?? 'sepolia';
  const chain = getChain(chainName);

  return {
    bundlerUrl: config.bundlerUrl,
    validatorAddress: config.validatorAddress,
    chain,
    rpcUrl: config.rpcUrl,
    paymasterUrl: config.paymasterUrl,
  };
}

export async function setupAccount(
  nameOrAddress: string,
  password: string
): Promise<{
  account: PQAccount;
  accountConfig: AccountConfig;
  chain: Chain;
  publicClient: PublicClient<Transport, Chain>;
}> {
  const accountConfig = await getAccountConfig(nameOrAddress);
  if (!accountConfig) {
    throw new Error(`Account "${nameOrAddress}" not found. Run: pqwallet list`);
  }

  const { validatorAddress, chain, rpcUrl } = await getRequiredConfig();

  const publicClient = createRpcClient(chain, rpcUrl);

  const keys = await loadKeystores(accountConfig.address, password);
  const { owner, pqSigners, composedSigners } = buildSignersFromKeys(keys);

  const account = await createPQAccount({
    client: publicClient,
    chain,
    owner,
    index: BigInt(accountConfig.keyIndex),
    validatorAddress,
    pqSigners,
    composedSigners,
  });

  return { account, accountConfig, chain, publicClient };
}

export function createAccountClient(
  account: PQAccount,
  publicClient: PublicClient<Transport, Chain>,
  bundlerUrl: string,
  paymasterUrl?: string
): PQClient {
  return createPQClient({
    account,
    client: publicClient,
    transport: http(bundlerUrl),
    paymaster: paymasterUrl ? true : undefined,
  });
}
