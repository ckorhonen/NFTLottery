# NFTLottery — EVM + Solana (skeleton)

## Overview
- Users deposit native tokens to buy tickets for time-based rounds. At round close, a configurable share (default 50%) funds trustless prize purchases (NFTs via Seaport, ERC20 via Uniswap). The remaining share accrues to the owner on-contract. Winners are drawn randomly and must claim prizes from the contract (no gas sponsorship).
- One‑win‑per‑wallet is supported (configurable at deploy). Rounds are pausable and can have an optional deposit threshold cap.
- Trustless purchases are executed through guarded executors and Lottery wrappers that spend the purchase budget and auto‑register prizes in the vault.
- EVM implementation (Foundry) is functional with comprehensive tests and coverage; Solana is a minimal Anchor skeleton for token-only v1.
- A Cloudflare Worker front-end is included and auto-wired to deployed addresses/instances.

## Repository Layout
- **evm/** – Solidity contracts, Foundry tests, deploy script.
- **web/** – React + Vite app served by Workers, plus registry build tooling.
- **ops/** – Multi-chain deploy orchestrator and example config.
- **deployments/** – Chain-specific JSON written by the deploy script.
- **solana/** – Anchor skeleton program for SVM (token-only v1).

## Key Contracts (EVM)
- **Lottery** – Manages deposits, round timing, budget split, winner draw, owner accrual, and executor authorization. Includes budget-spending wrappers:
  - `executeSeaportBasicERC721/1155(roundId, calldata, price)`
  - `executeUniV3SwapNative(roundId, calldata, amountIn)`
  - `bundleERC20Prizes(roundId, token, unitAmount, count)`
- **Ticket1155** – ERC1155 tickets (tokenId = roundId) minted per deposit.
- **PrizeVault** – Custodies NFT/ERC20 prizes, assigns winners, and handles claims (ERC721/1155 receivers, SafeERC20).
- **SeaportExecutor** – Executes allowed-collection NFT purchases via Seaport basic orders under budget constraints, forwards to the vault, and auto-registers prizes.
- **UniswapV3Executor** – Performs native-in swaps to allowed tokens with recipient forced to the vault; auto-registers ERC20 prizes.
- **Allowlists** – Owner-managed allowlists for NFT collections and ERC20 tokens.
- **Randomness** – `PseudoRandomSource` for development/tests and `VRFv2Adapter` (Chainlink VRF v2-style) for production.

## Security & Trust Model
- **Trustless v1** – Purchases may be executed by anyone but are constrained by on-chain allowlists, per-round budget consumption, and fixed recipients (PrizeVault). Seaport signature validity is enforced by Seaport.
- **Randomness** – `PseudoRandomSource` is for development only. Use the included `VRFv2Adapter` with Chainlink VRF v2/v2.5 on mainnet.
- **Claims** – Winners call the vault to claim. Owner share accrues on-contract and is withdrawn via `claimOwnerAll()`.

## Parameters
- Per-instance (deployment): `ticketPrice`, `roundDuration`, `purchaseWindow`, `purchaseShareBps` + `ownerShareBps` (sum 10000), optional `thresholdCap`, `allowMultipleWins`.
- Owner/fee recipient can be EOA or Safe. Use `setSeaportExecutor` / `setUniswapV3Executor` to wire executors post-deploy.

## Limits & Safety Defaults
- Per-transaction deposit minimum equals the ticket price. Optional per-wallet cap can be added later.
- Purchase window occurs after close; budget consumption tracked; pausable circuit breaker.
- Allowlists required for NFTs/tokens; executors revert if not allowed or budget exceeded.
- Recommended hardening: price caps (max native spend) on wrapper calls (TODO if desired).

## Build & Test (EVM)
- **Prerequisites:** Foundry installed.
- **Build:** `cd evm && forge build`
- **Unit tests + gas report:** `cd evm && forge test --gas-report`
- **Gas snapshot:** `cd evm && forge snapshot` (checked into `evm/.gas-snapshot` and enforced)
- **Coverage (core contracts):**
  - Summary: `cd evm && forge coverage --ir-minimum --exclude-tests --no-match-coverage '^script/' --report summary`
  - LCOV: `cd evm && forge coverage --ir-minimum --exclude-tests --no-match-coverage '^script/' --report lcov`
- **Current coverage:** ~90.4% lines on core contracts (scripts excluded).

## Deployment (EVM)
1. Copy `ops/config.example.json` to `ops/config.json` and fill RPC URLs + private keys.
2. Run `npm run deploy` (uses `ops/deploy.ts`). For each chain it runs the Foundry script, writes `deployments/<chainId>.json`, builds the web app, and deploys the Worker if `CF_API_TOKEN` is set.

### Manual Single-Chain Deploy
- `cd evm && forge script script/DeployLottery.s.sol:DeployLottery --rpc-url $RPC --private-key $PK --broadcast`
- Outputs JSON to `../deployments/<chainId>.json`.

## Front-end (Workers)
- Configure Cloudflare credentials (`CF_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`).
- Build + deploy: `npm --prefix web install && npm --prefix web run build && npm --prefix web run deploy`.
- The app reads `web/public/registry.json` (built from `deployments/*.json`).
- **Features include:**
  - Chain + instance picker; buy N tickets; "My Prizes" claim list.
  - Round stats (deposited, tickets, budget, owner accrual), winners list.
  - Owner-gated Admin: finalize/draw/start next.
  - Owner-gated Allowlist Manager: add/remove collections & tokens.
  - Owner-gated Swap Console: native→ERC20 swaps via executor through Lottery wrapper (auto-registers prize).

## Solana (Skeleton)
- See `solana/` for an Anchor program shell. It outlines lottery state; token purchases via Jupiter and secure randomness via Switchboard VRF are to be integrated next.

## CI & Monitoring Tips (GitHub CLI)
- PR checks summary: `gh pr view --json statusCheckRollup,url | jq`.
- Watch checks live: `gh pr checks --watch` (use `--fail-fast`, default interval 10s).
- Open PR in browser: `gh pr view -w`.
- List runs: `gh run list --json databaseId,headBranch,status,conclusion,displayTitle,url | jq`.
- View run jobs: `gh run view <RUN_ID> --json jobs | jq`.
- Tail job logs: `gh run view <RUN_ID> --job <JOB_ID> --log`.
- Rerun failed: `gh run rerun <RUN_ID>`.
- Manually trigger: `gh workflow run <workflow.yml> [--ref branch]`.

## Developer Tooling
- **Pre-commit:** lint-staged (Prettier/ESLint on web; `forge fmt` on `.sol`).
- **Pre-push:** runs `forge build && forge test --gas-report`, quick coverage summary, and web build.
- **CI:** runs Foundry tests with gas report + gas snapshot check, builds web, and uploads LCOV (core contracts).

## VRF & Automation (Production)
- **VRF (recommended):** set env in deploy script (per chain):
  - `VRF_COORDINATOR`
  - `VRF_KEYHASH`
  - `VRF_SUB_ID`
  - `VRF_MIN_CONFIRMATIONS` (default 3)
  - `VRF_CALLBACK_GAS` (e.g., 400000)
- **Automation (optional):** add Chainlink Automation to call `closeRound` → `finalizeRound` → `drawWinners` → `startNextRound`. Admin UI can surface automation status.

## Notes & TODO (Optional Hardening)
- Add price caps (max native spend) to Lottery wrappers for Seaport/Uniswap.
- Mainnet-fork tests for Seaport and Uniswap paths.
- UI: add ticket counts and countdown timers.
