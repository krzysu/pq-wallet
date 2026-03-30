// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPQVerifier} from "./IPQVerifier.sol";
import {ISigVerifier} from "../interfaces/IZKNOX.sol";

/// @title EthFalconAdapter
/// @notice Wraps a deployed ZKNOX ETHFALCON verifier behind the IPQVerifier interface.
/// Uses the ISigVerifier interface with SSTORE2-based key storage (PKContract pattern).
contract EthFalconAdapter is IPQVerifier {
    ISigVerifier public immutable ETHFALCON;
    address public immutable AUTHORIZED_CALLER;

    /// @notice Number of uint256 values in a packed ETHFALCON key
    uint256 internal constant FALCON_S256 = 32;

    /// @notice Expected packed key size: 32 uint256 values = 1024 bytes
    uint256 internal constant PACKED_KEY_SIZE = FALCON_S256 * 32;

    /// @notice keyId → PKContract address (deployed by ZKNOX setKey via SSTORE2)
    mapping(bytes32 keyId => address pkContract) private _keys;

    error OnlyAuthorizedCaller();
    error InvalidAddress();
    error InvalidKeySize();
    error KeyAlreadyRegistered(bytes32 keyId);
    error KeyDeploymentFailed();

    constructor(
        address ethfalcon_,
        address authorizedCaller_
    ) {
        if (ethfalcon_ == address(0)) revert InvalidAddress();
        if (authorizedCaller_ == address(0)) revert InvalidAddress();
        ETHFALCON = ISigVerifier(ethfalcon_);
        AUTHORIZED_CALLER = authorizedCaller_;
    }

    /// @notice Register an ETHFALCON public key on-chain.
    /// Accepts packed NTT coefficients (1024 bytes), converts to ABI-encoded uint256[]
    /// for ZKNOX setKey which deploys a PKContract via SSTORE2.
    /// @param publicKey Packed NTT coefficients (1024 bytes = 32 uint256 values)
    /// @return keyId keccak256 of the public key
    function registerKey(
        bytes calldata publicKey
    ) external returns (bytes32 keyId) {
        if (msg.sender != AUTHORIZED_CALLER) revert OnlyAuthorizedCaller();
        if (publicKey.length != PACKED_KEY_SIZE) revert InvalidKeySize();

        keyId = keccak256(publicKey);
        if (_keys[keyId] != address(0)) revert KeyAlreadyRegistered(keyId);

        // CEI: set sentinel before external call to prevent reentrancy
        _keys[keyId] = address(1);

        // Convert packed bytes to abi.encode(uint256[]) for ZKNOX SSTORE2 storage
        uint256[] memory ntth = new uint256[](FALCON_S256);
        for (uint256 i = 0; i < FALCON_S256; ++i) {
            ntth[i] = uint256(bytes32(publicKey[i * 32:(i + 1) * 32]));
        }

        // slither-disable-next-line reentrancy-no-eth
        bytes memory result = ETHFALCON.setKey(abi.encode(ntth));
        if (result.length < 20) revert KeyDeploymentFailed();
        address pkContract = address(bytes20(result));
        if (pkContract == address(0) || pkContract == address(1)) revert KeyDeploymentFailed();

        _keys[keyId] = pkContract;
    }

    /// @notice Verify an ETHFALCON signature against a stored key.
    /// Delegates to ZKNOX ISigVerifier.verify which reads the key from SSTORE2
    /// and performs the verification math internally.
    /// @param hash The message hash (bytes32)
    /// @param signature salt(40 bytes) + s2(1024 bytes) = 1064 bytes
    /// @param keyId References the PKContract (from registerKey)
    function verify(
        bytes32 hash,
        bytes calldata signature,
        bytes32 keyId
    ) external view returns (bool) {
        address pkContract = _keys[keyId];

        // No early return for unregistered keys — consistent gas path is required for
        // ERC-4337 gas estimation. ZKNOX will revert on address(0), caught by PQValidator's try/catch.
        bytes4 result = ETHFALCON.verify(abi.encodePacked(pkContract), hash, signature);
        return result == ISigVerifier.verify.selector;
    }
}
