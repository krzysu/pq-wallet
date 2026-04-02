import { readFile, mkdir, open } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { isAddress, isAddressEqual } from 'viem';
import type { SchemeIdType } from '@pq-wallet/sdk';
import type { Address } from 'viem';

export interface AccountConfig {
  name: string;
  address: Address;
  ecdsaSigner: Address;
  chain: string;
  keyIndex: number;
  schemes: SchemeIdType[];
  validatorAddress: Address;
  createdAt: string;
}

export interface Config {
  version: string;
  accounts: AccountConfig[];
  bundlerUrl?: string;
  paymasterUrl?: string;
  validatorAddress?: Address;
  rpcUrl?: string;
  chain?: string;
}

export interface KeystoreFiles {
  ecdsaPath: string;
  ethfalconPath: string;
  mldsaethPath: string;
}

let configDirOverride: string | null = null;

export function setConfigDir(dir: string | null): void {
  configDirOverride = dir;
}

function getConfigDirPath(): string {
  return configDirOverride ?? join(homedir(), '.pq-wallet');
}

export function getConfigDir(): string {
  return getConfigDirPath();
}

export function getConfigFilePath(): string {
  return join(getConfigDirPath(), 'config.json');
}

export function getKeystoresDir(): string {
  return join(getConfigDirPath(), 'keystores');
}

export function getMnemonicPath(): string {
  return join(getConfigDirPath(), 'mnemonic.enc');
}

export async function ensureConfigDir(): Promise<void> {
  await mkdir(getConfigDirPath(), { recursive: true, mode: 0o700 });
  await mkdir(getKeystoresDir(), { recursive: true, mode: 0o700 });
}

export async function writeFileSecure(filePath: string, content: string): Promise<void> {
  const fh = await open(filePath, 'w', 0o600);
  try {
    await fh.writeFile(content, 'utf-8');
  } finally {
    await fh.close();
  }
}

export async function readConfig(): Promise<Config> {
  try {
    const data = await readFile(getConfigFilePath(), 'utf-8');
    return JSON.parse(data) as Config;
  } catch {
    return { version: '1', accounts: [] };
  }
}

export async function writeConfig(config: Config): Promise<void> {
  await ensureConfigDir();
  await writeFileSecure(getConfigFilePath(), JSON.stringify(config, null, 2));
}

export async function addAccount(account: AccountConfig): Promise<void> {
  const config = await readConfig();
  config.accounts.push(account);
  await writeConfig(config);
}

export async function getAccountConfig(nameOrAddress: string): Promise<AccountConfig | undefined> {
  const config = await readConfig();
  return config.accounts.find(
    (acc) =>
      acc.name === nameOrAddress ||
      (isAddress(nameOrAddress) && isAddressEqual(acc.address, nameOrAddress))
  );
}

export async function getAllAccountNames(): Promise<string[]> {
  const config = await readConfig();
  return config.accounts.map((acc) => acc.name);
}

export function getNextKeyIndex(config: Config): number {
  if (config.accounts.length === 0) return 0;
  const maxIndex = Math.max(...config.accounts.map((acc) => acc.keyIndex));
  return maxIndex + 1;
}

export function getKeystoreFilesForAddress(address: Address): KeystoreFiles {
  const dir = getKeystoresDir();
  return {
    ecdsaPath: join(dir, `ecdsa-${address}.json`),
    ethfalconPath: join(dir, `ethfalcon-${address}.json`),
    mldsaethPath: join(dir, `mldsaeth-${address}.json`),
  };
}

export async function isWalletInitialized(): Promise<boolean> {
  try {
    await readFile(getMnemonicPath(), 'utf-8');
    return true;
  } catch {
    return false;
  }
}

export function resolveKeystorePath(address: Address, scheme: string): string {
  return join(getKeystoresDir(), `${scheme}-${address}.json`);
}
