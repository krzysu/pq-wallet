import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { getAddress } from 'viem';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  setConfigDir,
  readConfig,
  writeConfig,
  addAccount,
  getAccountConfig,
  getAllAccountNames,
  getNextKeyIndex,
  isWalletInitialized,
} from '../config.js';
import type { AccountConfig } from '../config.js';
import type { Address } from 'viem';

function makeAccount(overrides: Partial<AccountConfig> = {}): AccountConfig {
  return {
    name: 'test-account',
    address: '0x1234567890abcdef1234567890abcdef12345678' as Address,
    ecdsaSigner: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd' as Address,
    chain: 'sepolia',
    keyIndex: 0,
    schemes: [0, 1, 2, 101, 102],
    validatorAddress: '0x0000000000000000000000000000000000000001' as Address,
    createdAt: '2025-01-01T00:00:00.000Z',
    ...overrides,
  };
}

describe('config management', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await mkdtemp(join(tmpdir(), 'pqwallet-config-'));
    setConfigDir(tempDir);
  });

  afterEach(async () => {
    setConfigDir(null);
    await rm(tempDir, { recursive: true, force: true });
  });

  it('returns default config when file does not exist', async () => {
    const config = await readConfig();
    expect(config.version).toBe('1');
    expect(config.accounts).toEqual([]);
  });

  it('writes and reads config roundtrip', async () => {
    const config = { version: '1', accounts: [], bundlerUrl: 'https://example.com' };
    await writeConfig(config);
    const loaded = await readConfig();
    expect(loaded.bundlerUrl).toBe('https://example.com');
  });

  it('adds an account to config', async () => {
    const account = makeAccount();
    await addAccount(account);
    const config = await readConfig();
    expect(config.accounts).toHaveLength(1);
    expect(config.accounts[0]?.name).toBe('test-account');
  });

  it('adds multiple accounts', async () => {
    await addAccount(makeAccount({ name: 'a1', keyIndex: 0 }));
    await addAccount(makeAccount({ name: 'a2', keyIndex: 1 }));
    const config = await readConfig();
    expect(config.accounts).toHaveLength(2);
  });

  it('gets account by name', async () => {
    await addAccount(makeAccount({ name: 'my-wallet' }));
    const found = await getAccountConfig('my-wallet');
    expect(found?.name).toBe('my-wallet');
  });

  it('gets account by address (case-insensitive)', async () => {
    const address = getAddress('0x1234567890abcdef1234567890abcdef12345678');
    await addAccount(makeAccount({ address }));
    // Look up with lowercase — should still find it
    const found = await getAccountConfig('0x1234567890abcdef1234567890abcdef12345678');
    expect(found?.address).toBe(address);
  });

  it('returns undefined for non-existent account', async () => {
    const found = await getAccountConfig('no-such-account');
    expect(found).toBeUndefined();
  });

  it('gets all account names', async () => {
    await addAccount(makeAccount({ name: 'a1', keyIndex: 0 }));
    await addAccount(makeAccount({ name: 'a2', keyIndex: 1 }));
    const names = await getAllAccountNames();
    expect(names).toEqual(['a1', 'a2']);
  });
});

describe('getNextKeyIndex', () => {
  it('returns 0 for empty accounts', () => {
    expect(getNextKeyIndex({ version: '1', accounts: [] })).toBe(0);
  });

  it('returns max + 1', () => {
    const config = {
      version: '1',
      accounts: [makeAccount({ keyIndex: 0 }), makeAccount({ keyIndex: 3 })],
    };
    expect(getNextKeyIndex(config)).toBe(4);
  });
});

describe('isWalletInitialized', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await mkdtemp(join(tmpdir(), 'pqwallet-init-'));
    setConfigDir(tempDir);
  });

  afterEach(async () => {
    setConfigDir(null);
    await rm(tempDir, { recursive: true, force: true });
  });

  it('returns false when no mnemonic file exists', async () => {
    expect(await isWalletInitialized()).toBe(false);
  });

  it('returns true after mnemonic is saved', async () => {
    const { saveMnemonic } = await import('../mnemonic-storage.js');
    await saveMnemonic('test mnemonic', 'password123');
    expect(await isWalletInitialized()).toBe(true);
  });
});
