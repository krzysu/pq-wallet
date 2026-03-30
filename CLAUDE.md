# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PQ Wallet is a quantum-secure smart wallet for Ethereum and EVM compatible blockchains. It uses ZeroDev Kernel v3.3 (unmodified) with a custom ERC-7579 validator module for post-quantum signature verification. Integrates ZKNOX on-chain verifiers (ETHFALCON, MLDSAETH) via adapter pattern with compositional hybrid verification.

## Monorepo Architecture

This is a **pnpm workspace monorepo** managed with **Turborepo**. The workspace contains:

### Packages

- **`@pq-wallet/contracts`** (`packages/contracts/`) - Solidity smart contracts (PQValidator, adapters, verifiers)
- **`@pq-wallet/sdk`** (`packages/sdk/`) - Client library for quantum-secure smart accounts

**Key architectural decisions:**

- Packages use workspace protocol for internal dependencies (`workspace:*`)
- Turborepo handles build orchestration and caching with dependency awareness
- SDK builds with `tsup` to ESM + CJS + type declarations

## Toolchain

- **pnpm v10** - Package manager (specified in `packageManager` field)
- **Turborepo v2** - Uses `tasks` (not `pipeline`) for task orchestration
- **tsup v8** - Builds TypeScript to ESM/CJS with type declarations
- **TypeScript v5** - No project references/composite mode
- **ESLint v9** - Uses flat config (`eslint.config.mjs`)
- **Vitest** - Configured with `vitest.config.ts` in each package
- **Changesets** - For version management

## Important Constraints

- **Node.js >= 22.12.0** required (specified in engines)
- **pnpm >= 10.28.0** required
- **No type casting** - Avoid using `as` type assertions; fix types properly instead
- **No `any` types** - ESLint configured to error on explicit `any` usage
- **No dynamic imports** - Never use `import()` or `await import()`. Always use static imports at the top of the file
- **No default exports** - ESLint enforces named exports (config files exempted)
- **Consistent type imports** - Use `import type` for type-only imports

## Code Quality Workflow

### Global Commands (All Workspaces)

```bash
pnpm fix    # Fix formatting and linting in all workspaces
pnpm check  # Check formatting and linting in all workspaces
pnpm test   # Run tests in all workspaces
```

### Scoped Commands (Single Workspace)

```bash
pnpm --filter @pq-wallet/sdk fix
pnpm --filter @pq-wallet/contracts fix
```

**At the end of every task:**

- If working on a single workspace: run `pnpm fix` in that workspace
- If working across multiple workspaces: run `pnpm fix` from root
- Always run tests to ensure nothing breaks

## Commit Conventions

Use Semantic Commit Messages format (e.g., `chore:`, `feat:`, `fix:`). Keep messages short. Do not include co-authors or attribution in commit messages.
