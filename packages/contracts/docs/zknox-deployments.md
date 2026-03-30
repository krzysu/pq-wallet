# ZKNOX Deployed Verifier Contracts

Reference of known ZKNOX verifier deployments on testnets and mainnet.

## Contract Types

There are two types of ZKNOX contracts:

### Raw Verifiers ("Fixed Contracts")

Low-level verification math. Expose `verify(bytes,bytes,uint256[],uint256[])` — takes decompressed signature components and public key coefficients directly. **No `setKey`**, no SSTORE2 key storage. These are stateless pure functions.

### ISigVerifier Wrappers

Higher-level contracts implementing the `ISigVerifier` interface:

```solidity
interface ISigVerifier {
    function setKey(bytes calldata key) external returns (bytes memory);
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
```

`setKey` stores the public key on-chain via SSTORE2 and returns the PKContract address (`abi.encodePacked(address)` = 20 bytes). `verify` takes the PKContract address, a message hash, and a compact signature.

**Our `EthFalconAdapter` and `EthMldsaAdapter` expect ISigVerifier wrappers.**

## Sepolia Deployments

### Raw Verifiers (from Kohaku docs)

These are the stateless verification math contracts. They do NOT have `setKey`.

| Scheme    | Address                                      | Notes                   |
| --------- | -------------------------------------------- | ----------------------- |
| ETHFALCON | `0x146f0d9087001995ca63b648e865f6dbbb2d2915` | Keccak-optimized Falcon |
| FALCON    | `0x0724bb7c9e52f3be199964a2d70ff83a103ed99c` | Standard Falcon (SHAKE) |
| MLDSA     | `0x10c978aacef41c74e35fc30a4e203bf8d9a9e548` | ML-DSA (Dilithium)      |
| MLDSAETH  | `0x710f295f1715c2b08bccdb1d9841b4f833f6dde4` | Keccak-optimized ML-DSA |
| ECDSA K1  | `0xe2c354d06cce8f18fd0fd6e763a858b6963456d1` | secp256k1               |
| ECDSA R1  | `0x4023f2e318A3c7cbCf2fFAB11A75f99aC9625214` | P-256                   |

### ISigVerifier Wrappers (from Kohaku deployments.json)

These wrap the raw verifiers with `setKey`/SSTORE2 key storage. However, the Kohaku wrappers have `setKey` marked as `pure` (echoes input, no SSTORE2). They are NOT compatible with our adapter pattern.

| Scheme    | Address                                      | Salt Label                      |
| --------- | -------------------------------------------- | ------------------------------- |
| ETHFALCON | `0x01880eb770be007aE75febabA21532Fb5c33318B` | ZKNOX_ETHFALCON_VERIFIER_V0_0_1 |
| FALCON    | `0x82DDb9783D5577853CbAf2a02b359beeA1E4c4B9` | ZKNOX_FALCON_VERIFIER_V0_0_1    |
| MLDSA     | `0x1C789898a6141Fd5F840334Bb2E289fB188a3cb6` | ZKNOX_MLDSA_VERIFIER_V0_0_7     |
| MLDSAETH  | `0xbfF02B9D0EB96f1Fe1BeB57817F0d6085813f1c0` | ZKNOX_MLDSAETH_VERIFIER_V0_0_1  |
| ECDSA K1  | `0xCE4a6283fCf156B61170D438CC89bA0e96693043` | ZKNOX_ECDSA_K1_VERIFIER_V0_0_1  |
| ECDSA R1  | `0xDB5F45915EbD4647874d5ffFd31a331eE4554c27` | ZKNOX_ECDSA_R1_VERIFIER_V0_0_1  |

## Mainnet Deployments (from pqwallet-contracts)

Deployed on Ethereum (1), Arbitrum (42161), Base (8453) — identical addresses via CREATE2.

| Contract        | Address                                      | Notes                                              |
| --------------- | -------------------------------------------- | -------------------------------------------------- |
| ETHFALCON (raw) | `0xe7581500D3ce52f23f78380f5bd720ec183b3f55` | `zkEthfalconContract` — low-level, no ISigVerifier |
| FALCON (raw)    | `0x4c09aA220A32f41Ed38238eE3608FB7d5097fe4c` | `zkFalconContract` — low-level, no ISigVerifier    |

## What PQ Wallet Needs

Our `EthFalconAdapter` and `EthMldsaAdapter` wrap ISigVerifier contracts that:

1. Have `setKey(bytes)` that deploys the key via SSTORE2 and returns `abi.encodePacked(pkContractAddress)` (20 bytes)
2. Have `verify(bytes,bytes32,bytes)` that reads the stored key and verifies

**None of the currently deployed contracts fully match this.** The raw verifiers lack `setKey`. The Kohaku wrappers have `setKey` but it's `pure` (no SSTORE2).

The source code in our submodules implements the correct ISigVerifier with SSTORE2:

- `lib/ETHFALCON/src/ZKNOX_ethfalcon.sol` — ETHFALCON (Keccak-optimized Falcon)
- `lib/ETHDILITHIUM/src/ZKNOX_ethdilithium.sol` — MLDSAETH (Keccak-optimized ML-DSA)

For production, we deploy these contracts ourselves. They are MIT licensed.

## Signature Formats Expected by ZKNOX ISigVerifier.verify

### ETHFALCON

`verify(bytes pk, bytes32 hash, bytes signature)` where signature = `salt(40) + s2(1024)` = **1064 bytes**.

- `salt`: 40-byte nonce from the Falcon signature (bytes 1-40 of internal format)
- `s2`: 32 uint256 values = 1024 bytes (from `toEthFalconSignature()`)

### MLDSAETH

`verify(bytes pk, bytes32 hash, bytes signature)` where signature = `cTilde(32) + z(2304) + h(84)` = **2420 bytes**.

- `cTilde`: 32-byte challenge hash
- `z`: 2304 bytes (response vector)
- `h`: 84 bytes (hint)

Note: This is the expanded format, not the 3309-byte packed NIST format.

### Public Key Formats

- **ETHFALCON**: 1024 bytes = `abi.encodePacked(uint256[32])` — NTT-domain coefficients. Use `toEthFalconVerifyingKey()` from bedrock-wasm.
- **MLDSAETH**: `abi.encode(aHat, tr, t1)` — expanded key components. No bedrock-wasm converter exists; needs manual expansion.

## Client-Side Crypto: bedrock-wasm Compatibility

| Feature                 | ETHFALCON                                           | MLDSAETH                                                           |
| ----------------------- | --------------------------------------------------- | ------------------------------------------------------------------ |
| Key generation          | `generateFnDsaKeypair(ETH_FALCON)`                  | Not supported (only standard ML-DSA)                               |
| Signing                 | `signFnDsa(secretKey, message)`                     | Not supported for ETH variant                                      |
| Solidity key conversion | `toEthFalconVerifyingKey()` → 1024 bytes            | Not available                                                      |
| Solidity sig conversion | `toEthFalconSignature()` → 1024 bytes (s2 only)     | Not available                                                      |
| Salt extraction         | Internal sig bytes[1..41] → 40 bytes                | N/A                                                                |
| Deterministic keygen    | `generateFnDsaKeypairFromSeed(seed)` (48-byte seed) | `generateMlDsaKeypairFromSeed(seed)` (32-byte seed, standard only) |

**Bottom line:** bedrock-wasm fully supports ETHFALCON client-side crypto including Solidity format conversion. For MLDSAETH, there is no client-side support — bedrock-wasm only generates standard ML-DSA (SHAKE-based) which is cryptographically incompatible with the Keccak-based on-chain verifier.

## Kohaku Account Factories (Sepolia)

For reference — these are Kohaku's account factory contracts, not verifiers.

| Account Type | Address                                      | PQ Scheme | Pre-Quantum |
| ------------ | -------------------------------------------- | --------- | ----------- |
| ethfalcon_k1 | `0x75de9AF9902978826bc99E48f468b682bE17F416` | ETHFALCON | ECDSA K1    |
| ethfalcon_r1 | `0x93115df4f05728Effe3845B552Be5Ff8f183a908` | ETHFALCON | ECDSA R1    |
| falcon_k1    | `0x43D1B09AC488ea1CF2De674Adb3cB97fa0A51c00` | FALCON    | ECDSA K1    |
| falcon_r1    | `0x9984bc6D728991Df5C5662B865b7024a11909999` | FALCON    | ECDSA R1    |
| mldsa_k1     | `0xe28F039653772C32b0eDB1db7c7A5FA250DDA0e5` | MLDSA     | ECDSA K1    |
| mldsa_r1     | `0x01Ff8790a7615Db192ca1005fe60d0732f432eF5` | MLDSA     | ECDSA R1    |
| mldsaeth_k1  | `0x053116Dae2F3F966B2957D11f87A8Ff298ae31C2` | MLDSAETH  | ECDSA K1    |
| mldsaeth_r1  | `0x3b68f42a9eAfDF85D64492Cc68d5C88d1a525c05` | MLDSAETH  | ECDSA R1    |
