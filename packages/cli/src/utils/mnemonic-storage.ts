import { randomBytes, createCipheriv, createDecipheriv, pbkdf2 } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { ensureConfigDir, getMnemonicPath, writeFileSecure } from './config.js';

const pbkdf2Async = promisify(pbkdf2);

const ALGORITHM = 'aes-256-gcm';
const KEY_LENGTH = 32;
const IV_LENGTH = 16;
const SALT_LENGTH = 32;
const PBKDF2_ITERATIONS = 600000;
const PBKDF2_DIGEST = 'sha256';

interface EncryptedMnemonic {
  ciphertext: string;
  iv: string;
  salt: string;
  authTag: string;
}

export async function encryptMnemonic(mnemonic: string, password: string): Promise<string> {
  const salt = randomBytes(SALT_LENGTH);
  const iv = randomBytes(IV_LENGTH);

  const key = await pbkdf2Async(password, salt, PBKDF2_ITERATIONS, KEY_LENGTH, PBKDF2_DIGEST);

  try {
    const cipher = createCipheriv(ALGORITHM, key, iv);
    const encrypted = Buffer.concat([cipher.update(mnemonic, 'utf-8'), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const data: EncryptedMnemonic = {
      ciphertext: encrypted.toString('hex'),
      iv: iv.toString('hex'),
      salt: salt.toString('hex'),
      authTag: authTag.toString('hex'),
    };

    return JSON.stringify(data, null, 2);
  } finally {
    key.fill(0);
  }
}

export async function decryptMnemonic(encryptedJson: string, password: string): Promise<string> {
  const data: EncryptedMnemonic = JSON.parse(encryptedJson);

  const salt = Buffer.from(data.salt, 'hex');
  const iv = Buffer.from(data.iv, 'hex');
  const authTag = Buffer.from(data.authTag, 'hex');
  const ciphertext = Buffer.from(data.ciphertext, 'hex');

  const key = await pbkdf2Async(password, salt, PBKDF2_ITERATIONS, KEY_LENGTH, PBKDF2_DIGEST);

  try {
    const decipher = createDecipheriv(ALGORITHM, key, iv);
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return decrypted.toString('utf-8');
  } finally {
    key.fill(0);
  }
}

export async function saveMnemonic(mnemonic: string, password: string): Promise<void> {
  const encrypted = await encryptMnemonic(mnemonic, password);
  await ensureConfigDir();
  await writeFileSecure(getMnemonicPath(), encrypted);
}

export async function loadMnemonic(password: string): Promise<string> {
  const encrypted = await readFile(getMnemonicPath(), 'utf-8');
  return decryptMnemonic(encrypted, password);
}
