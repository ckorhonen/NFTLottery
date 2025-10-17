# AGENTS.md — Repo Working Guide for Agents

This file gives human- and agent-facing guidance for working in this repository.
Prefer these conventions when editing files in this repo.

## Project Overview

- EVM smart contracts (Foundry) implementing a round-based lottery with
  trustless prize purchasing:
  - NFTs via Seaport (executed through a guarded executor)
  - ERC20 via Uniswap V3 (native-in swaps; recipient = vault)
- Front-end (React + Vite) served by a Cloudflare Worker.
- Solana/Anchor skeleton for token-only v1 (future work).

## Tech Stack

- Solidity: `0.8.24` with `via_ir = true` for normal builds.
- Foundry: forge/cast/anvil latest stable.
- Node: 20.x LTS for web/Worker.
- Cloudflare Workers with static assets (Vite build in `web/dist`).

## Paths of Interest

- Contracts: `evm/src/**/*.sol`
- Tests: `evm/test/**/*.t.sol`
- Scripts: `evm/script/*.s.sol`
- Web app: `web/` (React + Vite), Worker entry `web/worker.ts`
- Deploy orchestration: `ops/`
- Deploy outputs: `deployments/*.json` (consumed by `web/public/registry.json`)

## Commands (EVM)

- Build: `cd evm && forge build`
- Tests (gas report): `cd evm && forge test --gas-report`
- Gas snapshot: `cd evm && forge snapshot` (kept in `evm/.gas-snapshot`)
- Coverage (core contracts only — excludes tests & scripts):
  - Summary: `forge coverage --ir-minimum --exclude-tests --no-match-coverage '^script/' --report summary`
  - LCOV:    `forge coverage --ir-minimum --exclude-tests --no-match-coverage '^script/' --report lcov`

Notes:
- Coverage uses `--ir-minimum` to avoid stack-too-deep during instrumentation.
  Small source-map imprecision is acceptable for CI gating.

## Quality Gates

- Lines coverage target (core contracts): 90%+
- CI enforces:
  - Foundry build + tests (with gas report)
  - Gas snapshot check
  - Coverage report (LCOV artifact, summary printed)
  - Web build must succeed
- Pre-push hook runs the same checks locally.

## Hooks & Formatting

- Pre-commit: lint-staged
  - `.sol`: `forge fmt`
  - web files: Prettier + ESLint (`npm run format` for manual run)
- Pre-push: `forge build && forge test --gas-report`, coverage summary, web build

If hooks don’t run (e.g., fresh clone), set hooks path:
`git config core.hooksPath .husky`.

## Deploy & Configuration

- Multi-chain, multi-instance deploy via `npm run deploy` (uses `ops/config.json`).
- Per-chain VRF env (optional for production randomness):
  - `VRF_COORDINATOR`, `VRF_KEYHASH`, `VRF_SUB_ID`, `VRF_MIN_CONFIRMATIONS`, `VRF_CALLBACK_GAS`.
- Worker deploy requires `CF_API_TOKEN` and `CLODFLARE_ACCOUNT_ID`.

## Contract Conventions

- Do not push production randomness without VRF configured.
- Keep lottery wrappers trust-minimized: enforce allowlists, recipient constraints,
  and respect per-round budgets. Price caps may be added at the wrapper call site.
- Use SafeERC20 for all ERC20 transfers from the vault.
- Prefer small, clearly named events and revert errors.

## Test Conventions

- Cover both happy paths and negative paths (reverts) for:
  - Purchase window, budget exhaustion, allowlists, recipient checks.
  - Claim flows (NotWinner, AlreadyClaimed), one-win-per-wallet.
  - VRF adapter: onlyOwner config, NotCoordinator reverts, successful fulfill.
- Add mainnet‑fork tests for protocol paths when appropriate (optional).

## Front-end Conventions

- ABIs centralized in `web/src/abi.ts`.
- Registry-driven addresses (`web/public/registry.json` generated from `/deployments`).
- Owner-gated admin panels only if connected wallet equals `Lottery.owner()`.

## PR Guidelines

- Keep changes minimal and focused. Update README.md when public APIs or deploy
  assumptions change. Include gas diffs if touching hot paths.
- For contract changes, add/adjust tests and ensure coverage remains ≥ 90% lines
  (core contracts). Update gas snapshot when intentional gas changes are made.

## Security Notes

- Executors and wrappers are designed for “trustless-ish” operations. Maintain
  strict allowlists, exact recipients, and budget checks. Consider adding price
  caps for Seaport and Uniswap calls if operationally needed.

## Contact & Ownership

- `owner` is expected to be a Safe in production. Admin actions (pausing,
  allowlists, executor wiring) should be executed from that Safe.

