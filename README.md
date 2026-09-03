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

A **differential fuzzer**. `node/crates/braid-quote` is a Rust replica of the pricing math --
a transliteration, not a reimplementation: where the Move widens to `u256` before dividing so
does the Rust, and where it floor-divides twice in sequence rather than once by a product, so
does the Rust. Floor division does not reassociate, so operation order is part of the spec.

`braid-difftest` generates random pool states and trades, computes each answer with the
replica, and emits them as Move test files. `sui move test` then runs every case through the
real Move VM. **1,829 cases; a one-unit disagreement fails the build.**

The generated files are committed on purpose. The RNG is seeded, so regenerating produces an
identical file unless a *value* moved -- and then the diff names the case and the delta. A
silent repricing becomes a reviewable line in a pull request.

```bash
cargo run -p braid-difftest    # regenerate, from node/
bash scripts/test.sh           # Move VM checks every case
```

**What it proves:** the two implementations do not diverge. That catches a mis-transliterated
operation order, a floor where the other has a ceil, a `u128` intermediate where the other
widened -- the class of bug where the off-chain quote engine promises a price the chain will
not honour.

**What it does not prove:** that either side is economically right. Two implementations can
agree and both be wrong. That is covered separately -- hand-derived fixtures, the invariant
properties (`k` and `D` never decrease), and for StableSwap a third implementation in Python
written from Curve's published reference rather than from this code.

The harness is verified against a negative control: flipping one `mul_div_floor` to
`mul_div_ceil` in the replica fails the generated suite immediately.

**Not yet wired:** reading return values back from the deployed bytecode. `sui client
--dev-inspect` on CLI 1.78 renders a dry run without return values, and the GraphQL
`simulateTransaction` field wants a protobuf-shaped transaction rather than serialized BCS.
The on-chain anchor for now is the real testnet swap below, whose result the replica
reproduces exactly.

## Layout

```
move/sui/braid_math/     Q64.64 fixed-point, mul_div with u256 intermediates, sqrt   [done]
move/sui/braid_cpmm/     constant-product pool                                      [done]
move/sui/braid_stable/   Curve-style stableswap                                     [done]
move/sui/braid_clmm/     concentrated liquidity                                     [in progress]
move/sui/braid_clob/     central limit order book
move/sui/braid_router/   atomic multi-venue route execution
move/aptos/              phase 2: the port, plus a dialect-comparison writeup
node/crates/             Rust: braid-quote replica + difftest generator        [in progress]
bench/                   gas costs per venue, p99 quote latency
docs/                    design notes, invariant derivations
```

Each `move/sui/*` folder is a separate Sui package: Sui publishes one package per transaction,
so `braid_math` is published first and the others import it as an on-chain dependency.

## Live on Sui testnet

All four packages are published, and the StableSwap pool has been exercised
end to end with a real swap.

| Package | Address |
|---|---|
| `braid_math` | `0x7bb8f3e41cd60941b0df6fd139d6df65e1dd5128e3b5a9394ad726a4a2b2f72a` |
| `braid_cpmm` | `0xcaee4def84ca508c1f1e6269847a1b51798b1dfae7d07d1a0fef548676f675a2` |
| `braid_stable` | `0x9f4d6e25313f06958c36d0291de02e6ca1e3298c634fa35b0e6b47290b13f3b5` |
| `braid_test_coins` | `0x0e9be022ce9a17e896329ea6550698c1394b2d46e20c9d7a11ef27e7b3555699` |

A live TUSD/TUSDT pool at `A = 100`, 4 bps, seeded 1:1 with 1e9 a side:
`0x4deab90d8255e19e8ac72916d41198dff7b3767a18e02260e611b59a0fe8e76a`

The first swap through it
([`2g5GigCt...`](https://suiscan.xyz/testnet/tx/2g5GigCtPdPizEYJJffzGmY2rPHbHrC7X23gEq8QXF82))
put 1,000,000 TUSD in and returned **999,590** TUSDT, leaving `D` at
**2,000,000,400** -- up by exactly the 400-unit fee.

Both numbers match the Move test suite and the independent Python reference to
the unit. The chain, the tests, and the replica all agree.

Addresses and object ids are recorded in [`deployments/testnet.json`](deployments/testnet.json).
Redeploy or extend with `bash scripts/deploy.sh`.

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
- [x] Deploy to Sui testnet
- [x] Rust quote engine + differential fuzzer (1,829 generated cases)
- [ ] CLMM (tick math done; liquidity, swap stepping, pool to come)
- [ ] CLOB, router
- [ ] Aptos port
