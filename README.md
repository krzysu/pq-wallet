# PQ Wallet

Quantum-secure smart contract wallet for Ethereum and EVM-compatible blockchains.

PQ Wallet uses [ZeroDev Kernel v3.3](https://github.com/zerodevapp/kernel) with a custom ERC-7579 validator module for post-quantum signature verification. It integrates [ZKNOX](https://github.com/ZKNOXHQ) on-chain verifiers (ETHFALCON, MLDSAETH) via an adapter pattern with compositional hybrid verification.

**This is a wallet for the transition period.** Start with ECDSA — it's secure today and compatible with everything. Register post-quantum keys when ready. When Q-Day arrives and ECDSA is no longer safe, disable it in one transaction. Funds stay in the same account, at the same address, with no migration.

Read more about the design in [Designing a Quantum-Secure Ethereum Wallet](https://pckt.blog/b/krzysu/designing-a-quantum-secure-ethereum-wallet-dc3v23r).

## Packages

| Package                                       | Description                                                 |
| --------------------------------------------- | ----------------------------------------------------------- |
| [`@pq-wallet/contracts`](packages/contracts/) | Solidity smart contracts — PQValidator, adapters, verifiers |

## Development

### Prerequisites

- Node.js >= 22.12.0
- pnpm >= 10.28.0
- [Foundry](https://book.getfoundry.sh/) (for contracts)

### Setup

```bash
pnpm install
```

### Commands

```bash
pnpm build   # Build all packages
pnpm fix     # Fix formatting and linting in all workspaces
pnpm check   # Check formatting and linting in all workspaces
pnpm test    # Run tests in all workspaces
```

## License

[MIT](LICENSE)
