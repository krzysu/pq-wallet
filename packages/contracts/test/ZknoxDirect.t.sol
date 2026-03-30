// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ZKNOX_ethfalcon} from "../src/vendor/zknox/ZKNOX_ethfalcon.sol";
import {PQFixtures} from "./fixtures/PQFixtures.sol";

/// @notice Minimal test to debug ZKNOX_ethfalcon raw verify directly.
contract ZknoxDirectTest is Test {
    ZKNOX_ethfalcon zknox;

    function setUp() public {
        zknox = new ZKNOX_ethfalcon();
    }

    function test_rawVerify() public view {
        bytes memory publicKey = PQFixtures.ethfalconPublicKey();
        bytes memory signature = PQFixtures.ethfalconSignature();
        bytes32 msgHash = PQFixtures.messageHash();

        // Parse salt (first 40 bytes) and s2 (remaining 1024 bytes)
        bytes memory salt = new bytes(40);
        for (uint256 i = 0; i < 40; i++) {
            salt[i] = signature[i];
        }

        uint256[] memory s2 = new uint256[](32);
        for (uint256 i = 0; i < 32; i++) {
            bytes32 word;
            uint256 offset = 40 + i * 32;
            assembly {
                word := mload(add(add(signature, 32), offset))
            }
            s2[i] = uint256(word);
        }

        // Parse public key as uint256[32]
        uint256[] memory ntth = new uint256[](32);
        for (uint256 i = 0; i < 32; i++) {
            bytes32 word;
            uint256 offset = i * 32;
            assembly {
                word := mload(add(add(publicKey, 32), offset))
            }
            ntth[i] = uint256(word);
        }

        bytes memory h = abi.encodePacked(msgHash);

        console.log("h length:", h.length);
        console.log("salt length:", salt.length);
        console.log("s2 length:", s2.length);
        console.log("ntth length:", ntth.length);

        bool result = zknox.verify(h, salt, s2, ntth);
        assertTrue(result, "Raw ZKNOX verify should pass");
    }
}
