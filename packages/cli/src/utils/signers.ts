import { SchemeId } from '@pq-wallet/sdk';
import { toHex, type Hex, type LocalAccount } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import type { PQSigner, ComposedSigner, SchemeIdType } from '@pq-wallet/sdk';
import { getBedrock } from './bedrock.js';
import type { LoadedKeys } from './keys-storage.js';
import type { PostQuantumKey } from '@tectonic-labs/bedrock-wasm';

export function createLocalAccount(ecdsaSecretKey: string): LocalAccount {
  const key: Hex = ecdsaSecretKey.startsWith('0x')
    ? (ecdsaSecretKey as Hex)
    : `0x${ecdsaSecretKey}`;
  return privateKeyToAccount(key);
}

export function createEthfalconSigner(publicKeyHex: string, secretKeyValue: string): PQSigner {
  const bedrock = getBedrock();
  const solidityKey = bedrock.toEthFalconVerifyingKey({
    value: publicKeyHex,
    scheme: 'ETHFALCON',
  });

  const publicKey = toHex(solidityKey);

  const secretKey: PostQuantumKey = {
    value: secretKeyValue,
    scheme: 'ETHFALCON',
  };

  return {
    scheme: SchemeId.ETHFALCON,
    publicKey,
    async sign(hash: Hex): Promise<Hex> {
      const messageBytes = hexToUint8Array(hash);
      const signature = bedrock.signFnDsa(secretKey, messageBytes);
      const soliditySig = bedrock.toEthFalconSignature(signature);
      return toHex(soliditySig);
    },
  };
}

export function createMldsaethSigner(publicKeyHex: string, secretKeyValue: string): PQSigner {
  const bedrock = getBedrock();

  const publicKey: Hex = `0x${publicKeyHex}`;

  const secretKey: PostQuantumKey = {
    value: secretKeyValue,
    scheme: 'ML-DSA-65',
  };

  return {
    scheme: SchemeId.MLDSAETH,
    publicKey,
    async sign(hash: Hex): Promise<Hex> {
      const messageBytes = hexToUint8Array(hash);
      const signature = bedrock.signMlDsa(secretKey, messageBytes);
      const result: Hex = `0x${signature.value}`;
      return result;
    },
  };
}

export function createComposedEcdsaEthfalconSigner(
  owner: LocalAccount,
  ethfalconSigner: PQSigner
): ComposedSigner {
  return {
    scheme: SchemeId.ECDSA_ETHFALCON,
    signerA: {
      async sign(hash: Hex): Promise<Hex> {
        return owner.signMessage({ message: { raw: hash } });
      },
    },
    signerB: {
      async sign(hash: Hex): Promise<Hex> {
        return ethfalconSigner.sign(hash);
      },
    },
  };
}

export function createComposedEcdsaMldsaethSigner(
  owner: LocalAccount,
  mldsaethSigner: PQSigner
): ComposedSigner {
  return {
    scheme: SchemeId.ECDSA_MLDSAETH,
    signerA: {
      async sign(hash: Hex): Promise<Hex> {
        return owner.signMessage({ message: { raw: hash } });
      },
    },
    signerB: {
      async sign(hash: Hex): Promise<Hex> {
        return mldsaethSigner.sign(hash);
      },
    },
  };
}

export function buildSignersFromKeys(keys: LoadedKeys): {
  owner: LocalAccount;
  pqSigners: PQSigner[];
  composedSigners: ComposedSigner[];
} {
  const owner = createLocalAccount(keys.ecdsaSecretKey);
  const ethfalconSigner = createEthfalconSigner(keys.ethfalconPublicKey, keys.ethfalconSecretKey);
  const mldsaethSigner = createMldsaethSigner(keys.mldsaethPublicKey, keys.mldsaethSecretKey);

  const composedEcdsaEthfalcon = createComposedEcdsaEthfalconSigner(owner, ethfalconSigner);
  const composedEcdsaMldsaeth = createComposedEcdsaMldsaethSigner(owner, mldsaethSigner);

  return {
    owner,
    pqSigners: [ethfalconSigner, mldsaethSigner],
    composedSigners: [composedEcdsaEthfalcon, composedEcdsaMldsaeth],
  };
}

function hexToUint8Array(hex: Hex): Uint8Array {
  const clean = hex.slice(2);
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

export function formatSchemeId(schemeId: SchemeIdType): string {
  switch (schemeId) {
    case SchemeId.ECDSA:
      return 'ECDSA';
    case SchemeId.ETHFALCON:
      return 'ETHFALCON';
    case SchemeId.MLDSAETH:
      return 'MLDSAETH';
    case SchemeId.ECDSA_ETHFALCON:
      return 'ECDSA+ETHFALCON';
    case SchemeId.ECDSA_MLDSAETH:
      return 'ECDSA+MLDSAETH';
    default:
      return `Unknown(${String(schemeId)})`;
  }
}
