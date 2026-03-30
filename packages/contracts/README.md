# @pq-wallet/contracts

> **WARNING: UNAUDITED CODE — USE AT YOUR OWN RISK.**
> These contracts have not been audited by a third party. They are provided as-is for research and development purposes. Do not use in production with real funds until a formal security audit has been completed.

Smart contracts for PQ Wallet — a quantum-secure ERC-4337 smart wallet.

Uses [ZeroDev Kernel v3.3](https://github.com/zerodevapp/kernel) with a custom **ERC-7579 validator module** for post-quantum signature verification. Integrates [ZKNOX](https://github.com/ZKNOXHQ) on-chain verifiers (ETHFALCON, MLDSAETH) via an adapter pattern with compositional hybrid verification.

## Architecture

```
Kernel v3.3 (unmodified)
  └── KernelFactory (unmodified)
        └── deploys standard Kernel proxies with:

PQValidator (ERC-7579 validator module)
  ├── Per-account: owner, scheme config, approved keys
  ├── ECDSA fast path (65-byte raw signatures)
  └── PQ schemes via PQSignatureRouter:
      ├── EcdsaVerifier (Solady ECDSA)
      ├── EthFalconAdapter → ZKNOX ETHFALCON
      ├── EthMldsaAdapter → ZKNOX MLDSAETH
      └── ComposedVerifier (combines any two adapters)
```

## Contracts

| Contract                        | Description                                                                                  |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| `PQValidator.sol`               | ERC-7579 validator module. Handles ECDSA fast path and routes PQ signatures via the router.  |
| `PQSignatureRouter.sol`         | Registry mapping scheme IDs to verifier adapters. Owner-managed with immutable registration. |
| `adapters/IPQVerifier.sol`      | Common interface for all signature verification adapters.                                    |
| `adapters/EcdsaVerifier.sol`    | ECDSA verification using Solady.                                                             |
| `adapters/EthFalconAdapter.sol` | Wraps ZKNOX ETHFALCON via ISigVerifier with SSTORE2 key storage.                             |
| `adapters/EthMldsaAdapter.sol`  | Wraps ZKNOX MLDSAETH via ISigVerifier with SSTORE2 key storage.                              |
| `adapters/ComposedVerifier.sol` | Combines any two IPQVerifier adapters. Both must pass.                                       |
| `libraries/PQStorageLib.sol`    | EIP-7201 namespaced storage for per-account validator state.                                 |
| `libraries/SchemeIds.sol`       | Signature scheme ID constants.                                                               |
| `interfaces/IZKNOX.sol`         | ISigVerifier interface matching deployed ZKNOX contracts.                                    |
| `interfaces/IPQValidator.sol`   | External interface for PQValidator.                                                          |

## Signature Schemes

| ID  | Name                     | Description                                      |
| --- | ------------------------ | ------------------------------------------------ |
| 0   | `ECDSA_SCHEME`           | ECDSA only (65-byte fast path, no ABI encoding)  |
| 1   | `ETHFALCON_SCHEME`       | ETHFALCON only (Keccak-optimized Falcon)         |
| 2   | `MLDSAETH_SCHEME`        | MLDSAETH only (Keccak-optimized ML-DSA)          |
| 101 | `ECDSA_ETHFALCON_SCHEME` | Hybrid: ECDSA + ETHFALCON (via ComposedVerifier) |
| 102 | `ECDSA_MLDSAETH_SCHEME`  | Hybrid: ECDSA + MLDSAETH (via ComposedVerifier)  |

## Signature Format

**ECDSA fast path** (most common): raw 65-byte signature (`r || s || v`). Detected by length — no encoding overhead.

**PQ and hybrid schemes**: standard ABI encoding:

```solidity
abi.encode(uint256 schemeId, bytes innerSignature, bytes32 keyId)
```

For hybrid (composed) schemes, the inner signature is itself ABI-encoded:

```solidity
abi.encode(ecdsaSignature, pqSignature)
```

## Security Model

- **ERC-4337 safe**: `validateUserOp` never reverts — all verification failures return `SIG_VALIDATION_FAILED` via try/catch around external calls.
- **Verifier immutability**: Once a scheme ID has a verifier registered, it cannot be replaced (even after disable). This prevents a compromised owner from swapping verifiers.
- **CEI pattern**: Adapter `registerKey` functions set sentinel values before external calls to ZKNOX contracts, preventing reentrancy.
- **Nonce invalidation**: `onUninstall` increments a nonce, making all prior key approvals and scheme settings unreachable without explicit re-authorization.
- **EIP-7201 storage**: Namespaced storage prevents collisions with Kernel's storage layout.

## Account Lifecycle

### 1. Deploy account (ECDSA only)

The account address depends only on owner + salt — no PQ dependency:

```solidity
bytes memory validatorData = abi.encode(ownerAddress);
address account = kernelFactory.createAccount(initData, salt);
```

### 2. Register PQ key (optional, separate transaction)

```solidity
pqValidator.registerPublicKey(ETHFALCON_SCHEME, falconPubKey);
pqValidator.setSchemeAllowed(ETHFALCON_SCHEME, true);
```

### 3. Disable ECDSA (atomic)

Registers the PQ key, enables the PQ scheme, and disables ECDSA in one call:

```solidity
pqValidator.disableEcdsa(ETHFALCON_SCHEME, falconPubKey);
```

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Git (for submodules)

### Setup

```bash
# Clone with submodules
git submodule update --init --recursive

# Build
forge build

# Test
forge test -vvv

# Format
forge fmt
```

### Code Quality

```bash
# Foundry linter
forge lint

# Solhint (style/best practices)
npx solhint 'src/**/*.sol'

# Slither (static analysis)
slither src/ --filter-paths "lib/"
```

### Dependencies

All dependencies are git submodules in `lib/`:

| Dependency                                                  | Purpose                                                                  |
| ----------------------------------------------------------- | ------------------------------------------------------------------------ |
| [kernel](https://github.com/zerodevapp/kernel) (dev branch) | IValidator, Kernel types, also provides forge-std and solady             |
| [ETHFALCON](https://github.com/ZKNOXHQ/ETHFALCON)           | ETHFALCON on-chain verifier, also provides InterfaceVerifier and sstore2 |
| [ETHDILITHIUM](https://github.com/ZKNOXHQ/ETHDILITHIUM)     | MLDSAETH on-chain verifier                                               |

## License

MIT
