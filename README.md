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

## Routing

```bash
python scripts/route.py run 6000000      # snapshot -> plan in Rust -> one PTB -> verify
```

**The split** (`node/crates/braid-route`). Venues do not interact, so a route's output is
exactly the sum of each venue's replica quote at its own allocation. The optimizer equalises
marginal output across venues on finite differences -- the curves are integer staircases, the
book moves in whole lots -- by filling in chunks at the best rate per unit consumed, then
rebalancing power-of-two transfers down to one unit. Every allocation is trimmed to what its
venue actually consumes, so a book handing back a partial lot does not make that input look
worthless. Against exhaustive search it lands within a unit per leg.

**The execution** (`move/sui/braid_router`). A `Route` is a hot potato: no abilities, so a
PTB that calls `begin` cannot complete without handing it to `finish`, which is where
`min_out` is enforced on the *total*. Legs pass zero minimums to the venues; a per-leg bound
would be the wrong check.

**The proof it lines up.** `braid-difftest` plans 25 orders against a Rust copy of the router
test world and emits Move tests that run each plan through the router at `min_out` equal to
the predicted output. All 25 pay exactly that.

## The headline test

A **differential fuzzer**. `node/crates/braid-quote` is a Rust replica of the pricing math --
a transliteration, not a reimplementation: where the Move widens to `u256` before dividing so
does the Rust, and where it floor-divides twice in sequence rather than once by a product, so
does the Rust. Floor division does not reassociate, so operation order is part of the spec.

`braid-difftest` generates random pool states and trades, computes each answer with the
replica, and emits them as Move test files. `sui move test` then runs every case through the
real Move VM. **A one-unit disagreement fails the build.** It covers every venue:

| Venue | Generated cases |
|---|---|
| CPMM | 742 formula checks |
| StableSwap | 1,087 formula checks |
| CLMM | 1,200 formula checks, plus 100 whole-pool scenarios -- random positions, then swaps across initialized ticks and empty bitmap words |
| CLOB | 50 order-book scenarios -- random books, quoted then executed in both directions |

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

The harness is verified against negative controls: flipping one `mul_div_floor` to
`mul_div_ceil` in the replica fails the generated suite immediately, and letting the CLMM
replica skip empty bitmap-word boundaries -- walking a sorted tick list, as a natural
reimplementation would -- fails 58 of the 100 pool scenarios.

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
move/sui/braid_clmm/     concentrated liquidity                                     [done]
move/sui/braid_clob/     central limit order book                                   [done]
move/sui/braid_router/   atomic multi-venue route execution                        [done]
move/aptos/braid_math/   phase 2: the Aptos port                                   [done]
move/aptos/braid_cpmm/   phase 2: the Aptos port                                   [done]
move/aptos/braid_stable/ phase 2: the Aptos port                                   [done]
node/crates/             Rust: replica, difftest generator, route optimizer         [done]
bench/                   gas costs per venue, p99 quote latency
docs/                    design notes, invariant derivations
```

Each `move/sui/*` folder is a separate Sui package: Sui publishes one package per transaction,
so `braid_math` is published first and the others import it as an on-chain dependency.

## Live on Sui testnet

Every venue package is published, and each venue has been exercised end to
end with real trades.

| Package | Address |
|---|---|
| `braid_math` | `0x7bb8f3e41cd60941b0df6fd139d6df65e1dd5128e3b5a9394ad726a4a2b2f72a` |
| `braid_cpmm` | `0xcaee4def84ca508c1f1e6269847a1b51798b1dfae7d07d1a0fef548676f675a2` |
| `braid_stable` | `0x9f4d6e25313f06958c36d0291de02e6ca1e3298c634fa35b0e6b47290b13f3b5` |
| `braid_clmm` | `0x53b3f796fa2716aee2a1b6a9e61bae58a728b8b0a5dddd10dfe7a7629a187034` |
| `braid_clob` | `0x7fd0dbcf91a111d4a86c50f10aee973085a7ee3aac13f10ad9ec6fe5202bee86` |
| `braid_router` | `0x3cb0239f0af24e7b8a27bedc5ceb010747b4180987e2402a3700b3774d9cf3f3` |
| `braid_test_coins` | `0x0e9be022ce9a17e896329ea6550698c1394b2d46e20c9d7a11ef27e7b3555699` |

A live TUSD/TUSDT pool at `A = 100`, 4 bps, seeded 1:1 with 1e9 a side:
`0x4deab90d8255e19e8ac72916d41198dff7b3767a18e02260e611b59a0fe8e76a`

The first swap through it
([`2g5GigCt...`](https://suiscan.xyz/testnet/tx/2g5GigCtPdPizEYJJffzGmY2rPHbHrC7X23gEq8QXF82))
put 1,000,000 TUSD in and returned **999,590** TUSDT, leaving `D` at
**2,000,000,400** -- up by exactly the 400-unit fee.

Both numbers match the Move test suite and the independent Python reference to
the unit. The chain, the tests, and the replica all agree.

A live TUSD/TETH concentrated pool at 30 bps, tick spacing 60, with a position
across ticks -600..600 holding 169,187,499 liquidity:
`0x5eb924a166883bc6296c5c9944208541f0c2e88d8831985c99a5afb141586d6c`

A swap through it
([`4ZB7s5AK...`](https://suiscan.xyz/testnet/tx/4ZB7s5AKpVa2VRcJyhoQzq4M5wNZktb9j3uVT2B74FUD))
put 100,000 TUSD in and returned **99,641** TETH for a fee of **300** -- exactly
30 bps -- moving the price from tick 0 to tick -12.

A live TETH/TUSD order book at a 1 bp tick, 10,000-unit lots and a 10 bp taker
fee: `0x396b0f0c0f36733ea9b3912b11f4037d399a2c117e03acb6106607c859fd1224`

Seeded with asks at 1.0001 / 1.0005 / 1.0010 and bids at 0.9999 / 0.9995, a
second address traded both ways in one transaction
([`9sP9ou28...`](https://suiscan.xyz/testnet/tx/9sP9ou28bWt268K4W8Q5egP9uWVxfxEKjdyUZbFKyRqk)).
3,000,000 TUSD cleared the first ask level and 99 lots of the second, returning
**2,987,010** TETH after a 2,990 fee and handing back the 9,305 that could not
buy a whole lot. 1,505,000 TETH sold 1,500,000 into the top bid for **1,498,350**
TUSD and returned the 5,000 of dust. Each `min_out` was set to the value
predicted from the Move math beforehand, so a one-unit shortfall would have
aborted. Afterwards both vaults held exactly what the remaining orders lock.

**One order, four venues.** With a CPMM and a StableSwap pool added on the same TUSD/TETH
pair, 6,000,000 TUSD was routed across all four in one transaction
([`38A5UsC4...`](https://suiscan.xyz/testnet/tx/38A5UsC44db3cfogzznA6d6y5bx6QuKnU5jXcMZqahJs)),
with `min_out` set to exactly the planned output:

| Venue | In | Out |
|---|---|---|
| CPMM | 26,509 | 26,290 |
| StableSwap | 2,180,665 | 2,168,303 |
| CLMM | 780,321 | 773,508 |
| CLOB | 3,012,505 | 3,006,990 |
| **Total** | **6,000,000** | **5,975,091** |

Every leg's on-chain event matched the Rust plan to the unit. The best venue that could take
the whole order alone, the stable pool, pays 4,899,130 -- the split returns 22% more, a figure
that says as much about how shallow these testnet pools are (5M a side) as about the router.
The snapshot and plan are committed under [`deployments/routes/`](deployments/routes), and
re-planning that snapshot reproduces the executed plan exactly.

Addresses and object ids are recorded in [`deployments/testnet.json`](deployments/testnet.json).
Redeploy or extend with `bash scripts/deploy.sh`.

## The Aptos port

The same exchange, on the other Move chain. `braid_math`, `braid_cpmm` and
`braid_stable` are live under `move/aptos/` and their suites are green: **162
tests on Sui, 163 on Aptos.**

The pricing math is the *same code* -- `cpmm_math.move` and `stable_math.move`
differ only by `let mut` becoming `let`, because Aptos Move has no `mut` on
locals. Better, the generated differential-fuzz corpora are byte-identical files:

```bash
diff move/sui/braid_cpmm/tests/generated_diff_tests.move \
     move/aptos/braid_cpmm/tests/generated_diff_tests.move   # empty
```

So the 1,829 cases the Rust replica produced now run against two independent
Move VMs and agree with both to the unit. A replica that matches one
implementation might have copied its bug; one that matches two is describing the
arithmetic.

`pool.move` is not a transliteration, and that is where the writeup lives. Sui
passes a shared object as `&mut Pool<A, B>`; Aptos keeps resources in global
storage, so the pool arrives as an `address` and the module must check it exists
-- which is the entire 162-vs-163 test difference, one test named
`a_swap_against_an_address_holding_no_pool_aborts`. Sui's LP token is its own
minting witness via `balance::create_supply`; Aptos's `coin::initialize` demands
a signer for the address that *declares* the type, so LP is a fungible asset
whose `MintRef` lives inside the pool and pool creation stays permissionless.
And Aptos's `FungibleAsset` has no abilities at all -- it is a hot potato, the
same trick `braid_router` uses for `Route`.

The StableSwap pool still returns **999,590** for 1,000,000 in: the number the
live Sui testnet swap below produced. Four implementations agree on it now.

```bash
bash scripts/get-aptos.sh      # vendors the Aptos CLI into .tools/
bash scripts/test-aptos.sh
```

Full comparison: [docs/aptos-port.md](docs/aptos-port.md).

## Notes from the build

- [Porting to Aptos Move](docs/aptos-port.md) -- what the dialect forces, and
  where the two chains genuinely disagree about what a program is.
- [When Newton-Raphson never converges](docs/stableswap-limit-cycles.md) --
  the StableSwap `D` solver has states where it orbits forever instead of
  converging, and Curve's own implementation reverts on them. What causes it,
  and how `braid_stable` resolves it safely.

## Toolchain

The Sui CLI is vendored into `.tools/` rather than installed globally, and is **not** committed
(~800MB). To reproduce it:

```bash
bash scripts/get-sui.sh
bash scripts/get-aptos.sh       # only needed for move/aptos
export PATH="$PWD/.tools:$PATH"
sui --version && aptos --version
```

Both CLIs pin an exact version, and on the Aptos side the framework `rev` in
each `Move.toml` is pinned to the tag that CLI was cut from — `aptos-core` ships
the compiler and the framework together, so a newer framework fails to parse on
an older compiler. Bump them as a pair.

Also required: Rust (1.96+) and Node 18+.

Every package's tests, in one go:

```bash
bash scripts/test.sh            # Sui: 570 Move tests, plus the Rust replica
bash scripts/test-aptos.sh      # Aptos: 163 Move tests
```

## Status

- [x] Repo, toolchain, `braid_math::full_math`
- [x] `braid_math::q64` — Q64.64 fixed-point
- [x] `braid_math` test suite (47 tests)
- [x] CPMM pool + swap (37 tests)
- [x] StableSwap pool + Newton-Raphson solver (46 tests)
- [x] Deploy to Sui testnet
- [x] Rust quote engine + differential fuzzer (1,829 generated cases)
- [x] CLMM: ticks, bitmap, fee growth, swap stepping, pool (125 tests)
- [x] CLOB: crit-bit tree, matching, custody and settlement (78 tests), live on testnet
- [x] Router: hot-potato route, Rust optimizer, CLMM and CLOB replicas, live four-venue route
- [x] Aptos port: `braid_math`, `braid_cpmm`, `braid_stable` (163 tests), dialect writeup
- [ ] Aptos port: `braid_clmm`, `braid_clob`, `braid_router`
- [ ] Deploy the Aptos packages to testnet
