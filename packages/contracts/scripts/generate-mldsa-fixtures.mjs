/**
 * Generate MLDSA test fixtures for Forge fork tests.
 *
 * Uses @noble/post-quantum for key generation and signing,
 * key expansion logic from Kohaku for the on-chain expanded format,
 * and viem for ABI encoding.
 *
 * Usage: node scripts/generate-mldsa-fixtures.mjs
 */

import { ml_dsa44 } from '@noble/post-quantum/ml-dsa.js';
import { shake128, shake256 } from '@noble/hashes/sha3.js';
import { encodeAbiParameters, bytesToHex, hexToBytes, toHex } from 'viem';
import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_PATH = resolve(__dirname, '../test/fixtures/MldsaFixtures.sol');

// ============================================================================
// Key expansion (from Kohaku's utils_mldsa.ts — expands NIST key to ZKNOX format)
// ============================================================================

const q = 8380417;

function rejectionSamplePoly(rho, i, j, N = 256) {
  const seed = new Uint8Array(rho.length + 2);
  seed.set(rho, 0);
  seed[rho.length] = j;
  seed[rho.length + 1] = i;
  const xof = shake128.create();
  xof.update(seed);
  const r = new Int32Array(N);
  let jIdx = 0;
  while (jIdx < N) {
    const buf = new Uint8Array(3 * 64);
    xof.xofInto(buf);
    for (let k = 0; jIdx < N && k <= buf.length - 3; k += 3) {
      let t = buf[k] | (buf[k + 1] << 8) | (buf[k + 2] << 16);
      t &= 0x7fffff;
      if (t < q) r[jIdx++] = t;
    }
  }
  return r;
}

function recoverAhat(rho, K, L) {
  const aHat = [];
  for (let i = 0; i < K; i++) {
    const row = [];
    for (let j = 0; j < L; j++) {
      row.push(rejectionSamplePoly(rho, i, j));
    }
    aHat.push(row);
  }
  return aHat;
}

function polyDecode10Bits(bytes) {
  const poly = new Int32Array(256);
  let r = 0n;
  for (let i = 0; i < bytes.length; i++) r |= BigInt(bytes[i]) << BigInt(8 * i);
  const mask = (1 << 10) - 1;
  for (let i = 0; i < 256; i++) {
    poly[i] = Number((r >> BigInt(i * 10)) & BigInt(mask));
  }
  return poly;
}

function compactPoly256(coeffs, m) {
  const a = Array.from(coeffs, x => BigInt(Math.floor(Number(x))));
  const n = (a.length * m) / 256;
  const b = new Array(n).fill(0n);
  for (let i = 0; i < a.length; i++) {
    const idx = Math.floor((i * m) / 256);
    const shift = BigInt((i % (256 / m)) * m);
    b[idx] |= a[i] << shift;
  }
  return b;
}

function compactModule256(data, m) {
  return data.map(row => row.map(p => compactPoly256(p, m)));
}

function decodePublicKey(publicKey) {
  const RHO_BYTES = 32;
  const K = 4;
  const T1_POLY_BYTES = 320;
  if (publicKey.length !== RHO_BYTES + K * T1_POLY_BYTES)
    throw new Error(`Invalid publicKey length: ${publicKey.length}`);
  const rho = publicKey.slice(0, RHO_BYTES);
  const t1 = [];
  for (let i = 0; i < K; i++) {
    const offset = RHO_BYTES + i * T1_POLY_BYTES;
    t1.push(polyDecode10Bits(publicKey.slice(offset, offset + T1_POLY_BYTES)));
  }
  const tr = shake256(new Uint8Array(publicKey), { dkLen: 64 });
  return { rho, t1, tr };
}

/**
 * Expand NIST ML-DSA-44 public key to ZKNOX on-chain format.
 * Returns ABI-encoded bytes: abi.encode(bytes aHatEncoded, bytes tr, bytes t1Encoded)
 */
function toExpandedEncodedBytes(publicKey) {
  const { rho, t1, tr } = decodePublicKey(publicKey);
  const aHat = recoverAhat(rho, 4, 4);
  const aHatCompact = compactModule256(aHat, 32);
  const [t1Compact] = compactModule256([t1], 32);

  // ABI-encode aHat as uint256[][][]
  const aHatEncoded = encodeAbiParameters(
    [{ type: 'uint256[][][]' }],
    [aHatCompact]
  );

  // ABI-encode t1 as uint256[][]
  const t1Encoded = encodeAbiParameters(
    [{ type: 'uint256[][]' }],
    [t1Compact]
  );

  // Final: abi.encode(bytes, bytes, bytes)
  const expanded = encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes' }, { type: 'bytes' }],
    [aHatEncoded, bytesToHex(tr), t1Encoded]
  );

  return expanded;
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const seed = new Uint8Array(32);
  seed.fill(0x42);

  console.log('Generating ML-DSA-44 keypair from seed...');
  const { publicKey, secretKey } = ml_dsa44.keygen(seed);
  console.log(`Public key: ${publicKey.length} bytes, Secret key: ${secretKey.length} bytes`);

  const messageHash = hexToBytes('0xa1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2');

  console.log('Signing...');
  // noble API: sign(msg, secretKey)
  const signature = ml_dsa44.sign(messageHash, secretKey);
  console.log(`Signature: ${signature.length} bytes`);

  // noble API: verify(sig, msg, publicKey)
  const valid = ml_dsa44.verify(signature, messageHash, publicKey);
  if (!valid) throw new Error('Local verification failed');
  console.log('Local verification passed.');

  console.log('Expanding public key for ZKNOX format...');
  const expandedKeyHex = toExpandedEncodedBytes(publicKey);
  console.log(`Expanded key: ${(expandedKeyHex.length - 2) / 2} bytes`);

  const sigHex = bytesToHex(signature);
  const messageHashHex = toHex(messageHash);

  const solidity = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MldsaFixtures
/// @notice Test fixtures generated by scripts/generate-mldsa-fixtures.mjs
/// @dev Regenerate with: node scripts/generate-mldsa-fixtures.mjs
///
/// ML-DSA-44 keypair from deterministic seed (32 bytes of 0x42).
/// Expanded key uses ZKNOX format: abi.encode(aHatEncoded, tr, t1Encoded).
/// Signature is 2420 bytes: cTilde(32) + z(2304) + h(84).
library MldsaFixtures {
    function messageHash() internal pure returns (bytes32) {
        return ${messageHashHex};
    }

    /// @notice Expanded ML-DSA-44 public key for ZKNOX setKey
    function mldsaExpandedKey() internal pure returns (bytes memory) {
        return hex"${expandedKeyHex.slice(2)}";
    }

    /// @notice ML-DSA-44 signature (2420 bytes)
    function mldsaSignature() internal pure returns (bytes memory) {
        return hex"${sigHex.slice(2)}";
    }
}
`;

  writeFileSync(OUTPUT_PATH, solidity);
  console.log(`Fixtures written to ${OUTPUT_PATH}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
