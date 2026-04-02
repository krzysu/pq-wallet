# @pq-wallet/cli

Command-line interface for managing quantum-secure smart wallet accounts on Ethereum.

## Overview

PQ Wallet CLI lets you create and manage ERC-4337 smart accounts that support post-quantum signature schemes (ETHFALCON, MLDSAETH) alongside traditional ECDSA, using a single BIP-39 mnemonic to derive multiple accounts.

## Installation

```bash
pnpm add @pq-wallet/cli
```

Or run directly from the monorepo:

```bash
pnpm --filter @pq-wallet/cli build
./packages/cli/bin/run.js --help
```

## Quick Start

```bash
# 1. Configure your bundler and validator
pqwallet configure --bundler-url https://rpc.zerodev.app/... --validator-address 0x...

# 2. Initialize wallet (generates 24-word mnemonic)
pqwallet init

# 3. Create your first account
pqwallet create --name my-wallet

# 4. Create additional accounts from the same mnemonic
pqwallet create --name my-wallet-2

# 5. Deploy on-chain
pqwallet deploy --account my-wallet

# 6. Send ETH
pqwallet send --from my-wallet --to 0x... --amount 0.01

# 7. Sign a message
pqwallet sign --message "Hello" --account my-wallet --scheme 101
```

## Commands

| Command     | Description                                                                 |
| ----------- | --------------------------------------------------------------------------- |
| `init`      | Generate a 24-word mnemonic and encrypt it with a password (one-time setup) |
| `create`    | Derive a new account at the next key index from the stored mnemonic         |
| `list`      | List all accounts with basic info                                           |
| `info`      | Query on-chain state: deployment status, balance, enabled schemes           |
| `deploy`    | Deploy a smart account on-chain (sends 0-value tx to trigger deployment)    |
| `sign`      | Sign a message with a chosen signature scheme                               |
| `send`      | Send ETH to an address                                                      |
| `backup`    | Display the mnemonic recovery phrase                                        |
| `configure` | Set bundler URL, validator address, RPC URL, chain, paymaster URL           |

## Signature Schemes

| Scheme ID | Name            | Description                                          |
| --------- | --------------- | ---------------------------------------------------- |
| `0`       | ECDSA           | Traditional elliptic curve signatures                |
| `1`       | ETHFALCON       | Post-quantum Falcon-512 (Ethereum-compatible format) |
| `2`       | MLDSAETH        | Post-quantum ML-DSA-65 (Dilithium)                   |
| `101`     | ECDSA+ETHFALCON | Hybrid: ECDSA combined with ETHFALCON                |
| `102`     | ECDSA+MLDSAETH  | Hybrid: ECDSA combined with MLDSAETH                 |

Use the `--scheme` flag with `sign` and `send` commands to select a scheme.

## Gas Sponsorship

Use `--sponsor` with the `send` command to have a paymaster cover gas fees:

```bash
pqwallet send --from my-wallet --to 0x... --amount 0.01 --sponsor
```

Requires `--paymaster-url` to be set via `pqwallet configure --paymaster-url <URL>`.

## Multi-Account Architecture

All accounts are derived from a single BIP-39 mnemonic:

- `pqwallet init` generates and encrypts the mnemonic once
- Each `pqwallet create` derives ECDSA + ETHFALCON + MLDSAETH keys at the next available key index
- Accounts are deterministic: the same mnemonic + key index always produces the same account address

## Storage

All data is stored in `~/.pq-wallet/`:

```
~/.pq-wallet/
├── config.json          # Account metadata and settings (unencrypted)
├── mnemonic.enc         # Single encrypted mnemonic (AES-256-GCM, PBKDF2)
└── keystores/           # Per-account encrypted keys
    ├── ecdsa-{address}.json
    ├── ethfalcon-{address}.json
    └── mldsaeth-{address}.json
```

Encryption uses AES-256-GCM with PBKDF2-HMAC-SHA256 key derivation (600,000 iterations).

## Configuration

Before creating accounts, configure your bundler and validator:

```bash
# Required
pqwallet configure --bundler-url <ERC-4337 bundler URL>
pqwallet configure --validator-address <PQValidator contract address>

# Optional
pqwallet configure --chain sepolia
pqwallet configure --rpc-url <custom RPC URL>
pqwallet configure --paymaster-url <paymaster URL>

# View current config
pqwallet configure --show
```

## Development

```bash
# Build
pnpm build

# Type check
pnpm typecheck

# Lint and format
pnpm fix

# Run tests
pnpm test
```
