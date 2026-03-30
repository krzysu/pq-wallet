// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EthMldsaAdapter} from "../src/adapters/EthMldsaAdapter.sol";
import {ISigVerifier} from "../src/interfaces/IZKNOX.sol";

/// @notice Mock ZKNOX MLDSAETH verifier for unit testing.
contract MockEthMldsa is ISigVerifier {
    mapping(address pkContract => bytes expandedKey) public storedKeys;
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
        // Adapters pass abi.encodePacked(pkContract) which is 20 bytes
        address pkContract = address(bytes20(pk[0:20]));
        if (storedKeys[pkContract].length == 0) return bytes4(0xffffffff);
        if (signature.length == 0 || uint8(signature[0]) == 0) return bytes4(0xffffffff);
        if (hash == bytes32(0)) return bytes4(0xffffffff);
        return ISigVerifier.verify.selector;
    }
}

contract EthMldsaAdapterTest is Test {
    EthMldsaAdapter adapter;
    MockEthMldsa mockMldsaeth;
    address authorizedCaller;

    /// @dev Returns a dummy expanded key that passes the MIN_EXPANDED_KEY_SIZE check
    function _validExpandedKey(
        uint8 seed
    ) internal pure returns (bytes memory) {
        bytes memory key = new bytes(2048);
        key[0] = bytes1(seed);
        return key;
    }

    function setUp() public {
        authorizedCaller = makeAddr("router");
        mockMldsaeth = new MockEthMldsa();
        adapter = new EthMldsaAdapter(address(mockMldsaeth), authorizedCaller);
    }

    // ========== Constructor ==========

    function test_constructor_setsImmutables() public view {
        assertEq(address(adapter.MLDSAETH()), address(mockMldsaeth));
        assertEq(adapter.AUTHORIZED_CALLER(), authorizedCaller);
    }

    function test_constructor_revertIfZeroMldsaeth() public {
        vm.expectRevert(EthMldsaAdapter.InvalidAddress.selector);
        new EthMldsaAdapter(address(0), authorizedCaller);
    }

    function test_constructor_revertIfZeroCaller() public {
        vm.expectRevert(EthMldsaAdapter.InvalidAddress.selector);
        new EthMldsaAdapter(address(mockMldsaeth), address(0));
    }

    // ========== registerKey ==========

    function test_registerKey_success() public {
        bytes memory expandedKey = _validExpandedKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(expandedKey);

        assertEq(keyId, keccak256(expandedKey));
    }

    function test_registerKey_revertIfUnauthorized() public {
        vm.expectRevert(EthMldsaAdapter.OnlyAuthorizedCaller.selector);
        adapter.registerKey(_validExpandedKey(0xaa));
    }

    function test_registerKey_revertIfDuplicateKey() public {
        bytes memory expandedKey = _validExpandedKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(expandedKey);

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(EthMldsaAdapter.KeyAlreadyRegistered.selector, keyId));
        adapter.registerKey(expandedKey);
    }

    function test_registerKey_differentKeysSucceed() public {
        vm.prank(authorizedCaller);
        bytes32 keyId1 = adapter.registerKey(_validExpandedKey(0xaa));

        vm.prank(authorizedCaller);
        bytes32 keyId2 = adapter.registerKey(_validExpandedKey(0xbb));

        assertTrue(keyId1 != keyId2);
    }

    function test_registerKey_revertIfKeyTooSmall() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(EthMldsaAdapter.InvalidKeySize.selector);
        adapter.registerKey(hex"aabbccddee");
    }

    // ========== verify ==========

    function test_verify_success() public {
        bytes memory expandedKey = _validExpandedKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(expandedKey);

        bytes32 hash = keccak256("test message");
        bytes memory signature = hex"01ff";

        assertTrue(adapter.verify(hash, signature, keyId));
    }

    function test_verify_invalidSignature() public {
        bytes memory expandedKey = _validExpandedKey(0xaa);

        vm.prank(authorizedCaller);
        bytes32 keyId = adapter.registerKey(expandedKey);

        bytes32 hash = keccak256("test message");
        bytes memory signature = hex"00ff";

        assertFalse(adapter.verify(hash, signature, keyId));
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
contract MockFailingEthMldsa is ISigVerifier {
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
contract MockShortReturnEthMldsa is ISigVerifier {
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

contract EthMldsaAdapterFailureTest is Test {
    function test_registerKey_revertIfSetKeyReturnsZero() public {
        MockFailingEthMldsa mock = new MockFailingEthMldsa();
        address caller = makeAddr("router");
        EthMldsaAdapter failAdapter = new EthMldsaAdapter(address(mock), caller);

        bytes memory key = new bytes(2048);
        vm.prank(caller);
        vm.expectRevert(EthMldsaAdapter.KeyDeploymentFailed.selector);
        failAdapter.registerKey(key);
    }

    function test_registerKey_revertIfSetKeyReturnsTooShort() public {
        MockShortReturnEthMldsa mock = new MockShortReturnEthMldsa();
        address caller = makeAddr("router");
        EthMldsaAdapter failAdapter = new EthMldsaAdapter(address(mock), caller);

        bytes memory key = new bytes(2048);
        vm.prank(caller);
        vm.expectRevert(EthMldsaAdapter.KeyDeploymentFailed.selector);
        failAdapter.registerKey(key);
    }
}
