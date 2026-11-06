# Pimd test coverage

The suite exercises the real `src/Pimd.sol` and its vendored ERC-20 implementation.
The supply oracle is the requested **1,000,000,000 × 10^18**, independent of the
contract's `INITIAL_SUPPLY` getter.

- `Pimd.t.sol` retains the existing deployment, metadata, mint-event, factory,
  exact-distribution, ERC-20 event, authorization, and failure-path tests.
- `Pimd.properties.t.sol` adds allowance boundary cases, caller identity checks,
  self-transfer rejection, retry after insufficient funds, and algebraic properties.
- `Pimd.invariant.t.sol` extends the existing four-actor balance/allowance model
  with targeted failure paths and productive delegated transfers.

The supplied Pashov and Trail of Bits references informed these five review passes:

| Review lens | Basis in the implementation | Property exercised |
| --- | --- | --- |
| Conservation | `Pimd.sol:10–14`; `ERC20._update` | Fixed supply; all tokens accounted for; no zero-address balance; exact per-actor balances. |
| State transitions | `ERC20.approve`, `transferFrom`, `_spendAllowance` | Replacement/revocation, finite allowance consumption, infinite allowance preservation, and atomic rollback of failed transfers. |
| Round trips and rounding | `ERC20.transfer` and `_update`; no fee or conversion functions | Transfers out and back restore balances without changing allowances. Splitting a delegated payment has the same effect as one payment. Returning spent tokens does not replenish approval. |
| Adversarial inputs | `ERC20._transfer`, `_approve`, `_spendAllowance` | Insufficient funds/authority, self-transfer over balance, revoked grants, zero recipients, maximum integers, and caller/origin confusion. |
| Token-specific behavior | `Pimd` constructor and inherited ERC-20 interface | Metadata and one-time deployer mint; zero/one/full-supply amounts; maximum finite versus infinite approvals; contract recipients do not burn supply. |

These properties are grounded in the requested fixed supply and the public ERC-20
behavior of this implementation. Infinite approvals and the precise custom errors
are OpenZeppelin-specific regression checks.

## Stateful campaign

The handler starts with four funded actors using actual token transfers. Its
balance and allowance expectations come from successful operations, never from
editing or copying the token's storage. The runner checks supply conservation and
the complete balance/allowance model after every handler call.

The ten selected actions are ordinary transfers, arbitrary approvals, delegated
spending, over-balance attempts, positive approve-and-spend operations, isolated
allowance failures, isolated balance failures, zero-recipient attempts, revocation
followed by rejected spending, and transfer round trips. Expected failures check
the relevant custom error; unexpected reverts fail the campaign.

Positive-spend and round-trip actions select a funded actor from the model, so they
always execute a positive amount. Other actions retain empty balances, zero-value
operations, and overlapping owner/spender/recipient roles. Round trips also check
the outward leg so that two no-op transfers cannot satisfy the property.

All successful handler transfers stay within the four-actor set. The invariant's
zero token-contract balance is therefore specific to this closed set; the separate
contract-recipient test explicitly exercises transfers to the token itself.

Inline settings pin the stateful campaign to 256 runs of depth 128 with
`fail-on-revert = true`, and the added stateless properties to 1,024 cases each.
New fuzz tests use bounded inputs without discarded assumptions.

## Reproduce offline

From the repository root, these commands keep generated files in the disposable
scratch directory:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_SEED=0x38363f061ef536409a0fa3117636561595f5e151b0723fedc208d976885708c9 forge test --offline
```

All delivered tests rely only on the project's existing vendored dependencies.
The factory/distribution fixture tests token movements; the supplied protected
launch suite separately owns the full PoolManager seed/swap integration.
