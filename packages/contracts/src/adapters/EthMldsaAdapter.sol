// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPQVerifier} from "./IPQVerifier.sol";
import {ISigVerifier} from "../interfaces/IZKNOX.sol";

/// @title EthMldsaAdapter
/// @notice Wraps a deployed ZKNOX MLDSAETH verifier behind the IPQVerifier interface.
/// Uses the ISigVerifier interface with SSTORE2-based key storage (PKContract pattern).
contract EthMldsaAdapter is IPQVerifier {
    ISigVerifier public immutable MLDSAETH;
    address public immutable AUTHORIZED_CALLER;

    /// @notice Minimum expanded key size in bytes.
    /// The expanded key is abi.encode(aHatEncoded, tr, t1Encoded) where aHat is a 4×4 matrix
    /// of compacted polynomials and t1 is 4 compacted polynomials. Any valid encoding is
    /// well above this floor; the check catches obviously invalid inputs without parsing ABI structure.
    uint256 internal constant MIN_EXPANDED_KEY_SIZE = 2048;

    /// @notice keyId → PKContract address (deployed by ZKNOX setKey)
    mapping(bytes32 keyId => address pkContract) private _keys;

    error OnlyAuthorizedCaller();
    error InvalidAddress();
    error InvalidKeySize();
    error KeyAlreadyRegistered(bytes32 keyId);
    error KeyDeploymentFailed();

    constructor(
        address mldsaeth_,
        address authorizedCaller_
    ) {
        if (mldsaeth_ == address(0)) revert InvalidAddress();
        if (authorizedCaller_ == address(0)) revert InvalidAddress();
        MLDSAETH = ISigVerifier(mldsaeth_);
        AUTHORIZED_CALLER = authorizedCaller_;
    }

    /// @notice Register an MLDSAETH public key on-chain.
    /// Calls ZKNOX setKey() which deploys a PKContract via SSTORE2.
    /// @param expandedKey ABI-encoded expanded MLDSAETH public key (aHat, tr, t1)
    /// @return keyId keccak256 of the expanded key
    function registerKey(
        bytes calldata expandedKey
    ) external returns (bytes32 keyId) {
        if (msg.sender != AUTHORIZED_CALLER) revert OnlyAuthorizedCaller();
        if (expandedKey.length < MIN_EXPANDED_KEY_SIZE) revert InvalidKeySize();

        keyId = keccak256(expandedKey);
        if (_keys[keyId] != address(0)) revert KeyAlreadyRegistered(keyId);

        // CEI: set sentinel before external call to prevent reentrancy
        _keys[keyId] = address(1);

        // slither-disable-next-line reentrancy-no-eth
        bytes memory result = MLDSAETH.setKey(expandedKey);
        // ZKNOX setKey returns abi.encodePacked(address) = 20 bytes
        if (result.length < 20) revert KeyDeploymentFailed();
        // forge-lint: disable-next-line(unsafe-typecast)
        address pkContract = address(bytes20(result));
        if (pkContract == address(0) || pkContract == address(1)) revert KeyDeploymentFailed();

        // Safe: reentrancy blocked by AUTHORIZED_CALLER check + sentinel value above
        _keys[keyId] = pkContract;
    }

    /// @notice Verify an MLDSAETH signature.
    /// @param hash The message hash (bytes32)
    /// @param signature 2420 bytes: cTilde(32) || z(2304) || h(84)
    /// @param keyId References the PKContract (from registerKey)
    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        address pkContract = _keys[keyId];

        // No early return for unregistered keys — consistent gas path is required for
        // ERC-4337 gas estimation. ZKNOX will revert on address(0), caught by PQValidator's try/catch.
        bytes4 result = MLDSAETH.verify(abi.encodePacked(pkContract), hash, signature);
        return result == ISigVerifier.verify.selector;
    }
}
