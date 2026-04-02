import { createBundlerClient } from 'viem/account-abstraction';
import { SchemeId } from '../constants.js';
import type { PQAccount } from '../accounts/types.js';
import type { SchemeIdType } from '../types.js';
import type { PublicClient, Transport, Chain, SignableMessage, TypedDataDefinition } from 'viem';
import type {
  PaymasterClient,
  SendUserOperationParameters,
  BundlerClient,
} from 'viem/account-abstraction';

/**
 * Async mutex to serialize signing operations.
 * Prevents race conditions when concurrent operations
 * change the shared scheme state.
 */
class SigningMutex {
  private queue: Array<() => void> = [];
  private locked = false;

  async acquire(): Promise<() => void> {
    if (!this.locked) {
      this.locked = true;
      return () => {
        this.release();
      };
    }
    return new Promise((resolve) => {
      this.queue.push(() => {
        resolve(() => {
          this.release();
        });
      });
    });
  }

  private release(): void {
    const next = this.queue.shift();
    if (next) {
      next();
    } else {
      this.locked = false;
    }
  }
}

/**
 * Options for operations that involve signing.
 */
export interface SigningOptions {
  /** Override the default scheme for this operation */
  schemeId?: SchemeIdType;
}

/**
 * Options for sendUserOperation.
 */
export type SendUserOperationOptions = SigningOptions;

/**
 * PQ Wallet bundler client with per-operation scheme selection.
 */
export interface PQClient {
  /** The underlying viem BundlerClient */
  bundlerClient: BundlerClient;
  /** Send a UserOperation with optional scheme override */
  sendUserOperation(
    params: SendUserOperationParameters,
    options?: SendUserOperationOptions
  ): Promise<`0x${string}`>;
  /** Set the default signing scheme */
  setDefaultScheme(schemeId: SchemeIdType): Promise<void>;
  /** Get the current default signing scheme */
  getDefaultScheme(): SchemeIdType;
  /** Sign a message with optional scheme override */
  signMessage(message: SignableMessage, options?: SigningOptions): Promise<`0x${string}`>;
  /** Sign typed data with optional scheme override */
  signTypedData(typedData: TypedDataDefinition, options?: SigningOptions): Promise<`0x${string}`>;
}

export interface CreatePQClientParams {
  /** PQ account from createPQAccount */
  account: PQAccount;
  /** Viem PublicClient for reading blockchain state */
  client: PublicClient<Transport, Chain>;
  /** Transport for bundler RPC */
  transport: Transport;
  /** Enable paymaster for gas sponsorship */
  paymaster?: true | PaymasterClient;
}

/**
 * Create a PQ Wallet bundler client.
 *
 * Wraps viem's BundlerClient with:
 * - Per-operation scheme selection via options
 * - Signing mutex for concurrent operation safety
 */
export function createPQClient(params: CreatePQClientParams): PQClient {
  const { account, client, transport, paymaster } = params;

  const bundlerClient = createBundlerClient({
    account: account.smartAccount,
    client,
    transport,
    paymaster,
  });

  let defaultScheme: SchemeIdType = SchemeId.ECDSA;
  const signingMutex = new SigningMutex();

  return {
    bundlerClient,

    async sendUserOperation(
      params: SendUserOperationParameters,
      options?: SendUserOperationOptions
    ) {
      const schemeId = options?.schemeId ?? defaultScheme;

      const release = await signingMutex.acquire();
      try {
        account.smartAccount.setScheme(schemeId);
        return await bundlerClient.sendUserOperation(params);
      } finally {
        release();
      }
    },

    async setDefaultScheme(schemeId: SchemeIdType) {
      const release = await signingMutex.acquire();
      try {
        defaultScheme = schemeId;
        account.smartAccount.setScheme(schemeId);
      } finally {
        release();
      }
    },

    getDefaultScheme(): SchemeIdType {
      return defaultScheme;
    },

    async signMessage(message: SignableMessage, options?: SigningOptions) {
      const schemeId = options?.schemeId ?? defaultScheme;
      const release = await signingMutex.acquire();
      try {
        account.smartAccount.setScheme(schemeId);
        return await account.smartAccount.signMessage({ message });
      } finally {
        release();
      }
    },

    async signTypedData(typedData: TypedDataDefinition, options?: SigningOptions) {
      const schemeId = options?.schemeId ?? defaultScheme;
      const release = await signingMutex.acquire();
      try {
        account.smartAccount.setScheme(schemeId);
        return await account.smartAccount.signTypedData(typedData);
      } finally {
        release();
      }
    },
  };
}
