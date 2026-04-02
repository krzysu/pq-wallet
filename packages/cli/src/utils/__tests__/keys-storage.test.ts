import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { setConfigDir } from '../config.js';
import { saveKeystores, loadKeystores } from '../keys-storage.js';
import type { DerivedKeys } from '../crypto.js';
import type { Address } from 'viem';

const TEST_PASSWORD = 'test-password-123';
const TEST_ADDRESS = '0x1234567890abcdef1234567890abcdef12345678' as Address;

function makeDerivedKeys(): DerivedKeys {
  return {
    ecdsa: {
      public_key: 'deadbeef',
      secret_key: 'cafebabe',
    },
    ethfalcon: {
      public_key: { value: 'aabbccdd', scheme: 'ETHFALCON' },
      secret_key: { value: 'eeff0011', scheme: 'ETHFALCON' },
    },
    mldsaeth: {
      public_key: { value: '11223344', scheme: 'ML-DSA-65' },
      secret_key: { value: '55667788', scheme: 'ML-DSA-65' },
    },
  };
}

describe('keys storage', () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await mkdtemp(join(tmpdir(), 'pqwallet-keys-'));
    setConfigDir(tempDir);
  });

  afterEach(async () => {
    setConfigDir(null);
    await rm(tempDir, { recursive: true, force: true });
  });

  it('saves and loads keystores roundtrip', async () => {
    const keys = makeDerivedKeys();
    await saveKeystores(keys, TEST_ADDRESS, TEST_PASSWORD);
    const loaded = await loadKeystores(TEST_ADDRESS, TEST_PASSWORD);

    expect(loaded.ecdsaSecretKey).toBe('cafebabe');
    expect(loaded.ethfalconPublicKey).toBe('aabbccdd');
    expect(loaded.ethfalconSecretKey).toBe('eeff0011');
    expect(loaded.mldsaethPublicKey).toBe('11223344');
    expect(loaded.mldsaethSecretKey).toBe('55667788');
  });

  it('fails to load with wrong password', async () => {
    const keys = makeDerivedKeys();
    await saveKeystores(keys, TEST_ADDRESS, TEST_PASSWORD);
    await expect(loadKeystores(TEST_ADDRESS, 'wrong-password')).rejects.toThrow();
  });

  it('fails to load when files do not exist', async () => {
    const fakeAddress = '0xffffffffffffffffffffffffffffffffffffffff' as Address;
    await expect(loadKeystores(fakeAddress, TEST_PASSWORD)).rejects.toThrow();
  });

  it('creates separate files per scheme', async () => {
    const { readdir } = await import('node:fs/promises');
    const keys = makeDerivedKeys();
    await saveKeystores(keys, TEST_ADDRESS, TEST_PASSWORD);

    const keystoresDir = join(tempDir, 'keystores');
    const files = await readdir(keystoresDir);
    expect(files).toHaveLength(3);
    expect(files.sort()).toEqual([
      `ecdsa-${TEST_ADDRESS}.json`,
      `ethfalcon-${TEST_ADDRESS}.json`,
      `mldsaeth-${TEST_ADDRESS}.json`,
    ]);
  });
});
