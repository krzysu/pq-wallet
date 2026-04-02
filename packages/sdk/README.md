# @pq-wallet/sdk

Client library for creating and managing quantum-secure smart accounts on Ethereum and EVM chains.

Built on [viem](https://viem.sh) and [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337). Uses ZeroDev Kernel v3.3 with a custom PQValidator module for post-quantum signature verification.

## Install

```bash
pnpm add @pq-wallet/sdk viem
```

`viem` is a peer dependency (`^2.0.0`).

## Quick start

```ts
import { createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import { createPQAccount, createPQClient, SchemeId } from '@pq-wallet/sdk';

// 1. Set up a viem public client
const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(),
});

// 2. Create the smart account (starts with ECDSA signing)
const owner = privateKeyToAccount('0x...');
const account = await createPQAccount({
  client: publicClient,
  chain: sepolia,
  owner,
  validatorAddress: '0x...', // deployed PQValidator address
});

// 3. Create a bundler client for sending UserOperations
const pqClient = createPQClient({
  account,
  client: publicClient,
  transport: http('https://your-bundler-rpc'),
});

// 4. Send a UserOperation
const hash = await pqClient.sendUserOperation({
  calls: [{ to: '0x...', value: 1000n }],
});
```

## API reference

### Account creation

#### `createPQAccount(params): Promise<PQAccount>`

Creates a Kernel v3.3 smart account with PQValidator as the root validator. Predicts the counterfactual address and checks deployment status.

```ts
const account = await createPQAccount({
  client, // PublicClient<Transport, Chain>
  chain, // Chain (e.g., sepolia)
  owner, // LocalAccount - ECDSA signer
  validatorAddress, // Address - deployed PQValidator
  index, // bigint (default: 0n) - for deterministic address derivation
  pqSigners, // PQSigner[] (optional) - PQ signing implementations
  composedSigners, // ComposedSigner[] (optional) - hybrid signing implementations
  factoryAddress, // Address (optional) - override Kernel factory
  metaFactoryAddress, // Address (optional) - override FactoryStaker
});
```

Returns a `PQAccount`:

| Field              | Type             | Description                              |
| ------------------ | ---------------- | ---------------------------------------- |
| `smartAccount`     | `PQSmartAccount` | viem SmartAccount with PQ extensions     |
| `address`          | `Address`        | Counterfactual smart account address     |
| `isDeployed`       | `boolean`        | Whether the account is deployed on-chain |
| `owner`            | `LocalAccount`   | The ECDSA owner                          |
| `validatorAddress` | `Address`        | PQValidator contract address             |

### Client

#### `createPQClient(params): PQClient`

Creates a bundler client wrapping viem's `BundlerClient` with per-operation scheme selection and a signing mutex for concurrency safety.

```ts
const pqClient = createPQClient({
  account, // PQAccount from createPQAccount
  client, // PublicClient<Transport, Chain>
  transport, // Transport for bundler RPC
  paymaster, // true | PaymasterClient (optional)
});
```

#### `PQClient` methods

| Method                                | Description                                                |
| ------------------------------------- | ---------------------------------------------------------- |
| `sendUserOperation(params, options?)` | Send a UserOperation. Accepts `{ schemeId }` override.     |
| `signMessage(message, options?)`      | Sign an ERC-1271 message. Accepts `{ schemeId }` override. |
| `signTypedData(typedData, options?)`  | Sign EIP-712 typed data. Accepts `{ schemeId }` override.  |
| `setDefaultScheme(schemeId)`          | Change the default signing scheme (async, mutex-guarded).  |
| `getDefaultScheme()`                  | Get the current default signing scheme.                    |
| `bundlerClient`                       | Access the underlying viem `BundlerClient`.                |

### Signature schemes

The `SchemeId` constant maps scheme names to their on-chain identifiers:

| Scheme            | ID    | Description                     |
| ----------------- | ----- | ------------------------------- |
| `ECDSA`           | `0`   | Standard ECDSA (default)        |
| `ETHFALCON`       | `1`   | ETHFALCON post-quantum          |
| `MLDSAETH`        | `2`   | MLD-SA (Dilithium) post-quantum |
| `ECDSA_ETHFALCON` | `101` | Hybrid ECDSA + ETHFALCON        |
| `ECDSA_MLDSAETH`  | `102` | Hybrid ECDSA + MLD-SA           |

### Custom signers

The SDK does not bundle post-quantum cryptography. You provide signing implementations via the `PQSigner` and `ComposedSigner` interfaces.

#### `PQSigner`

For single PQ schemes (ETHFALCON, MLDSAETH):

```ts
const falconSigner: PQSigner = {
  scheme: SchemeId.ETHFALCON,
  publicKey: '0x...', // 1024 bytes for ETHFALCON
  async sign(hash) {
    return signWithFalcon(hash); // your PQ signing implementation
  },
};
```

#### `ComposedSigner`

For hybrid schemes (ECDSA + PQ):

```ts
const composedSigner: ComposedSigner = {
  scheme: SchemeId.ECDSA_ETHFALCON,
  signerA: { sign: (hash) => ecdsaSign(hash) },
  signerB: { sign: (hash) => falconSign(hash) },
};
```

Note: `ComposedSigner` requires a matching `PQSigner` in `pqSigners` for the PQ sub-scheme (e.g., an ETHFALCON signer for `ECDSA_ETHFALCON`). The SDK derives the composed keyId automatically from the owner address and the PQ signer's public key.

### Key ID helpers

Compute key identifiers matching the on-chain `keccak256` derivation. Needed for key revocation (`buildRevokeKeyCall`) and status queries (`isKeyApproved`).

```ts
import { computeKeyId, computeEcdsaKeyId, computeComposedKeyId } from '@pq-wallet/sdk';

// PQ key: keccak256(publicKey)
const falconKeyId = computeKeyId(falconPublicKey);

// ECDSA key: keccak256(abi.encodePacked(uint256(address)))
const ecdsaKeyId = computeEcdsaKeyId(ownerAddress);

// Composed key: keccak256(abi.encodePacked(keyIdA, keyIdB))
const composedKeyId = computeComposedKeyId(ecdsaKeyId, falconKeyId);
```

Note: You don't need to compute key IDs when constructing signers -- the SDK derives them internally from the public key and owner address.

### Validator management

Call builders return `Call` objects (`{ to, data, value? }`) to be executed as UserOperations. These manage the on-chain PQValidator state.

#### Key registration

```ts
import {
  buildRegisterKeyCall,
  buildRegisterComposedKeyCall,
  buildRevokeKeyCall,
} from '@pq-wallet/sdk';

// Register a PQ public key
const call = buildRegisterKeyCall(validatorAddress, SchemeId.ETHFALCON, publicKey);

// Register a composed (hybrid) key
const call = buildRegisterComposedKeyCall(
  validatorAddress,
  SchemeId.ECDSA_ETHFALCON,
  ecdsaPublicKey,
  falconPublicKey
);

// Revoke a key
const call = buildRevokeKeyCall(validatorAddress, SchemeId.ETHFALCON, keyId);
```

#### Scheme management

```ts
import { buildSetSchemeAllowedCall, buildDisableEcdsaCall } from '@pq-wallet/sdk';

// Enable a PQ scheme
const call = buildSetSchemeAllowedCall(validatorAddress, SchemeId.ETHFALCON, true);

// Atomically register PQ key, enable PQ scheme, and disable ECDSA
const call = buildDisableEcdsaCall(validatorAddress, SchemeId.ETHFALCON, publicKey);
```

### Validator queries

Read on-chain validator state:

```ts
import { getOwner, isKeyApproved, isSchemeAllowed, isValidatorInitialized } from '@pq-wallet/sdk';

const owner = await getOwner(client, validatorAddress, accountAddress);
const approved = await isKeyApproved(
  client,
  validatorAddress,
  accountAddress,
  SchemeId.ETHFALCON,
  keyId
);
const allowed = await isSchemeAllowed(client, validatorAddress, accountAddress, SchemeId.ETHFALCON);
const initialized = await isValidatorInitialized(client, validatorAddress, accountAddress);
```

### ABI

The PQValidator ABI is exported for advanced contract interactions:

```ts
import { pqValidatorAbi } from '@pq-wallet/sdk';
```

## Upgrading to post-quantum signing

Accounts start with ECDSA and can be upgraded to PQ schemes:

```ts
// 1. Register the PQ key on-chain
await pqClient.sendUserOperation({
  calls: [
    buildRegisterKeyCall(validatorAddress, SchemeId.ETHFALCON, falconPublicKey),
    buildSetSchemeAllowedCall(validatorAddress, SchemeId.ETHFALCON, true),
  ],
});

// 2. Switch the client to use the PQ scheme
await pqClient.setDefaultScheme(SchemeId.ETHFALCON);

// 3. All subsequent operations use ETHFALCON signatures
await pqClient.sendUserOperation({
  calls: [{ to: '0x...', value: 1000n }],
});
```

Or atomically disable ECDSA while enabling a PQ scheme:

```ts
await pqClient.sendUserOperation({
  calls: [buildDisableEcdsaCall(validatorAddress, SchemeId.ETHFALCON, falconPublicKey)],
});

await pqClient.setDefaultScheme(SchemeId.ETHFALCON);
```

## Per-operation scheme override

You can override the signing scheme for individual operations without changing the default:

```ts
// Use ETHFALCON for this specific operation only
await pqClient.sendUserOperation(
  { calls: [{ to: '0x...', value: 1000n }] },
  { schemeId: SchemeId.ETHFALCON }
);

// Sign a message with a specific scheme
const sig = await pqClient.signMessage('hello', {
  schemeId: SchemeId.ECDSA_ETHFALCON,
});
```

## License

MIT
