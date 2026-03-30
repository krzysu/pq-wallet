// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Signature scheme identifiers for PQ Wallet.
// Combined (hybrid) schemes start at 100 + PQ scheme index.

uint256 constant ECDSA_SCHEME = 0;
uint256 constant ETHFALCON_SCHEME = 1;
uint256 constant MLDSAETH_SCHEME = 2;

// Combined: 100 + PQ scheme index
uint256 constant ECDSA_ETHFALCON_SCHEME = 101;
uint256 constant ECDSA_MLDSAETH_SCHEME = 102;
