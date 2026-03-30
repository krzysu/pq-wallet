// SPDX-License-Identifier: MIT
// Vendored from https://github.com/ZKNoxHQ/ETHFALCON (commit 03ed0d6)
// Modified by PQ Wallet:
//   - Only hashToPointBedrock is kept (keccak-based, bedrock-wasm compatible)
//   - Argument ordering: keccak256(msgHash, salt) — matches bedrock-wasm's fn-dsa-comm
//   - The upstream hashToPointEVM uses keccak256(salt, msgHash) which is incompatible
//   - hashToPointNIST and hashToPointTETRATION removed (not needed)
//
// Hash-to-point ordering history:
//   - Old ZKNOX (hashToPointRIP): keccak256(msgHash, salt) ← bedrock-wasm matches this
//   - New ZKNOX (hashToPointEVM): keccak256(salt, msgHash) ← breaking change
//   - This file uses the old/bedrock ordering with a clear name
pragma solidity ^0.8.25;

import "./ZKNOX_falcon_utils.sol";

/// @notice Hash message to polynomial point using Keccak256-CTR PRNG (bedrock-wasm compatible)
/// @dev Uses keccak256(msgHash, salt) ordering to match bedrock-wasm's fn-dsa-comm implementation.
/// This is the same algorithm as ZKNOX's hashToPointRIP / hashToPointEVM, differing ONLY
/// in the argument order to keccak256. The XOF construction is identical:
///   1. state = keccak256(msgHash || salt)
///   2. extendedState = state || counter(uint64)
///   3. buffer = keccak256(extendedState), sample 16-bit values < 61445, reduce mod 12289
///   4. Increment counter, repeat until 512 coefficients produced
/// @param salt 40-byte salt/nonce from the Falcon signature
/// @param msgHash Message hash bytes
/// @return output Array of 512 coefficients in Z_q
function hashToPointBedrock(
    bytes memory salt,
    bytes memory msgHash
) pure returns (uint256[] memory output) {
    output = new uint256[](n);

    bytes32 state;

    // NOTE: msgHash comes FIRST to match bedrock-wasm's keccak hash-to-point
    // The upstream hashToPointEVM uses (salt, msgHash) which breaks bedrock compatibility
    state = keccak256(abi.encodePacked(msgHash, salt));
    bytes memory extendedState = abi.encodePacked(state, uint64(0x00));

    assembly ("memory-safe") {
        let counter := 0
        let i := 0
        let offset := add(output, 32)
        let extendedAdress := add(extendedState, 64)
        for {} lt(i, n) {} {
            let buffer := keccak256(add(extendedState, 32), 40)
            for { let j := 240 } lt(j, 666) { j := sub(j, 16) } {
                let chunk := and(shr(j, buffer), 0xffff)
                if lt(chunk, kq) {
                    mstore(offset, mod(chunk, q))
                    offset := add(offset, 32)
                    i := add(i, 1)
                    if eq(i, 512) { break }
                }
            }

            // counter += 1 (shifted by 192 bits to increment the uint64 counter in-place)
            counter := add(counter, 6277101735386680763835789423207666416102355444464034512896)
            mstore(extendedAdress, counter)
        }
    }
}
