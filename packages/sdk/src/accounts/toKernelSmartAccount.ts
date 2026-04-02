import {
  encodeFunctionData,
  encodeAbiParameters,
  getContract,
  hashMessage,
  hashTypedData,
  toHex,
  type Address,
  type Chain,
  type Hex,
  type LocalAccount,
  type PublicClient,
  type Transport,
} from 'viem';
import { toSmartAccount, getUserOperationHash } from 'viem/account-abstraction';
import { factoryStakerAbi } from '../abis/factoryStakerAbi.js';
import { kernelV3Abi } from '../abis/kernelV3Abi.js';
import {
  ENTRY_POINT,
  KERNEL_V3_3,
  NO_HOOK,
  SchemeId,
  getSignatureSize,
  getPQSchemeFromComposed,
} from '../constants.js';
import {
  encodeEcdsaSignature,
  encodePQSignature,
  encodeComposedSignature,
  computeKeyId,
  computeEcdsaKeyId,
  computeComposedKeyId,
  wrapHashForERC1271,
  wrapSignatureWithValidationId,
} from '../signatures/index.js';
import { encodeCalls } from './encodeCalls.js';
import { buildRootValidationId } from './validationId.js';
import type { PQSigner, ComposedSigner, SchemeIdType } from '../types.js';

export interface ToKernelSmartAccountParams {
  client: PublicClient<Transport, Chain>;
  chain: Chain;
  owner: LocalAccount;
  validatorAddress: Address;
  salt: Hex;
  factoryAddress?: Address;
  metaFactoryAddress?: Address;
  accountAddress: Address;
  pqSigners?: ReadonlyArray<PQSigner>;
  composedSigners?: ReadonlyArray<ComposedSigner>;
}

/**
 * Create a Kernel v3.3 SmartAccount with PQValidator as root validator.
 * Uses viem's `toSmartAccount` primitive — no ZeroDev SDK dependency.
 */
export async function toKernelSmartAccount(params: ToKernelSmartAccountParams) {
  const {
    client,
    chain,
    owner,
    validatorAddress,
    salt,
    factoryAddress = KERNEL_V3_3.factory,
    metaFactoryAddress = KERNEL_V3_3.metaFactory,
    accountAddress,
    pqSigners = [],
    composedSigners = [],
  } = params;

  // Current signing scheme — ECDSA by default
  let currentSchemeId: SchemeIdType = SchemeId.ECDSA;

  // Build PQ signer lookup with computed keyIds
  interface ResolvedPQSigner extends PQSigner {
    readonly keyId: Hex;
  }
  interface ResolvedComposedSigner extends ComposedSigner {
    readonly keyId: Hex;
  }
  const pqSignerMap = new Map<number, ResolvedPQSigner>();
  for (const signer of pqSigners) {
    const keyId = computeKeyId(signer.publicKey);
    pqSignerMap.set(signer.scheme, { ...signer, keyId });
  }
  const ecdsaKeyId = computeEcdsaKeyId(owner.address);
  const composedSignerMap = new Map<number, ResolvedComposedSigner>();
  for (const signer of composedSigners) {
    // Composed schemes pair ECDSA (signerA) with a PQ scheme (signerB).
    const pqSchemeId = getPQSchemeFromComposed(signer.scheme);
    const pqSigner = pqSignerMap.get(pqSchemeId);
    if (!pqSigner) {
      throw new Error(
        `Composed signer for scheme ${signer.scheme} requires a PQ signer for scheme ${pqSchemeId}`
      );
    }
    const keyId = computeComposedKeyId(ecdsaKeyId, pqSigner.keyId);
    composedSignerMap.set(signer.scheme, { ...signer, keyId });
  }

  // Build Kernel initialize calldata
  // PQValidator.onInstall expects: abi.encode(ownerAddress)
  const validatorInitData = encodeAbiParameters(
    [{ type: 'address', name: 'owner' }],
    [owner.address]
  );

  const initializeData = encodeFunctionData({
    abi: kernelV3Abi,
    functionName: 'initialize',
    args: [buildRootValidationId(validatorAddress), NO_HOOK, validatorInitData, '0x', []],
  });

  // Build factory calldata via FactoryStaker.deployWithFactory
  const factoryCalldata = encodeFunctionData({
    abi: factoryStakerAbi,
    functionName: 'deployWithFactory',
    args: [factoryAddress, initializeData, salt],
  });

  /**
   * Sign a hash with the currently active scheme.
   */
  async function signHash(hash: Hex): Promise<Hex> {
    // ECDSA fast path — raw 65-byte signature
    if (currentSchemeId === SchemeId.ECDSA) {
      const sig = await owner.signMessage({ message: { raw: hash } });
      return encodeEcdsaSignature(sig);
    }

    // Composed/hybrid schemes
    const composedSigner = composedSignerMap.get(currentSchemeId);
    if (composedSigner) {
      const [sigA, sigB] = await Promise.all([
        composedSigner.signerA.sign(hash),
        composedSigner.signerB.sign(hash),
      ]);
      return encodeComposedSignature(currentSchemeId, sigA, sigB, composedSigner.keyId);
    }

    // Single PQ scheme
    const pqSigner = pqSignerMap.get(currentSchemeId);
    if (pqSigner) {
      const innerSig = await pqSigner.sign(hash);
      return encodePQSignature(currentSchemeId, innerSig, pqSigner.keyId);
    }

    throw new Error(`No signer configured for scheme ${currentSchemeId}`);
  }

  /**
   * Build a dummy Hex of the given byte length.
   * Used for gas estimation stub signatures — content doesn't matter, only size.
   */
  function dummyHex(byteLength: number): Hex {
    return toHex(new Uint8Array(byteLength).fill(0xff));
  }

  /**
   * Get a stub signature for gas estimation.
   * Must match the size of a real signature for the current scheme.
   */
  function getStubSignature(): Hex {
    // ECDSA: 65-byte dummy signature
    if (currentSchemeId === SchemeId.ECDSA) {
      return dummyHex(getSignatureSize(SchemeId.ECDSA));
    }

    // For PQ and composed schemes, use the ABI-encoded format with dummy data.
    // The key insight: gas estimation needs the correct ABI structure and length,
    // not valid cryptographic content.
    const composedSigner = composedSignerMap.get(currentSchemeId);
    if (composedSigner) {
      const pqSchemeId = getPQSchemeFromComposed(currentSchemeId);
      return encodeComposedSignature(
        currentSchemeId,
        dummyHex(getSignatureSize(SchemeId.ECDSA)),
        dummyHex(getSignatureSize(pqSchemeId)),
        composedSigner.keyId
      );
    }

    const pqSigner = pqSignerMap.get(currentSchemeId);
    if (pqSigner) {
      return encodePQSignature(
        currentSchemeId,
        dummyHex(getSignatureSize(currentSchemeId)),
        pqSigner.keyId
      );
    }

    throw new Error(`No signer configured for scheme ${currentSchemeId}`);
  }

  // Create smart account via viem's primitive, with PQ-specific methods via extend
  const smartAccount = await toSmartAccount({
    client,
    entryPoint: ENTRY_POINT,
    extend: {
      setScheme(schemeId: SchemeIdType) {
        currentSchemeId = schemeId;
      },
      getScheme(): SchemeIdType {
        return currentSchemeId;
      },
    },

    getAddress() {
      return Promise.resolve(accountAddress);
    },

    async encodeCalls(calls) {
      return encodeCalls(calls);
    },

    async getNonce(parameters) {
      const key = parameters?.key ?? 0n;
      const entryPointContract = getContract({
        address: ENTRY_POINT.address,
        abi: ENTRY_POINT.abi,
        client,
      });

      return entryPointContract.read.getNonce([accountAddress, key]);
    },

    getFactoryArgs() {
      return Promise.resolve({
        factory: metaFactoryAddress,
        factoryData: factoryCalldata,
      });
    },

    async getStubSignature() {
      return getStubSignature();
    },

    async signMessage({ message }) {
      const messageHash = hashMessage(message);
      const wrappedHash = wrapHashForERC1271(messageHash, accountAddress, chain.id);
      const sig = await signHash(wrappedHash);
      return wrapSignatureWithValidationId(sig, validatorAddress);
    },

    async signTypedData(typedData) {
      const typedDataHash = hashTypedData(typedData);
      const wrappedHash = wrapHashForERC1271(typedDataHash, accountAddress, chain.id);
      const sig = await signHash(wrappedHash);
      return wrapSignatureWithValidationId(sig, validatorAddress);
    },

    async signUserOperation(userOperation) {
      const hash = getUserOperationHash({
        userOperation: {
          ...userOperation,
          signature: '0x',
          sender: userOperation.sender ?? accountAddress,
        },
        entryPointAddress: ENTRY_POINT.address,
        entryPointVersion: ENTRY_POINT.version,
        chainId: chain.id,
      });

      return signHash(hash);
    },
  });

  return smartAccount;
}
