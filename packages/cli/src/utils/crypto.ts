import { HHDSignatureScheme, FalconScheme } from '@tectonic-labs/bedrock-wasm';
import { getBedrock } from './bedrock.js';
import type { PostQuantumKeypair, EcdsaKeypair } from '@tectonic-labs/bedrock-wasm';

const ALL_HHD_SCHEMES = [
  HHDSignatureScheme.ECDSA_SECP256K1,
  HHDSignatureScheme.FALCON512,
  HHDSignatureScheme.MLDSA65,
];

export interface DerivedKeys {
  ecdsa: EcdsaKeypair;
  ethfalcon: PostQuantumKeypair;
  mldsaeth: PostQuantumKeypair;
}

export function generateMnemonic(): string {
  return getBedrock().generateMnemonic();
}

export function validateMnemonic(mnemonic: string): boolean {
  return getBedrock().validateMnemonic(mnemonic);
}

export function deriveKeysFromMnemonic(mnemonic: string, keyIndex: number): DerivedKeys {
  const bedrock = getBedrock();

  const handle = bedrock.hhdWalletNewFromMnemonic(mnemonic, ALL_HHD_SCHEMES);

  try {
    const ecdsa = bedrock.hhdWalletDeriveEcdsaSecp256k1Keypair(handle, keyIndex);

    // Derive Falcon-512 seed, then generate ETHFALCON keypair from it
    const masterSeeds = bedrock.hhdWalletMasterSeeds(handle);
    const falconSeedHex = masterSeeds[HHDSignatureScheme.FALCON512];
    if (!falconSeedHex) {
      throw new Error('Failed to get Falcon master seed from wallet');
    }

    // Use the HD wallet to derive the Falcon-512 keypair at keyIndex to get deterministic seed
    const falcon512Keypair = bedrock.hhdWalletDeriveFnDsa512Keypair(handle, keyIndex);
    // Generate ETHFALCON keypair from the Falcon-512 secret key seed
    // ETHFALCON needs a 48-byte seed - use the raw Falcon-512 keypair derivation seed
    const ethfalcon = bedrock.generateFnDsaKeypairFromSeed(
      FalconScheme.ETH_FALCON,
      hexToBytes(falcon512Keypair.secret_key.value).slice(0, 48)
    );

    // Derive ML-DSA-65 keypair, then generate MLDSAETH format
    const mldsa65Keypair = bedrock.hhdWalletDeriveMlDsa65(handle, keyIndex);
    // ML-DSA-65 keypair is already in the right format for on-chain verification
    const mldsaeth = mldsa65Keypair;

    return { ecdsa, ethfalcon, mldsaeth };
  } finally {
    bedrock.hhdWalletFree(handle);
  }
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}
