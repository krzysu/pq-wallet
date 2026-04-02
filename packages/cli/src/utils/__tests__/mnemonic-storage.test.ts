import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { setConfigDir } from '../config.js';
import {
  encryptMnemonic,
  decryptMnemonic,
  saveMnemonic,
  loadMnemonic,
} from '../mnemonic-storage.js';

const TEST_MNEMONIC =
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const TEST_PASSWORD = 'test-password-123';

describe('mnemonic encryption', () => {
  it('encrypts and decrypts a mnemonic roundtrip', async () => {
    const encrypted = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    const decrypted = await decryptMnemonic(encrypted, TEST_PASSWORD);
    expect(decrypted).toBe(TEST_MNEMONIC);
  });

  it('produces valid JSON with expected fields', async () => {
    const encrypted = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    const parsed = JSON.parse(encrypted);
    expect(parsed).toHaveProperty('ciphertext');
    expect(parsed).toHaveProperty('iv');
    expect(parsed).toHaveProperty('salt');
    expect(parsed).toHaveProperty('authTag');
  });

  it('produces different ciphertext each time (random salt/iv)', async () => {
    const encrypted1 = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    const encrypted2 = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    expect(encrypted1).not.toBe(encrypted2);
  });

  it('fails to decrypt with wrong password', async () => {
    const encrypted = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    await expect(decryptMnemonic(encrypted, 'wrong-password')).rejects.toThrow();
  });

  it('fails to decrypt with tampered ciphertext', async () => {
    const encrypted = await encryptMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    const parsed = JSON.parse(encrypted);
    parsed.ciphertext = 'ff' + parsed.ciphertext.slice(2);
    await expect(decryptMnemonic(JSON.stringify(parsed), TEST_PASSWORD)).rejects.toThrow();
  });
});

describe('mnemonic file storage', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await mkdtemp(join(tmpdir(), 'pqwallet-test-'));
    setConfigDir(tempDir);
  });

  afterEach(async () => {
    setConfigDir(null);
    await rm(tempDir, { recursive: true, force: true });
  });

  it('saves and loads a mnemonic from disk', async () => {
    await saveMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    const loaded = await loadMnemonic(TEST_PASSWORD);
    expect(loaded).toBe(TEST_MNEMONIC);
  });

  it('fails to load with wrong password', async () => {
    await saveMnemonic(TEST_MNEMONIC, TEST_PASSWORD);
    await expect(loadMnemonic('wrong-password')).rejects.toThrow();
  });

  it('fails to load when no mnemonic file exists', async () => {
    await expect(loadMnemonic(TEST_PASSWORD)).rejects.toThrow();
  });
});
