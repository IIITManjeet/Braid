# Braid

A multi-venue on-chain exchange and router, built on Sui Move and ported to Aptos Move,
with a Rust market-data node in front of it.

One order enters the router; it is split across four venues with different pricing math
and rejoined into a single atomic settlement — the braided-river model the name comes from.

## Why this shape

The project is deliberately scoped to cover three skills end-to-end:

| Skill | Where it lives |
|---|---|
| Move smart contracts, testnet-deployed | `move/sui/*`, later `move/aptos/*` |
| High-throughput WS/REST services in Rust | `node/crates` |
| DeFi pricing math, pool invariants, fixed-point | `braid_math`, `braid_cpmm`, `braid_stable`, `braid_clmm` |
| Orderbook mechanics | `braid_clob` |

## The four venues, in increasing order of math difficulty

1. **CPMM** — `x * y = k`. Exact-in and exact-out, fee charged on input, rounding in favour of the pool.
2. **StableSwap** — the Curve invariant, solved by Newton–Raphson for both `D` and `y`.
3. **CLMM** — concentrated liquidity: tick bitmap, `1.0001^tick` sqrt-price math, cross-tick swap stepping, fee-growth-inside accounting.
4. **CLOB** — critbit order book, price-time priority, GTC/IOC/FOK/post-only, self-trade prevention.

Then **`braid_router`** splits one order across all four to maximise output. The optimizer
(marginal-price equalisation) runs off-chain in Rust; the chain executes the pre-computed
route atomically under a slippage bound.

## The headline test

A **differential fuzzer**: generate random swaps, run each through the Rust quote engine *and*
through the on-chain Move code via `sui client dev-inspect`, and assert bit-exact agreement.
If the Rust replica and the chain ever disagree by one unit, the test fails.

## Layout

```
move/sui/braid_math/     Q64.64 fixed-point, mul_div with u256 intermediates, sqrt   [done]
move/sui/braid_cpmm/     constant-product pool                                      [done]
move/sui/braid_stable/   Curve-style stableswap                                     [done]
move/sui/braid_clmm/     concentrated liquidity                                     [next]
move/sui/braid_clob/     central limit order book
move/sui/braid_router/   atomic multi-venue route execution
move/aptos/              phase 2: the port, plus a dialect-comparison writeup
node/crates/             Rust: checkpoint ingest -> in-memory replica -> axum REST + WS
bench/                   gas costs per venue, p99 quote latency
docs/                    design notes, invariant derivations
```

Each `move/sui/*` folder is a separate Sui package: Sui publishes one package per transaction,
so `braid_math` is published first and the others import it as an on-chain dependency.

## Notes from the build

- [When Newton-Raphson never converges](docs/stableswap-limit-cycles.md) --
  the StableSwap `D` solver has states where it orbits forever instead of
  converging, and Curve's own implementation reverts on them. What causes it,
  and how `braid_stable` resolves it safely.

## Toolchain

The Sui CLI is vendored into `.tools/` rather than installed globally, and is **not** committed
(~800MB). To reproduce it:

```bash
bash scripts/get-sui.sh
export PATH="$PWD/.tools:$PATH"
sui --version
```

Also required: Rust (1.96+) and Node 18+. Aptos CLI is only needed for phase 2.

Every package's tests, in one go:

```bash
bash scripts/test.sh
```

## Status

- [x] Repo, toolchain, `braid_math::full_math`
- [x] `braid_math::q64` — Q64.64 fixed-point
- [x] `braid_math` test suite (47 tests)
- [x] CPMM pool + swap (37 tests)
- [x] StableSwap pool + Newton-Raphson solver (46 tests)
- [ ] Deploy to Sui testnet
- [ ] Rust quote engine + differential fuzzer
- [ ] CLMM, CLOB, router
- [ ] Aptos port
