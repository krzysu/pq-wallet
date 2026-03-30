# Vendored ZKNOX Verifiers

Vendored from [ZKNoxHQ/ETHFALCON](https://github.com/ZKNoxHQ/ETHFALCON) commit `03ed0d6`.

## Why vendored?

The upstream ZKNOX ETHFALCON verifier changed the hash-to-point argument ordering
in commit `625d462` ("revert salt, msg in the correct order as in NIST also for RIP"),
later renamed from `hashToPointRIP` to `hashToPointEVM` in commit `81097ba`.

- **Upstream (new)**: `keccak256(abi.encodePacked(salt, msgHash))` — salt first
- **bedrock-wasm**: `keccak256(abi.encodePacked(msgHash, salt))` — msgHash first

bedrock-wasm's `fn-dsa-comm` crate implements the old ordering. Since we use bedrock-wasm
for client-side ETHFALCON key generation and signing, the verifier must match.

We vendored the code to have full control and patched the hash ordering to match bedrock-wasm.

## Exact changes from upstream

### `ZKNOX_ethfalcon.sol`

1. **Import ISigVerifier from our interface** instead of `InterfaceVerifier/IVerifier.sol`:
   ```diff
   - import {ISigVerifier} from "InterfaceVerifier/IVerifier.sol";
   + import {ISigVerifier} from "../../interfaces/IZKNOX.sol";
   ```

2. **Use `hashToPointBedrock`** instead of `hashToPointEVM`:
   ```diff
   - uint256[] memory hashed = hashToPointEVM(salt, h);
   + uint256[] memory hashed = hashToPointBedrock(salt, h);
   ```

3. Removed unused `CheckParameters` internal function.

### `ZKNOX_HashToPoint.sol`

1. **Renamed `hashToPointEVM` to `hashToPointBedrock`** and swapped the keccak argument order:
   ```diff
   - function hashToPointEVM(bytes memory salt, bytes memory msgHash) ...
   -     state = keccak256(abi.encodePacked(salt, msgHash));
   + function hashToPointBedrock(bytes memory salt, bytes memory msgHash) ...
   +     state = keccak256(abi.encodePacked(msgHash, salt));
   ```
   The Solidity function parameters are unchanged (`salt, msgHash`), only the internal
   `keccak256` argument order is swapped. This matches the old `hashToPointRIP` behavior.

2. **Removed unused functions**: `hashToPointNIST`, `hashToPointTETRATION`, `splitToHex`.
   Also removed `ZKNOX_shake.sol` import (only needed by `hashToPointNIST`).

### All other files

No changes from upstream — `ZKNOX_falcon_core.sol`, `ZKNOX_falcon_utils.sol`,
`ZKNOX_NTT.sol`, `ZKNOX_NTT_falcon.sol`, `ZKNOX_common.sol`, `ZKNOX_shake.sol`
are unmodified copies.

## MLDSA / MLDSAETH Verifiers

Also vendored from [ZKNoxHQ/ETHDILITHIUM](https://github.com/ZKNOXHQ/ETHDILITHIUM):

- `ZKNOX_dilithium.sol` — Standard MLDSA verifier (SHAKE-based, NIST-compliant)
- `ZKNOX_ethdilithium.sol` — MLDSAETH verifier (Keccak-based, gas-optimized)

### Changes from upstream

**`ZKNOX_dilithium.sol` and `ZKNOX_ethdilithium.sol`:**
```diff
- import {ISigVerifier} from "InterfaceVerifier/IVerifier.sol";
+ import {ISigVerifier} from "../../interfaces/IZKNOX.sol";
```

No other changes. All dependency files (`ZKNOX_dilithium_core.sol`, `ZKNOX_dilithium_utils.sol`,
`ZKNOX_NTT_dilithium.sol`, `ZKNOX_SampleInBall.sol`, `ZKNOX_keccak_prng.sol`, `ZKNOX_hint.sol`,
`ZKNOX_shake.sol`) are unmodified copies.

### Client-side compatibility

- **ZKNOX_dilithium** (standard MLDSA): Compatible with `@noble/post-quantum` (`ml_dsa44`).
  Signatures from noble verify successfully on-chain. Tested via ForkMldsa.t.sol.
- **ZKNOX_ethdilithium** (MLDSAETH): No compatible client-side library exists yet.
  bedrock-wasm only supports standard MLDSA. ZKNOX provides a Python reference in
  the ETHDILITHIUM repo (`pythonref/`) for testing.

## External dependencies

- `sstore2/SSTORE2.sol` — Vendored in `src/vendor/sstore2/` (from [0xSequence/sstore2](https://github.com/0xSequence/sstore2))

## License

All vendored files are MIT licensed (original ZKNOX license preserved in file headers).
