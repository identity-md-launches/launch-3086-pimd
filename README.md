# Pimd (PIMD)

Pimd is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 PIMD with 18 decimals** to the immediate deployer. There are no constructor arguments or initialization calls.

## Contract and assumptions

| Property | Value |
| --- | --- |
| Source / Solidity identifier | `src/Pimd.sol:Pimd` |
| Name | `Pimd` |
| Symbol | `PIMD` |
| Decimals | `18` |
| Initial and permanent total supply | `1000000000000000000000000000` base units (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Initial recipient | Constructor `msg.sender` |
| Constructor arguments | None |
| Constructor value | `0` ETH |
| Owner / administrative roles | None |

The requested token uses ordinary ERC-20 transfers and allowances. Every successful transfer delivers exactly the requested amount. There are no transfer taxes, burns, rebases, vesting, transfer restrictions, subsequent minting, pause/blacklist functions, privileged seizure, upgrade mechanisms, or external callbacks. OpenZeppelin Contracts v5.1.0 supplies the ERC-20 behavior; the only custom behavior is setting the metadata and minting the initial supply.

Zero-value transfers and transfers to the sender are supported. Transfers to the zero address and approvals to a zero spender revert. Transfers exceeding the balance or delegated transfers exceeding the allowance revert atomically, including restoration of any allowance that would otherwise have been spent. Successful ERC-20 mutations return `true`; failures revert with OpenZeppelin's ERC-6093 custom errors.

Approvals replace the previous allowance. Finite allowances decrease on `transferFrom`; `type(uint256).max` represents an unlimited allowance and does not decrease. `approve` emits `Approval`; `transferFrom` emits `Transfer` without an additional `Approval` event when spending an allowance, as in OpenZeppelin v5. Consumers should query `allowance` for its current value.

## Build and test

Run from this repository's root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x38363f061ef536409a0fa3117636561595f5e151b0723fedc208d976885708c9 forge test
forge fmt --check
```

All Solidity dependencies are included as ordinary files in `lib/`. No dependency download, RPC, fork, wallet, environment configuration, filesystem permission, or FFI is needed by the tests. The seed above is provided to Foundry itself; no test reads or changes environment variables. The compiler is pinned by version in `foundry.toml`, with Cancun EVM, optimization enabled at 200 runs, and `bytecode_hash = "none"`.

`test/Pimd.t.sol` covers metadata, the single mint event, CREATE2 deployment through a factory, exact distribution and subsequent transfers, approvals/revocation, unlimited allowances, zero/self transfers, invalid addresses, insufficient balance/allowance, atomic failure, and rejection of mint/admin/upgrade calls. Seven fuzz tests run 1,024 cases each by default.

`test/Pimd.invariant.t.sol` independently models balances and allowances for four actors over randomized transfers, approvals, delegated transfers, and failed overspending. The two invariants check the model and conservation of the entire supply over 256 sequences of 64 calls. Each test has isolated setup and no dependence on execution order.

The local launch fixture checks token movement and factory receipt of the supply. It is not a Uniswap pool implementation. The supplied protected launch tests use a separate factory/PoolManager harness and are run by the launch verifier; that infrastructure is not included in this project.

## Deployment parameters and responsibilities

The intended launch chain is Ethereum (chain ID `1`). Deploy the compiled **`Pimd`** creation bytecode directly with no appended constructor arguments and no ETH. The constructor makes no external calls and requires no pre-existing contracts. There are no linked libraries or application contracts to deploy.

For inspection without sending a transaction:

```sh
forge inspect src/Pimd.sol:Pimd abi
forge inspect src/Pimd.sol:Pimd bytecode
```

The immediate creator receives **all** tokens. For the specified custom-token launch, this is the launch factory. When a contract creates Pimd on someone else's behalf, that contract receives the tokens; the caller and `tx.origin` do not. Do not deploy through an intermediate helper that cannot forward tokens.

The launch system is responsible for the separate manifest, attestation, transaction submission, source verification, pool creation, and distribution. The supplied launch economics allocate 10% to the swarm distributor, 80% to pool liquidity, and 10% to the requester's remainder recipient, `0xd6302976e590b9b947da8774b7f1246164e0ce98`. Those transfers occur after deployment and are not allocations inside the token constructor. Pool configuration and pricing belong to the launch system. No `launch.json` or broadcast script is part of this deliverable.

Before admitting the launch, the launch operator must verify the artifact and metadata above, total supply, the factory's initial balance, and the protected distribution, pool-seeding, buy/sell, and owner checks. An independent security review and post-deployment source verification remain release responsibilities. No deployment or transaction was performed for this assignment.

## After launch

There are no setters, owner actions, keepers, or other configuration steps. The initial recipient controls distribution of its holdings; thereafter each holder controls transfers and approvals for its own balance. No operator can mint more tokens, freeze holders, reverse transfers, upgrade the contract, or recover assets sent to the token contract.

Holders are responsible for recipient correctness and spender approvals. Standard ERC-20 approval replacement can race with an already-authorized spend; when changing an active allowance, revoke it first and confirm the resulting allowance before granting a replacement. Grant only the allowance intended for the chosen spender. The token has no native-currency deposit or asset-recovery interface.

See [DEPENDENCIES.md](DEPENDENCIES.md) for dependency provenance and [SECURITY_REVIEW.md](SECURITY_REVIEW.md) for the local review's scope and limitations.
