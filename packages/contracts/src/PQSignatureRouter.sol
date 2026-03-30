// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "solady/auth/Ownable.sol";
import {IPQVerifier} from "./adapters/IPQVerifier.sol";

/// @title PQSignatureRouter
/// @notice Registry mapping scheme IDs to verifier adapters.
/// Managed by an operator (multisig or DAO) who can register new adapters
/// and disable schemes found to be broken or insecure.
///
/// TRUST MODEL: The owner of this contract is the most trust-critical admin role
/// in the system. It can disable schemes (locking users out) and registers verifiers
/// (which all accounts rely on). Use a multisig or timelock for production.
///
/// Ownership uses Solady's Ownable which supports 2-step handover via
/// requestOwnershipHandover() + completeOwnershipHandover(). Direct
/// transferOwnership() is disabled — use the handover pattern instead.
contract PQSignatureRouter is Ownable {
    mapping(uint256 schemeId => IPQVerifier verifier) public verifiers;

    /// @notice Tracks whether a scheme has ever had a verifier registered.
    /// Prevents re-registration after disableVerifier(), enforcing true immutability.
    mapping(uint256 schemeId => bool) public schemeEverRegistered;

    /// @notice The PQValidator contract authorized to call registerKey
    address public validator;

    event VerifierRegistered(uint256 indexed schemeId, address indexed verifier);
    event VerifierDisabled(uint256 indexed schemeId);
    event ValidatorSet(address indexed validator);

    error UnknownScheme(uint256 schemeId);
    error VerifierAlreadyRegistered(uint256 schemeId);
    error InvalidVerifierAddress();
    error ValidatorAlreadySet();
    error TransferOwnershipDisabled();
    error OnlyValidator();

    constructor(
        address owner_
    ) {
        _initializeOwner(owner_);
    }

    /// @notice Disable direct transferOwnership — use 2-step handover instead.
    function transferOwnership(
        address
    ) public payable override {
        revert TransferOwnershipDisabled();
    }

    /// @notice Set the PQValidator address that is authorized to call registerKey.
    /// Can only be called once (immutable after set) to prevent owner from changing the validator.
    function setValidator(
        address validator_
    ) external onlyOwner {
        if (validator_ == address(0)) revert InvalidVerifierAddress();
        if (validator != address(0)) revert ValidatorAlreadySet();
        validator = validator_;
        emit ValidatorSet(validator_);
    }

    /// @notice Register a verifier adapter for a scheme. Cannot overwrite or re-register.
    /// @dev Verifier registration is permanent — once a scheme ID has been used, it cannot
    /// be reassigned even after disabling. This prevents a compromised owner from replacing
    /// a disabled verifier with a malicious one.
    /// @param schemeId The unique scheme identifier (see SchemeIds.sol)
    /// @param verifier The adapter contract implementing IPQVerifier
    function registerVerifier(
        uint256 schemeId,
        IPQVerifier verifier
    ) external onlyOwner {
        if (address(verifier) == address(0)) revert InvalidVerifierAddress();
        if (address(verifier).code.length == 0) revert InvalidVerifierAddress();
        if (schemeEverRegistered[schemeId]) revert VerifierAlreadyRegistered(schemeId);
        verifiers[schemeId] = verifier;
        schemeEverRegistered[schemeId] = true;
        emit VerifierRegistered(schemeId, address(verifier));
    }

    /// @notice Disable a verifier (e.g., if the scheme is found to be insecure).
    /// The scheme ID is permanently consumed and cannot be re-registered.
    function disableVerifier(
        uint256 schemeId
    ) external onlyOwner {
        delete verifiers[schemeId];
        emit VerifierDisabled(schemeId);
    }

    /// @notice Register a public key for a given scheme. Delegates to the adapter.
    /// @dev Only callable by the authorized PQValidator contract.
    function registerKey(
        uint256 schemeId,
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        if (msg.sender != validator) revert OnlyValidator();
        IPQVerifier verifier = verifiers[schemeId];
        if (address(verifier) == address(0)) revert UnknownScheme(schemeId);
        return verifier.registerKey(publicKey);
    }

    /// @notice Verify a signature for a given scheme. Delegates to the adapter.
    /// @param schemeId The scheme identifier
    /// @param hash The message hash
    /// @param signature The cryptographic signature
    /// @param keyId The key identifier (from registerKey)
    /// @return True if the signature is valid
    function verify(
        uint256 schemeId,
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        IPQVerifier verifier = verifiers[schemeId];
        if (address(verifier) == address(0)) revert UnknownScheme(schemeId);
        return verifier.verify(hash, signature, keyId);
    }
}
