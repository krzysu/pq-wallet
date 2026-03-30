// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EthFalconAdapter} from "../src/adapters/EthFalconAdapter.sol";
import {ISigVerifier} from "../src/interfaces/IZKNOX.sol";

/// @notice Mock ZKNOX ETHFALCON ISigVerifier for unit testing.
/// Simulates SSTORE2-based key storage and signature verification.
contract MockEthFalcon is ISigVerifier {
    mapping(address pkContract => bytes storedKey) public storedKeys;
    uint256 private _nonce;

    function setKey(
        bytes calldata key
    ) external returns (bytes memory) {
        _nonce++;
        address pkContract = address(uint160(uint256(keccak256(abi.encodePacked(key, _nonce)))));
        storedKeys[pkContract] = key;
        return abi.encodePacked(pkContract);
    }

    function verify(
        bytes calldata pk,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        address pkContract = address(bytes20(pk[0:20]));
        if (storedKeys[pkContract].length == 0) return bytes4(0xffffffff);
        if (signature.length == 0 || uint8(signature[0]) == 0) return bytes4(0xffffffff);
        if (hash == bytes32(0)) return bytes4(0xffffffff);
        return ISigVerifier.verify.selector;
    }
}

contract EthFalconAdapterTest is Test {
    EthFalconAdapter adapter;
    MockEthFalcon mockFalcon;
    address authorizedCaller;

    function setUp() public {
        authorizedCaller = makeAddr("router");
        mockFalcon = new MockEthFalcon();
        adapter = new EthFalconAdapter(address(mockFalcon), authorizedCaller);
    }

    // ========== Constructor ==========

    function test_constructor_setsImmutables() public view {
        assertEq(address(adapter.ETHFALCON()), address(mockFalcon));
        assertEq(adapter.AUTHORIZED_CALLER(), authorizedCaller);
    }

    function test_constructor_revertIfZeroFalcon() public {
        vm.expectRevert(EthFalconAdapter.InvalidAddress.selector);
        new EthFalconAdapter(address(0), authorizedCaller);
    }

    function test_constructor_revertIfZeroCaller() public {
        vm.expectRevert(EthFalconAdapter.InvalidAddress.selector);
        new EthFalconAdapter(address(mockFalcon), address(0));
    }

    // ========== registerKey ==========

    function _makeKey(
        uint8 seed
    ) internal pure returns (bytes memory) {
        bytes memory key = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            key[i] = bytes1(uint8((seed + i) % 256));
        }
        return key;
    }

    function test_registerKey_success() public {
        bytes memory publicKey = _makeKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(publicKey);

        assertEq(keyId, keccak256(publicKey));
    }

    function test_registerKey_revertIfUnauthorized() public {
        vm.expectRevert(EthFalconAdapter.OnlyAuthorizedCaller.selector);
        adapter.registerKey(_makeKey(0xaa));
    }

    function test_registerKey_revertIfWrongSize() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(EthFalconAdapter.InvalidKeySize.selector);
        adapter.registerKey(hex"aabbccdd"); // too short
    }

    function test_registerKey_revertIfDuplicateKey() public {
        bytes memory publicKey = _makeKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(publicKey);

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(EthFalconAdapter.KeyAlreadyRegistered.selector, keyId));
        adapter.registerKey(publicKey);
    }

    function test_registerKey_differentKeysSucceed() public {
        vm.prank(authorizedCaller);
        bytes32 keyId1 = adapter.registerKey(_makeKey(0xaa));

        vm.prank(authorizedCaller);
        bytes32 keyId2 = adapter.registerKey(_makeKey(0xbb));

        assertTrue(keyId1 != keyId2);
    }

    // ========== verify ==========

    function test_verify_success() public {
        bytes memory publicKey = _makeKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(publicKey);

        bytes32 hash = keccak256("test message");
        // Non-zero first byte → valid in mock
        assertTrue(adapter.verify(hash, hex"01ff", keyId));
    }

    function test_verify_invalidSignature() public {
        bytes memory publicKey = _makeKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(publicKey);

        bytes32 hash = keccak256("test message");
        // Zero first byte → invalid in mock
        assertFalse(adapter.verify(hash, hex"00ff", keyId));
    }

    function test_verify_unregisteredKey() public view {
        bytes32 fakeKeyId = keccak256("nonexistent");
        assertFalse(adapter.verify(keccak256("msg"), hex"01ff", fakeKeyId));
    }

    function test_verify_zeroKeyId() public view {
        assertFalse(adapter.verify(keccak256("msg"), hex"01ff", bytes32(0)));
    }
}

/// @notice Mock that returns address(0) from setKey
contract MockFailingEthFalcon is ISigVerifier {
    function setKey(
        bytes calldata
    ) external pure returns (bytes memory) {
        return abi.encodePacked(address(0));
    }

    function verify(
        bytes calldata,
        bytes32,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(0xffffffff);
    }
}

/// @notice Mock that returns too-short data from setKey
contract MockShortReturnEthFalcon is ISigVerifier {
    function setKey(
        bytes calldata
    ) external pure returns (bytes memory) {
        return hex"dead";
    }

    function verify(
        bytes calldata,
        bytes32,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(0xffffffff);
    }
}

contract EthFalconAdapterFailureTest is Test {
    function test_registerKey_revertIfSetKeyReturnsZero() public {
        MockFailingEthFalcon mock = new MockFailingEthFalcon();
        address caller = makeAddr("router");
        EthFalconAdapter adapter = new EthFalconAdapter(address(mock), caller);

        vm.prank(caller);
        vm.expectRevert(EthFalconAdapter.KeyDeploymentFailed.selector);
        adapter.registerKey(_makeKey(0xaa));
    }

    function test_registerKey_revertIfSetKeyReturnsTooShort() public {
        MockShortReturnEthFalcon mock = new MockShortReturnEthFalcon();
        address caller = makeAddr("router");
        EthFalconAdapter adapter = new EthFalconAdapter(address(mock), caller);

        vm.prank(caller);
        vm.expectRevert(EthFalconAdapter.KeyDeploymentFailed.selector);
        adapter.registerKey(_makeKey(0xaa));
    }

    function _makeKey(
        uint8 seed
    ) internal pure returns (bytes memory) {
        bytes memory key = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            key[i] = bytes1(uint8((seed + i) % 256));
        }
        return key;
    }
}
