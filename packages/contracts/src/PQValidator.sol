// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IValidator} from "@zerodev/kernel/interfaces/IERC7579Modules.sol";
import {PackedUserOperation} from "@zerodev/kernel/interfaces/PackedUserOperation.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {PQSignatureRouter} from "./PQSignatureRouter.sol";
import {PQStorageLib} from "./libraries/PQStorageLib.sol";
import {ECDSA_SCHEME} from "./libraries/SchemeIds.sol";
import {IPQValidator} from "./interfaces/IPQValidator.sol";

/// @title PQValidator
/// @notice ERC-7579 validator module for PQ Wallet.
/// Installed as root validator on Kernel accounts.
/// Supports ECDSA (fast path) and post-quantum schemes via PQSignatureRouter.
///
/// IMPORTANT: The 65-byte ECDSA fast path is a hard constraint.
/// No other signature scheme may produce 65-byte signatures, or they will be
/// misrouted to ECDSA verification.
contract PQValidator is IValidator, IPQValidator {
    using PQStorageLib for PQStorageLib.Layout;

    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /// @notice Module type ID for validators (ERC-7579)
    uint256 internal constant MODULE_TYPE_VALIDATOR = 1;

    /// @notice Minimum ABI-encoded length for (uint256, bytes, bytes32): 4 words = 128 bytes
    uint256 internal constant MIN_ABI_ENCODED_SIG_LENGTH = 128;

    /// @notice The signature router that maps scheme IDs to verifier adapters
    PQSignatureRouter public immutable ROUTER;

    constructor(
        PQSignatureRouter _router
    ) {
        ROUTER = _router;
    }

    // ========== ERC-7579 Module Interface ==========

    /// @notice Called by Kernel during module installation.
    /// @param data ABI-encoded owner address
    function onInstall(
        bytes calldata data
    ) external payable {
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        if (s.initialized[msg.sender]) revert AlreadyInitialized(msg.sender);

        address owner = abi.decode(data, (address));
        if (owner == address(0)) revert InvalidOwner();

        s.owners[msg.sender] = owner;
        s.initialized[msg.sender] = true;

        // ECDSA is always allowed by default
        uint256 nonce = s.uninstallNonce[msg.sender];
        bytes32 schemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(ECDSA_SCHEME)), nonce);
        s.schemeAllowed[msg.sender][schemeKey] = true;

        emit OwnerSet(msg.sender, owner);
        emit SchemeAllowedSet(msg.sender, ECDSA_SCHEME, true);
    }

    /// @notice Called by Kernel during module uninstallation.
    /// Clears owner and increments nonce to invalidate all prior key approvals and scheme settings.
    function onUninstall(
        bytes calldata
    ) external payable {
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        delete s.owners[msg.sender];
        delete s.initialized[msg.sender];
        // Increment nonce to invalidate all prior approved keys and scheme settings.
        // All storage keys are derived from keccak256(raw, nonce), so changing the nonce
        // makes all prior entries unreachable without explicit re-authorization.
        ++s.uninstallNonce[msg.sender];
    }

    /// @notice Returns true if this module is a validator (type 1).
    function isModuleType(
        uint256 moduleTypeId
    ) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @notice Returns true if the given smart account has installed this validator.
    function isInitialized(
        address smartAccount
    ) external view returns (bool) {
        return PQStorageLib.layout().initialized[smartAccount];
    }

    // ========== ERC-4337 Validation ==========

    /// @inheritdoc IValidator
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external payable returns (uint256) {
        return _verify(userOpHash, userOp.signature) ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
    }

    // ========== ERC-1271 Validation ==========

    /// @inheritdoc IValidator
    function isValidSignatureWithSender(
        address,
        bytes32 hash,
        bytes calldata sig
    ) external view returns (bytes4) {
        return _verify(hash, sig) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    // ========== Key Management ==========

    /// @inheritdoc IPQValidator
    function registerPublicKey(
        uint256 schemeId,
        bytes calldata publicKey
    ) external {
        _requireInitialized();
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        // slither-disable-next-line reentrancy-events
        bytes32 keyId = ROUTER.registerKey(schemeId, publicKey);
        uint256 nonce = s.uninstallNonce[msg.sender];
        bytes32 nonceKeyId = PQStorageLib.deriveNonceKey(keyId, nonce);
        s.approvedKeys[msg.sender][schemeId][nonceKeyId] = true;
        emit KeyRegistered(msg.sender, schemeId, keyId);
    }

    /// @inheritdoc IPQValidator
    function revokeKey(
        uint256 schemeId,
        bytes32 keyId
    ) external {
        _requireInitialized();
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        uint256 nonce = s.uninstallNonce[msg.sender];
        bytes32 nonceKeyId = PQStorageLib.deriveNonceKey(keyId, nonce);
        s.approvedKeys[msg.sender][schemeId][nonceKeyId] = false;
        emit KeyRevoked(msg.sender, schemeId, keyId);
    }

    /// @inheritdoc IPQValidator
    function setSchemeAllowed(
        uint256 schemeId,
        bool allowed
    ) external {
        _requireInitialized();
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        uint256 nonce = s.uninstallNonce[msg.sender];
        bytes32 schemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(schemeId)), nonce);
        s.schemeAllowed[msg.sender][schemeKey] = allowed;
        emit SchemeAllowedSet(msg.sender, schemeId, allowed);
    }

    /// @inheritdoc IPQValidator
    function disableEcdsa(
        uint256 schemeId,
        bytes calldata publicKey
    ) external {
        _requireInitialized();
        if (schemeId == ECDSA_SCHEME) revert EcdsaSchemeNotAllowed();

        PQStorageLib.Layout storage s = PQStorageLib.layout();
        uint256 nonce = s.uninstallNonce[msg.sender];

        // Register the PQ key (reverts if scheme unknown in router)
        // slither-disable-next-line reentrancy-events
        bytes32 keyId = ROUTER.registerKey(schemeId, publicKey);
        bytes32 nonceKeyId = PQStorageLib.deriveNonceKey(keyId, nonce);
        s.approvedKeys[msg.sender][schemeId][nonceKeyId] = true;

        // Enable the PQ scheme
        bytes32 pqSchemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(schemeId)), nonce);
        s.schemeAllowed[msg.sender][pqSchemeKey] = true;

        // Disable ECDSA — only after PQ key is approved (atomic, no lockout window)
        bytes32 ecdsaSchemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(ECDSA_SCHEME)), nonce);
        s.schemeAllowed[msg.sender][ecdsaSchemeKey] = false;

        emit KeyRegistered(msg.sender, schemeId, keyId);
        emit SchemeAllowedSet(msg.sender, schemeId, true);
        emit UpgradedToPQ(msg.sender, schemeId, keyId);
        emit SchemeAllowedSet(msg.sender, ECDSA_SCHEME, false);
    }

    // ========== Views ==========

    /// @inheritdoc IPQValidator
    function getOwner(
        address account
    ) external view returns (address) {
        return PQStorageLib.layout().owners[account];
    }

    /// @inheritdoc IPQValidator
    function isKeyApproved(
        address account,
        uint256 schemeId,
        bytes32 keyId
    ) external view returns (bool) {
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        uint256 nonce = s.uninstallNonce[account];
        bytes32 nonceKeyId = PQStorageLib.deriveNonceKey(keyId, nonce);
        return s.approvedKeys[account][schemeId][nonceKeyId];
    }

    /// @inheritdoc IPQValidator
    function isSchemeAllowed(
        address account,
        uint256 schemeId
    ) external view returns (bool) {
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        uint256 nonce = s.uninstallNonce[account];
        bytes32 schemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(schemeId)), nonce);
        return s.schemeAllowed[account][schemeKey];
    }

    // ========== Internal ==========

    /// @notice Core signature verification. Handles ECDSA fast path and PQ scheme routing.
    /// @dev The 65-byte fast path is a hard constraint: no other scheme may produce 65-byte signatures.
    function _verify(
        bytes32 hash,
        bytes calldata sig
    ) internal view returns (bool) {
        PQStorageLib.Layout storage s = PQStorageLib.layout();
        if (!s.initialized[msg.sender]) return false;

        uint256 nonce = s.uninstallNonce[msg.sender];

        // Fast path: raw 65-byte ECDSA signature.
        // Uses tryRecoverCalldata (not recover) because Solady's recover reverts on
        // malformed signatures. ERC-4337 requires validateUserOp to return
        // SIG_VALIDATION_FAILED, not revert — a revert would cause bundler bans.
        if (sig.length == 65) {
            bytes32 ecdsaKey = PQStorageLib.deriveNonceKey(bytes32(uint256(ECDSA_SCHEME)), nonce);
            if (!s.schemeAllowed[msg.sender][ecdsaKey]) return false;
            address recovered = ECDSA.tryRecoverCalldata(hash, sig);
            return recovered != address(0) && recovered == s.owners[msg.sender];
        }

        // Reject signatures too short to be valid ABI-encoded (uint256, bytes, bytes32)
        if (sig.length < MIN_ABI_ENCODED_SIG_LENGTH) return false;

        // Standard path: ABI-encoded (schemeId, innerSig, keyId)
        (uint256 schemeId, bytes memory innerSig, bytes32 keyId) = abi.decode(sig, (uint256, bytes, bytes32));

        // Check scheme is allowed for this account
        bytes32 schemeKey = PQStorageLib.deriveNonceKey(bytes32(uint256(schemeId)), nonce);
        if (!s.schemeAllowed[msg.sender][schemeKey]) return false;

        // Check key is approved for this account + scheme
        bytes32 nonceKeyId = PQStorageLib.deriveNonceKey(keyId, nonce);
        if (!s.approvedKeys[msg.sender][schemeId][nonceKeyId]) return false;

        // Verify via router — wrapped in try/catch to prevent reverts from bubbling up.
        // ERC-4337 requires validateUserOp to return SIG_VALIDATION_FAILED, not revert.
        // Router or adapter reverts (e.g., disabled verifier, unregistered key) must not
        // cause bundler bans.
        try ROUTER.verify(schemeId, hash, innerSig, keyId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    function _requireInitialized() internal view {
        if (!PQStorageLib.layout().initialized[msg.sender]) revert NotInitialized(msg.sender);
    }
}
