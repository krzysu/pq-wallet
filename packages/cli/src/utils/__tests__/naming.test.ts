import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { setConfigDir, addAccount } from '../config.js';
import { getUniqueAccountName } from '../naming.js';
import type { AccountConfig } from '../config.js';
import type { Address } from 'viem';

function makeAccount(name: string, keyIndex: number): AccountConfig {
  return {
    name,
    address: `0x${'00'.repeat(19)}${keyIndex.toString(16).padStart(2, '0')}` as Address,
    ecdsaSigner: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd' as Address,
    chain: 'sepolia',
    keyIndex,
    schemes: [0],
    validatorAddress: '0x0000000000000000000000000000000000000001' as Address,
    createdAt: '2025-01-01T00:00:00.000Z',
  };
}

describe('getUniqueAccountName', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await mkdtemp(join(tmpdir(), 'pqwallet-naming-'));
    setConfigDir(tempDir);
  });

  afterEach(async () => {
    setConfigDir(null);
    await rm(tempDir, { recursive: true, force: true });
  });

  it('generates account-1 when no accounts exist', async () => {
    const result = await getUniqueAccountName();
    expect(result).toEqual({ name: 'account-1', wasModified: false });
  });

  it('generates account-2 when one account exists', async () => {
    await addAccount(makeAccount('account-1', 0));
    const result = await getUniqueAccountName();
    expect(result).toEqual({ name: 'account-2', wasModified: false });
  });

  it('uses requested name when available', async () => {
    const result = await getUniqueAccountName('my-wallet');
    expect(result).toEqual({ name: 'my-wallet', wasModified: false });
  });

  it('appends suffix when requested name exists', async () => {
    await addAccount(makeAccount('my-wallet', 0));
    const result = await getUniqueAccountName('my-wallet');
    expect(result).toEqual({ name: 'my-wallet-2', wasModified: true });
  });

  it('increments suffix when name-2 also exists', async () => {
    await addAccount(makeAccount('my-wallet', 0));
    await addAccount(makeAccount('my-wallet-2', 1));
    const result = await getUniqueAccountName('my-wallet');
    expect(result).toEqual({ name: 'my-wallet-3', wasModified: true });
  });

  it('skips existing auto-generated names', async () => {
    await addAccount(makeAccount('account-1', 0));
    await addAccount(makeAccount('account-2', 1));
    const result = await getUniqueAccountName();
    expect(result).toEqual({ name: 'account-3', wasModified: false });
  });
});
