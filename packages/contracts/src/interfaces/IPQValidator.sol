// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IPQValidator
/// @notice External interface for the PQ Wallet validator module.
interface IPQValidator {
    // --- Events ---
    event OwnerSet(address indexed account, address indexed owner);
    event KeyRegistered(address indexed account, uint256 indexed schemeId, bytes32 keyId);
    event KeyRevoked(address indexed account, uint256 indexed schemeId, bytes32 keyId);
    event SchemeAllowedSet(address indexed account, uint256 indexed schemeId, bool indexed allowed);
    event UpgradedToPQ(address indexed account, uint256 indexed schemeId, bytes32 keyId);

    // --- Errors ---
    // AlreadyInitialized and NotInitialized are inherited from IModule (Kernel)
    error InvalidOwner();
    error EcdsaSchemeNotAllowed();

    // --- Key Management (called by account via execute) ---
    function registerPublicKey(
        uint256 schemeId,
        bytes calldata publicKey
    ) external;
    function revokeKey(
        uint256 schemeId,
        bytes32 keyId
    ) external;
    function setSchemeAllowed(
        uint256 schemeId,
        bool allowed
    ) external;
    function disableEcdsa(
        uint256 schemeId,
        bytes calldata publicKey
    ) external;

    // --- Views ---
    function getOwner(
        address account
    ) external view returns (address);
    function isKeyApproved(
        address account,
        uint256 schemeId,
        bytes32 keyId
    ) external view returns (bool);
    function isSchemeAllowed(
        address account,
        uint256 schemeId
    ) external view returns (bool);
}
