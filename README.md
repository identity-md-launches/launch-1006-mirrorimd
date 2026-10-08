# MirrorIMD (MIRROR)

`src/MirrorIMD.sol:MirrorIMD` is a fixed-supply ERC-20. Its constructor takes **no arguments** and mints **1,000,000,000 MIRROR**, with **18 decimals**, to `msg.sender` in a single mint. The exact supply in minor units is **1000000000000000000000000000** (`10^27`).

When a factory deploys the token, that factory receives all tokens, not the transaction origin or the requester. There is no initializer or required post-deployment call.

## Behavior and interface

| Function | Behavior |
| --- | --- |
| `name()`, `symbol()`, `decimals()` | `MirrorIMD`, `MIRROR`, `18` |
| `INITIAL_SUPPLY()`, `totalSupply()` | Fixed supply of `10^27` minor units |
| `balanceOf(account)` | Account balance in minor units |
| `transfer(to, amount)` | Moves exactly `amount` from the caller; returns `true` |
| `approve(spender, amount)` | Replaces the caller's allowance; returns `true` |
| `allowance(owner, spender)` | Remaining spending authorization |
| `transferFrom(from, to, amount)` | Moves exactly `amount`, using the caller's allowance; returns `true` |

Successful minting and transfers emit `Transfer`. Explicit approvals emit `Approval`. OpenZeppelin's ERC-6093 custom errors report invalid addresses, insufficient balances, or insufficient allowances. Failed transfers revert atomically, including any allowance change.

Zero-value transfers and self-transfers are supported. Transfers to the zero address and approvals to the zero address revert. A finite allowance decreases as it is spent; `type(uint256).max` remains unchanged. `transferFrom` requires allowance even when its caller is the token holder. As in the vendored OpenZeppelin implementation, spending allowance does not emit a second `Approval` event.

There are no transfer taxes, burns, rebases, additional minting entry points, owner, pause, blacklist, seizure, proxy, upgrade, or rescue powers. The token makes no external calls. Transfers do not invoke receiver callbacks.

## Assumptions and product context

The [linked Mirror site](https://mirrorimd.com/) was read on 2026-10-08. It describes a wallet-card product using IMD and identity.md data, with eligibility frozen before opening for seat holders or wallets holding at least 10 IMD. It does not specify additional MIRROR transfer mechanics.

This assignment delivers the requested token. Wallet-card rendering, historical eligibility collection, snapshot commitments, and any product-specific claims are separate application work. Eligibility is not a restriction on owning or transferring MIRROR. No external registry, recipient address, oracle, or owner configuration is needed to deploy this token.

The website describes Ethereum mainnet. This repository's direct-deployment rehearsal follows the supplied worker default of Sepolia (11155111), with local chain 31337 also allowed. It does not select or execute a production mainnet launch. The token itself is chain-independent; the network's deployment workflow determines its launch chain.

## Offline build and checks

Use Foundry 1.8.3 and cached solc 0.8.26. All imported Solidity dependencies and licenses are ordinary files under `lib/`; no package installation, submodule, network access, FFI, or contract filesystem permissions are needed.

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x20261008 --fuzz-runs 4096
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

The compiler is pinned to 0.8.26, matching the supplied protected test's pragma. Optimization uses 200 runs and Paris EVM output. `bytecode_hash = "none"` omits the metadata hash for launch reproducibility. `offline = true`, `ffi = false`, and `fs_permissions = []` apply by default. Dependency provenance and hashes are in `docs/DEPENDENCIES.md` and `docs/dependency-checksums.sha256`.

Tests cover exact constructor allocation, a CREATE2 factory deployment, mint/transfer/approval events, full and zero amounts, self-transfers, finite/infinite/revoked allowances, unauthorized spends, failure rollback, fixed supply, and absence of privileged entry points and forbidden runtime opcodes. Four fuzz properties cover transfer conservation and rejection of overdraw/overspend. A stateful invariant checks total supply and the sum of four holders' balances after sequences of transfers, approvals, and delegated transfers.

Launch-flow tests model exact factory/distributor/pool token transfers. They do not simulate Uniswap's pool accounting. The platform's full protected AMM test requires its own contracts, manifest, and launch environment, and remains a separate integration check.

## Deployment and operator responsibilities

For the IdentityMD custom-token launch, the network deployer should use `src/MirrorIMD.sol:MirrorIMD`, no constructor arguments (`[]`), and the exact supply above. The factory receives the entire supply and performs the network's allocations. The token does not itself split supply or implement a distributor. Pool parameters, the requester recipient, and economic allocations belong to the separate launch manifest; none are invented here.

To inspect the creation code locally:

```sh
forge inspect src/MirrorIMD.sol:MirrorIMD bytecode --offline
```

`script/Deploy.s.sol` is a standalone deployment/rehearsal script, not the network factory launch. It reads only `EXPECTED_CHAIN_ID`, checks the actual chain before deployment, and creates exactly one token between broadcast markers. The `0` default is accepted only on local chain 31337. Sepolia requires `EXPECTED_CHAIN_ID=11155111`. Tests call `deploy(uint256)` directly and never read or change environment variables.

For the authorized operator only, after independently configuring the provider and signer outside this repository, the standalone Sepolia command is:

```sh
EXPECTED_CHAIN_ID=11155111 forge script script/Deploy.s.sol:Deploy --broadcast
```

The broadcaster receives the supply in that standalone flow. For an IdentityMD launch, use the network factory workflow instead. No transaction was broadcast for this assignment, and no keys or RPC connection values are stored here.

After launch, there are no owner setters or maintenance transactions. The deployer must verify the deployed name, symbol, decimals, bytecode, mint event, and exact initial balance; publish/verify source; and complete the network's independent review and protected launch checks before release. Distribution and key custody remain the operator's responsibility. Holders should approve only intended spenders and amounts; when replacing an existing allowance, account for the standard ERC-20 approval ordering race. Tokens sent to this token contract or to a recipient unable to transfer them cannot be rescued by an administrator.

