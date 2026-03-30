// SPDX-License-Identifier: MIT
// Vendored from https://github.com/ZKNoxHQ/ETHFALCON (commit 03ed0d6)
// Modified by PQ Wallet:
//   - Import ISigVerifier from our own interface instead of InterfaceVerifier
//   - Use hashToPointBedrock (msgHash-first ordering) instead of hashToPointEVM (salt-first)
//     to match bedrock-wasm's keccak hash-to-point implementation.
//     See docs/pq-schemes-reference.md for details on the ordering difference.
pragma solidity ^0.8.25;

import "./ZKNOX_common.sol";
import {ISigVerifier} from "../../interfaces/IZKNOX.sol";
import "./ZKNOX_falcon_utils.sol";
import "./ZKNOX_falcon_core.sol";
import "./ZKNOX_HashToPoint.sol";
import {SSTORE2} from "sstore2/SSTORE2.sol";

/// @title ZKNOX_ethfalcon (vendored, bedrock-wasm compatible)
/// @notice Verifies ETHFALCON signatures using Keccak-CTR PRNG hash-to-point.
/// @dev Uses hashToPointBedrock which computes keccak256(msgHash, salt) to match
/// bedrock-wasm's fn-dsa-comm implementation. The upstream ZKNOX_ethfalcon switched
/// to keccak256(salt, msgHash) in hashToPointEVM which is incompatible with bedrock-wasm.
/// @custom:experimental This library is not audited yet, do not use in production.
contract ZKNOX_ethfalcon is ISigVerifier {
    function setKey(
        bytes memory pubkey
    ) external returns (bytes memory) {
        address pointer = SSTORE2.write(pubkey);
        return abi.encodePacked(pointer);
    }

    /// @notice Verify an ETHFALCON signature (raw interface)
    /// @param h Message hash (32 bytes)
    /// @param salt Signature salt/nonce (40 bytes)
    /// @param s2 Compacted signature coefficients (32 uint256 values)
    /// @param ntth Public key in NTT domain, compacted (32 uint256 values)
    function verify(
        bytes memory h,
        bytes memory salt,
        uint256[] memory s2,
        uint256[] memory ntth
    ) external pure returns (bool result) {
        if (salt.length != 40) revert("invalid salt length");
        if (s2.length != falcon_S256) revert("invalid s2 length");
        if (ntth.length != falcon_S256) revert("invalid ntth length");

        // NOTE: hashToPointBedrock uses keccak256(msgHash, salt) ordering
        // to match bedrock-wasm. See ZKNOX_HashToPoint.sol for details.
        uint256[] memory hashed = hashToPointBedrock(salt, h);

        result = falcon_core(s2, ntth, hashed);
        return result;
    }

    /// @notice Verify via ISigVerifier interface (SSTORE2 key lookup)
    function verify(
        bytes calldata _pubkey,
        bytes32 _digest,
        bytes calldata _sig
    ) external view returns (bytes4) {
        address pkContractAddress;
        assembly {
            pkContractAddress := shr(96, calldataload(_pubkey.offset))
        }

        uint256[] memory ntth = abi.decode(SSTORE2.read(pkContractAddress), (uint256[]));

        bytes memory digest = abi.encodePacked(_digest);
        bytes memory sig = _sig;

        uint256 saltPtr;
        uint256 s2Ptr;

        assembly {
            // === Salt (first 40 bytes of signature) ===
            let freePtr := mload(0x40)
            saltPtr := freePtr
            mstore(saltPtr, SALT_LEN)
            let src := add(sig, 32)
            let dst := add(saltPtr, 32)
            for { let i := 0 } lt(i, SALT_LEN) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }

            let saltAllocSize := and(add(SALT_LEN, 31), not(31))
            freePtr := add(freePtr, add(32, saltAllocSize))

            // === s2 (remaining bytes as uint256[]) ===
            let s2DataStart := add(src, SALT_LEN)
            let s2LengthSlot := sub(s2DataStart, 32)

            let savedPtr := freePtr
            mstore(savedPtr, mload(sig))
            mstore(add(savedPtr, 32), mload(s2LengthSlot))
            mstore(0x40, add(savedPtr, 64))

            mstore(s2LengthSlot, div(sub(mload(sig), SALT_LEN), 32))
            s2Ptr := s2LengthSlot
        }

        bool result = this.verify(digest, _ptrToBytes(saltPtr), _ptrToUint256Array(s2Ptr), ntth);

        assembly {
            let savedPtr := sub(mload(0x40), 64)
            mstore(sig, mload(savedPtr))
            mstore(add(sig, SALT_LEN), mload(add(savedPtr, 32)))
        }

        if (result) {
            return ISigVerifier.verify.selector;
        }
        return 0xFFFFFFFF;
    }

    function _ptrToBytes(
        uint256 ptr
    ) private pure returns (bytes memory result) {
        assembly {
            result := ptr
        }
    }

    function _ptrToUint256Array(
        uint256 ptr
    ) private pure returns (uint256[] memory result) {
        assembly {
            result := ptr
        }
    }
}
