import { randomBytes, createCipheriv, createDecipheriv, pbkdf2 } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { ensureConfigDir, getKeystoreFilesForAddress, writeFileSecure } from './config.js';
import type { DerivedKeys } from './crypto.js';
import type { Address } from 'viem';

const pbkdf2Async = promisify(pbkdf2);

const ALGORITHM = 'aes-256-gcm';
const KEY_LENGTH = 32;
const IV_LENGTH = 16;
const SALT_LENGTH = 32;
const PBKDF2_ITERATIONS = 600000;
const PBKDF2_DIGEST = 'sha256';

interface EncryptedKeystore {
  ciphertext: string;
  iv: string;
  salt: string;
  authTag: string;
  scheme: string;
}

async function encryptKeystore(data: string, password: string, scheme: string): Promise<string> {
  const salt = randomBytes(SALT_LENGTH);
  const iv = randomBytes(IV_LENGTH);
  const key = await pbkdf2Async(password, salt, PBKDF2_ITERATIONS, KEY_LENGTH, PBKDF2_DIGEST);

  try {
    const cipher = createCipheriv(ALGORITHM, key, iv);
    const encrypted = Buffer.concat([cipher.update(data, 'utf-8'), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const keystore: EncryptedKeystore = {
      ciphertext: encrypted.toString('hex'),
      iv: iv.toString('hex'),
      salt: salt.toString('hex'),
      authTag: authTag.toString('hex'),
      scheme,
    };

    return JSON.stringify(keystore, null, 2);
  } finally {
    key.fill(0);
  }
}

async function decryptKeystore(encryptedJson: string, password: string): Promise<string> {
  const keystore: EncryptedKeystore = JSON.parse(encryptedJson);

  const salt = Buffer.from(keystore.salt, 'hex');
  const iv = Buffer.from(keystore.iv, 'hex');
  const authTag = Buffer.from(keystore.authTag, 'hex');
  const ciphertext = Buffer.from(keystore.ciphertext, 'hex');

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

export async function saveKeystores(
  keys: DerivedKeys,
  address: Address,
  password: string
): Promise<void> {
  await ensureConfigDir();
  const paths = getKeystoreFilesForAddress(address);

  const ecdsaData = JSON.stringify({ secret_key: keys.ecdsa.secret_key });
  const ethfalconData = JSON.stringify({
    public_key: keys.ethfalcon.public_key,
    secret_key: keys.ethfalcon.secret_key,
  });
  const mldsaethData = JSON.stringify({
    public_key: keys.mldsaeth.public_key,
    secret_key: keys.mldsaeth.secret_key,
  });

  const [ecdsaEnc, ethfalconEnc, mldsaethEnc] = await Promise.all([
    encryptKeystore(ecdsaData, password, 'ecdsa'),
    encryptKeystore(ethfalconData, password, 'ethfalcon'),
    encryptKeystore(mldsaethData, password, 'mldsaeth'),
  ]);

  await Promise.all([
    writeFileSecure(paths.ecdsaPath, ecdsaEnc),
    writeFileSecure(paths.ethfalconPath, ethfalconEnc),
    writeFileSecure(paths.mldsaethPath, mldsaethEnc),
  ]);
}

export interface LoadedKeys {
  ecdsaSecretKey: string;
  ethfalconPublicKey: string;
  ethfalconSecretKey: string;
  mldsaethPublicKey: string;
  mldsaethSecretKey: string;
}

export async function loadKeystores(address: Address, password: string): Promise<LoadedKeys> {
  const paths = getKeystoreFilesForAddress(address);

  const [ecdsaEnc, ethfalconEnc, mldsaethEnc] = await Promise.all([
    readFile(paths.ecdsaPath, 'utf-8'),
    readFile(paths.ethfalconPath, 'utf-8'),
    readFile(paths.mldsaethPath, 'utf-8'),
  ]);

  const [ecdsaJson, ethfalconJson, mldsaethJson] = await Promise.all([
    decryptKeystore(ecdsaEnc, password),
    decryptKeystore(ethfalconEnc, password),
    decryptKeystore(mldsaethEnc, password),
  ]);

  const ecdsa = JSON.parse(ecdsaJson) as { secret_key: string };
  const ethfalcon = JSON.parse(ethfalconJson) as {
    public_key: { value: string; scheme: string };
    secret_key: { value: string; scheme: string };
  };
  const mldsaeth = JSON.parse(mldsaethJson) as {
    public_key: { value: string; scheme: string };
    secret_key: { value: string; scheme: string };
  };

  return {
    ecdsaSecretKey: ecdsa.secret_key,
    ethfalconPublicKey: ethfalcon.public_key.value,
    ethfalconSecretKey: ethfalcon.secret_key.value,
    mldsaethPublicKey: mldsaeth.public_key.value,
    mldsaethSecretKey: mldsaeth.secret_key.value,
  };
}
