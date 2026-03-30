# Post-Quantum Signature Schemes — Reference

Comprehensive reference for PQ signature schemes, ZKNOX verifiers, and client-side libraries.

## Signature Schemes Overview

### FALCON (NIST Standard)

- **Hash function**: SHAKE-256 XOF
- **Public key**: 897 bytes (Falcon-512)
- **Signature**: ~666 bytes (variable, compressed)
- **On-chain gas**: ~3.9M (compacted format)
- **ZKNOX verifier**: `ZKNOX_falcon` / `ZKNOX_falcon.sol`
- **Client library**: bedrock-wasm (`FalconScheme.DSA_512`)
- **Not useful for us**: Standard FALCON uses SHAKE, which is expensive on EVM

### ETHFALCON (Keccak-optimized Falcon)

- **Hash function**: Keccak-256 CTR PRNG (replaces SHAKE)
- **Public key**: 1024 bytes (NTT domain, compacted as uint256[32])
- **Signature**: 1064 bytes (salt 40 + s2 1024)
- **On-chain gas**: ~1.5M
- **ZKNOX verifier**: `ZKNOX_ethfalcon` / `ZKNOX_ethfalcon.sol`
- **Client library**: bedrock-wasm (`FalconScheme.ETH_FALCON`) — **BUT see hash-to-point caveat below**

### MLDSA / ML-DSA-44 (NIST Standard, aka Dilithium)

- **Hash function**: SHAKE-256
- **Public key**: 1312 bytes (NIST format), ~20KB expanded for ZKNOX
- **Signature**: 2420 bytes (cTilde 32 + z 2304 + h 84)
- **On-chain gas**: ~8.1M (standard), reportedly up to 18M with some verifiers
- **ZKNOX verifier**: `ZKNOX_dilithium` / `ZKNOX_dilithium.sol`
- **Client library**: `@noble/post-quantum` (`ml_dsa44`)
- **Status**: Works end-to-end (our ForkMldsa test passes with deployed Sepolia verifier)

### MLDSAETH (Keccak-optimized ML-DSA)

- **Hash function**: Keccak-based PRNG (replaces SHAKE)
- **Public key**: Same expanded format as MLDSA
- **Signature**: 2420 bytes (same format)
- **On-chain gas**: ~4.9M (40% savings vs standard)
- **ZKNOX verifier**: `ZKNOX_ethdilithium` / `ZKNOX_ethdilithium.sol`
- **Client library**: **None exists** — bedrock does not support ETH MLDSA, and `@noble/post-quantum` only supports standard MLDSA (SHAKE-based). ZKNOX provides a Python reference implementation.

## ZKNOX Verifier Interfaces

All ZKNOX verifiers implement `ISigVerifier`:

```solidity
interface ISigVerifier {
    function setKey(bytes calldata key) external returns (bytes memory);
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) external view returns (bytes4);
}
```

- `setKey`: Stores public key on-chain via SSTORE2, returns `abi.encodePacked(pkContractAddress)` (20 bytes)
- `verify`: Returns `verify.selector` on success, `0xFFFFFFFF` on failure
- Both ETHFALCON and MLDSAETH verifiers also expose raw `verify(...)` functions for direct use

### Raw ETHFALCON verify

```solidity
function verify(bytes h, bytes salt, uint256[] s2, uint256[] ntth) external pure returns (bool)
```

- `h`: message hash (32 bytes)
- `salt`: 40-byte nonce from signature
- `s2`: 32 uint256 values, compacted (16 coefficients of 16 bits per word, time domain)
- `ntth`: 32 uint256 values, compacted (NTT domain)

## ZKNOX Version Differences (Critical!)

### hashToPoint argument ordering

The ZKNOX ETHFALCON library has evolved through multiple versions with **incompatible hash-to-point functions**:

| Version                  | Function               | Initial hash               | bedrock-wasm compatible? |
| ------------------------ | ---------------------- | -------------------------- | ------------------------ |
| OLD (pqwallet-contracts) | `hashToPointRIP`       | `keccak256(msgHash, salt)` | **Yes**                  |
| NEW (our submodule)      | `hashToPointEVM`       | `keccak256(salt, msgHash)` | **No**                   |
| TETRATION (PoC only)     | `hashToPointTETRATION` | `keccak256(msgHash, salt)` | N/A (insecure)           |

Both function signatures are `hashToPointXXX(bytes salt, bytes msgHash)` — the Solidity parameter order is the same, but the internal `keccak256(abi.encodePacked(...))` argument order is **swapped**.

**This is the root cause of our ETHFALCON fork test failure.** bedrock-wasm's Keccak hash-to-point uses the OLD/RIP ordering (`msgHash, salt`), but our ZKNOX submodule uses the NEW/EVM ordering (`salt, msgHash`). The encoding format is correct; only the hash computation differs.

### Resolution options

1. **Update bedrock-wasm** to use the new `keccak256(salt, msgHash)` ordering (requires Rust change in fn-dsa-comm)
2. **Pin to old ZKNOX version** with `hashToPointRIP` (security risk — may miss fixes)
3. **Make ZKNOX configurable** — unlikely, this is an external dependency

### ISigVerifier.verify path

The `ISigVerifier.verify(key, hash, sig)` function in ZKNOX_ethfalcon.sol internally:

1. Reads public key from SSTORE2 as `abi.decode(data, (uint256[]))`
2. Parses signature: first 40 bytes = salt, remaining = s2 as uint256[]
3. Calls the raw `verify(abi.encodePacked(hash), salt, s2, ntth)` — same hash-to-point issue applies

## Client-Side Libraries

### bedrock-wasm (`@tectonic-labs/bedrock-wasm`)

**Supports**: ETHFALCON key generation, signing, Solidity format conversion
**Does NOT support**: MLDSAETH (only standard MLDSA with SHAKE)

Key functions:

- `generateFnDsaKeypair(FalconScheme.ETH_FALCON)` → 897-byte public key + 1281-byte private key
- `signFnDsa(secretKey, message)` → internal format signature (variable length)
- `toEthFalconVerifyingKey(publicKey)` → 1024 bytes (NTT compact, uint256[32] packed)
- `toEthFalconSignature(signature)` → 1024 bytes (s2 compact, uint256[32] packed)
- Salt extraction: `signature.value` hex → skip 1-byte header → bytes 1-40

Signature assembly for on-chain: `salt(40) + toEthFalconSignature(1024) = 1064 bytes`

**Compatibility**: Uses `keccak256(msgHash, salt)` ordering → works with OLD ZKNOX (`hashToPointRIP`), NOT with NEW ZKNOX (`hashToPointEVM`).

### @noble/post-quantum

**Supports**: Standard ML-DSA-44/65/87 (SHAKE-based)
**Does NOT support**: MLDSAETH (Keccak variant)

Key functions:

- `ml_dsa44.keygen(seed)` → standard NIST keypair
- `ml_dsa44.sign(message, secretKey)` → 2420-byte signature
- `ml_dsa44.verify(signature, message, publicKey)` → boolean

Public key must be expanded for ZKNOX: raw 1312 bytes → `abi.encode(aHat, tr, t1)` using custom expansion code (see `generate-mldsa-fixtures.mjs` or Kohaku's `utils_mldsa.ts`).

**Compatibility**: Works with ZKNOX `ZKNOX_dilithium` (standard MLDSA verifier). Does NOT work with `ZKNOX_ethdilithium` (MLDSAETH — different hash function).

### ZKNOX Python Reference Implementations

**The canonical signing libraries** for ZKNOX verifiers. Located in the ZKNOX git repos:

- `ETHFALCON/pythonref/` — Python ETHFALCON signer
- `ETHDILITHIUM/pythonref/` — Python MLDSAETH signer

Used in Kohaku tests via `PythonSigner.sol` (FFI-based Solidity contract):

```solidity
// ETHFALCON
(uint256[32] pk, bytes salt, uint256[32] s2) = pythonSigner.sign(path, data, "ETH", seed);

// MLDSAETH
(bytes cTilde, bytes z, bytes h) = pythonSigner.sign(path, data, "ETH", seed);
```

These produce output guaranteed to verify against the corresponding ZKNOX Solidity verifier.

## ZKNOX Compact Format

### Polynomial compaction (uint256[32])

FALCON-512 polynomials have 512 coefficients over F_12289. Compacted as:

- 16 coefficients of 16 bits packed per uint256 word
- coefficient j at bits `[j*16 : j*16+15]` (j=0 at LSB, j=15 at MSB)
- 32 words total = 512 coefficients = 1024 bytes

In big-endian bytes (EVM memory):

- bytes[0:1] = coefficient 15 (MSB)
- bytes[30:31] = coefficient 0 (LSB)

### Public key format

- Input: 897-byte NIST public key (1 byte header + 896 bytes coefficients)
- Processing: parse coefficients → NTT forward transform → compact
- Output: uint256[32] in NTT domain, compacted
- For ISigVerifier.setKey: pass as `abi.encode(uint256[])` → stores via SSTORE2

### Signature format (for ISigVerifier.verify)

- salt: 40 bytes (extracted from internal signature bytes 1-40)
- s2: 1024 bytes = uint256[32] compacted (time domain, NOT NTT)
- Total: `salt(40) + s2(1024) = 1064 bytes`

### MLDSA expanded key format (for ISigVerifier.setKey)

- Input: 1312-byte NIST public key (32 bytes rho + 4 × 320 bytes t1)
- Processing: expand aHat matrix from rho via rejection sampling, compute tr = SHAKE256(pk)
- Output: `abi.encode(bytes aHatEncoded, bytes tr, bytes t1Encoded)`
  - aHatEncoded = `abi.encode(uint256[][][])` (4×4 matrix of compacted polynomials)
  - tr = 64 bytes
  - t1Encoded = `abi.encode(uint256[][])` (4 compacted polynomials)

## Deployment Addresses (Sepolia)

See `docs/zknox-deployments.md` for full list.

Key verifiers:

- ETHFALCON ISigVerifier: `0x01880eb770be007aE75febabA21532Fb5c33318B` (Kohaku, but setKey is pure/no SSTORE2)
- MLDSA ISigVerifier: `0x1C789898a6141Fd5F840334Bb2E289fB188a3cb6` (Kohaku, standard MLDSA, NOT ETH)
- MLDSAETH ISigVerifier: `0xbfF02B9D0EB96f1Fe1BeB57817F0d6085813f1c0` (Kohaku)

For production: deploy `ZKNOX_ethfalcon` and `ZKNOX_ethdilithium` from our submodules.

## Current Status & Blockers

### What works today

| Component                             | Status  | Notes                          |
| ------------------------------------- | ------- | ------------------------------ |
| Standard MLDSA signing (noble)        | Working | ForkMldsa test passes          |
| Standard MLDSA on-chain verification  | Working | Via ZKNOX_dilithium on Sepolia |
| ETHFALCON format conversion (bedrock) | Working | Encoding is correct            |
| ETHFALCON ISigVerifier adapter        | Working | Tested with mocks              |

### What's blocked

| Component                         | Blocker                         | Resolution                           |
| --------------------------------- | ------------------------------- | ------------------------------------ |
| ETHFALCON end-to-end verification | hash-to-point ordering mismatch | Update bedrock-wasm OR pin old ZKNOX |
| MLDSAETH signing                  | No client-side library          | Add to bedrock OR use Python ref     |
| MLDSAETH end-to-end               | Blocked by signing              | Depends on above                     |
