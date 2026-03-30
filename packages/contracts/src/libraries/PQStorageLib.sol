// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title PQStorageLib
/// @notice EIP-7201 namespaced storage for PQValidator.
/// Each smart account gets isolated storage via msg.sender-keyed mappings.
/// Key approvals and scheme allowlists are derived from the uninstall nonce,
/// so incrementing the nonce on uninstall invalidates all prior state without
/// explicit iteration.
library PQStorageLib {
    /// @custom:storage-location erc7201:pqwallet.validator.storage
    struct Layout {
        /// @notice ECDSA owner per account
        mapping(address account => address owner) owners;
        /// @notice Approved keys per account, per scheme. The bytes32 key is nonce-derived via deriveNonceKey.
        mapping(address account => mapping(uint256 schemeId => mapping(bytes32 nonceKeyId => bool approved)))
            approvedKeys;
        /// @notice Which schemes each account allows. The bytes32 key is nonce-derived via deriveNonceKey.
        mapping(address account => mapping(bytes32 nonceSchemeKey => bool allowed)) schemeAllowed;
        /// @notice Whether account is initialized
        mapping(address account => bool initialized) initialized;
        /// @notice Nonce incremented on uninstall to invalidate all prior approved keys and scheme settings
        mapping(address account => uint256 nonce) uninstallNonce;
    }

    // keccak256(abi.encode(uint256(keccak256("pqwallet.validator.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xb9c87b537fc6962e00fd83451d672e31943c36cc3c6386576bdded54b09ae800;

    function layout() internal pure returns (Layout storage store) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            store.slot := slot
        }
    }

    /// @notice Derive a nonce-bound storage key. Used for both key approvals and scheme allowlists.
    /// When uninstallNonce increments, all previously derived keys become unreachable.
    function deriveNonceKey(
        bytes32 raw,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(raw, nonce));
    }
}
