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
replica, and emits them as Move test files. Both Move VMs then run every case. **A one-unit
disagreement fails the build.** It covers every venue, on both chains:

| Venue | Generated cases |
|---|---|
| CPMM | 742 formula checks |
| StableSwap | 1,087 formula checks |
| CLMM | 1,200 formula checks, plus 100 whole-pool scenarios -- random positions, then swaps across initialized ticks and empty bitmap words |
| CLOB | 50 order-book scenarios -- random books, quoted then executed in both directions |
| Router | 25 optimizer plans, each executed at `min_out` equal to its predicted output |

The generated files are committed on purpose. The RNG is seeded, so regenerating produces an
identical file unless a *value* moved -- and then the diff names the case and the delta. A
silent repricing becomes a reviewable line in a pull request.

The three formula suites and the route suite are emitted once and written to both trees
unchanged, so `diff` between each `move/sui/*/tests/generated_*.move` and its `move/aptos/`
twin is empty. The CLMM and CLOB scenario suites build chain state, so they are rendered per
dialect from identically seeded streams: case `k` is the same pool and the same trades on
either chain.

```bash
cargo run -p braid-difftest    # regenerate both trees, from node/
bash scripts/test.sh           # the Sui VM checks every case
bash scripts/test-aptos.sh     # so does the Aptos one
```

**What it proves:** the implementations do not diverge. That catches a mis-transliterated
operation order, a floor where the other has a ceil, a `u128` intermediate where the other
widened -- the class of bug where the off-chain quote engine promises a price the chain will
not honour. With the port in place it is three implementations and two VMs, not two and one.

**What it does not prove:** that either side is economically right. Two implementations can
agree and both be wrong. That is covered separately -- hand-derived fixtures, the invariant
properties (`k` and `D` never decrease), and for StableSwap a third implementation in Python
written from Curve's published reference rather than from this code.

The harness is verified against negative controls: flipping one `mul_div_floor` to
`mul_div_ceil` in the replica fails the generated suite immediately, and letting the CLMM
replica skip empty bitmap-word boundaries -- walking a sorted tick list, as a natural
reimplementation would -- fails 58 of the 100 pool scenarios.

**Not yet wired on Sui:** reading return values back from the deployed bytecode. `sui client
--dev-inspect` on CLI 1.78 renders a dry run without return values, and the GraphQL
`simulateTransaction` field wants a protobuf-shaped transaction rather than serialized BCS.
The on-chain anchor there is the real testnet swap below, whose result the replica
reproduces exactly. On Aptos it is wired: `#[view]` quotes from a live node are compared with
the replica before every deployment route is sent.

## Layout

```
move/sui/braid_math/     Q64.64 fixed-point, mul_div with u256 intermediates, sqrt   [done]
move/sui/braid_cpmm/     constant-product pool                                      [done]
move/sui/braid_stable/   Curve-style stableswap                                     [done]
move/sui/braid_clmm/     concentrated liquidity                                     [done]
move/sui/braid_clob/     central limit order book                                   [done]
move/sui/braid_router/   atomic multi-venue route execution                        [done]
move/aptos/*             phase 2: the port -- all six, plus test coins and scripts [done]
node/crates/             Rust: replica, difftest generator, route optimizer, bench  [done]
node/crates/braid-server Rust: the quote, route and deployment API                 [done]
web/                     Next.js front end -- route explorer, deployments, bench    [done]
bench/                   gas costs per venue on both chains, p99 quote latency      [done]
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

All six packages, on the other Move chain, and green: **570 tests on Sui, 574 on
Aptos.** Counting only the five math and venue packages, 536 against 537.

The pricing math is the *same code*. `cpmm_math.move` is byte-identical to the
Sui file; the CLMM's eight pure modules -- tick math, the bitmap, fee growth, the
swap step, the signed integers -- moved across on `let mut` → `let` and four
non-ASCII characters in a comment, and pass 128 tests with no hand edits.

Better, the generated differential-fuzz corpora are byte-identical files:

```bash
diff move/sui/braid_cpmm/tests/generated_diff_tests.move \
     move/aptos/braid_cpmm/tests/generated_diff_tests.move   # empty
diff move/sui/braid_router/tests/generated_route_diff_tests.move \
     move/aptos/braid_router/tests/generated_route_diff_tests.move   # empty
```

So 3,029 formula cases from the Rust replica run against two independent Move
VMs and agree with both to the unit, and all 25 optimizer plans pay exactly their
predicted output through both routers. A replica that matches one implementation
might have copied its bug; one that matches two is describing the arithmetic.

`pool.move` and `market.move` are not transliterations, and that is where the
writeup lives. Sui passes a shared object as `&mut Pool<A, B>`; Aptos keeps
resources in global storage, so the pool arrives as an `address` and the module
must check it exists. Sui's LP token is its own minting witness; Aptos's
`coin::initialize` demands the declaring address's signer, so LP is a fungible
asset whose `MintRef` lives inside the pool. Aptos's `FungibleAsset` has no
abilities at all -- a hot potato, the same trick `braid_router` uses for `Route`.
And two hard boundaries Sui does not draw: a reference into global storage cannot
be returned, and `move_to` on a type is confined to the module that declares it.

The StableSwap pool still returns **999,590** for 1,000,000 in: the number the
live Sui testnet swap above produced. Four implementations agree on it now.

**The router ports, and its guarantee survives.** On Sui, `Route` has no abilities, so a
PTB that calls `begin` cannot complete without handing it to `finish`, where `min_out` is
enforced on the total. Aptos has no PTBs, but it has **transaction scripts**: compiled
Move whose `main` composes public calls in one transaction, verified like any module.
[`route_a_to_b.move`](move/aptos/braid_router/scripts/route_a_to_b.move) is the Sui PTB
almost line for line; remove its `finish` and it no longer compiles.

**Deploying found a real difference.** Three packages have a module named `pool`, and
Aptos keys modules by `(address, name)`, so they cannot share an account -- the second
publish aborts with `EMODULE_NAME_CLASH`. [`scripts/aptos.py`](scripts/aptos.py) puts each
package in its own resource account, seeds the four venues exactly as the router tests do,
plans a route offline in Rust, checks the live `#[view]` quotes against the plan, and sends
it with `min_out` equal to the prediction.

```bash
bash scripts/get-aptos.sh              # vendors the Aptos CLI into .tools/
bash scripts/test-aptos.sh
python scripts/aptos.py all 8000000    # needs a funded `braid-testnet` profile
```

## Live on Aptos testnet

All seven packages are published, one resource account each, and an 8,000,000
TUSD route through all four venues
([`0xb7827e45...`](https://explorer.aptoslabs.com/txn/0xb7827e4579e47ba3ba788e847a29b09b84977837f0ca2de6b8f7eddc07898716?network=testnet))
matched the plan to the unit on every leg:

| Venue | In | Out |
|---|---|---|
| CPMM | 8,192 | 8,160 |
| StableSwap | 1,867,704 | 1,863,389 |
| CLMM | 120,904 | 120,455 |
| CLOB | 6,003,200 | 5,994,000 |
| **Total** | **8,000,000** | **7,986,004** |

`min_out` was 7,986,004 -- the prediction exactly, so a one-unit shortfall on any
leg would have aborted the whole transaction. Before sending, each venue's live
`#[view]` quote was compared with the plan. Publishing all seven packages cost
734,795 gas units; the route itself cost 10,198.

The venues are seeded to exactly `braid_router::test_world`, so the whole thing
is a prediction made offline and then checked on chain:

```bash
cargo run -p braid-route -- --test-world 8000000    # 7986004, before anything is sent
```

That is the same number the localnet run produced, leg for leg -- and the same
number the generated route tests hold both Move VMs to. Addresses and
transactions are in
[`deployments/aptos-testnet.json`](deployments/aptos-testnet.json).

Full comparison: [docs/aptos-port.md](docs/aptos-port.md).

## The web front end

```bash
bash scripts/web.sh          # API on :8080, page on http://localhost:3000
bash scripts/web.sh --dev    # same, with Next's hot reloading
```

Two processes, because they are two different things.

`node/crates/braid-server` is a thin axum shell over `braid-quote` and
`braid-route` -- the same crates the differential fuzzer checks against both
Move VMs. It owns no pricing of its own, so a number on the page is a number
the generated Move tests are holding the chain to. Reimplementing any of it in
TypeScript would throw the guarantee away, so none of it is.

`web/` is a Next.js app that draws it, and proxies `/api/*` to the server so
the page is same-origin. Five views:

- **Route** -- enter an order and watch it split. The leg table shows each
  venue's allocation, what it actually consumed, and its *marginal* rate: the
  output for one more unit there, per unit consumed. The optimizer stops when
  those are as equal as an integer staircase permits, so the table is the
  argument, not a summary of it. Idle venues show what they would pay for the
  next unit -- if one of those were above a leg in use, the split would be
  wrong. The chart plots effective price, output per unit of input, across four
  decades of order size: the book is worthless below one lot and steps as lots
  fill, and the concentrated pool falls away where it runs out of range.
- **Venues** -- the state each venue prices from: reserves, every initialized
  tick, every resting book level.
- **Deployments** -- the Sui testnet packages, pools and the transactions that
  exercised them, with explorer links, plus the Aptos deployments.
- **Benchmarks** -- gas per venue, one chart per chain. Never one chart with
  two axes: MIST and Aptos gas units are different measures. The bars show each
  route's cost *over an empty route*, because the fixed per-transaction cost is
  most of the Sui number and plotting totals hides the venues entirely.
- **Verification** -- the generated corpora, counted from the committed files
  at request time rather than quoted from this README, and whether each pair of
  Sui/Aptos files is byte-identical.

**Venue state comes from one of two places.** The *router test world* is the
fixture the generated route tests run against, and the state the Aptos
deployment seeds to -- reproducible, offline, and not executable because there
is no object to point at. *Sui testnet* starts from the snapshot committed
under `deployments/routes/`, which is what the first four-venue route was
planned against; that route moved those pools, so the page labels it a record
rather than current state. **Refresh chain** re-reads the venues through
`scripts/route.py snapshot` and replaces it.

**Executing.** With a live snapshot and a Sui wallet, the page builds the same
programmable transaction `scripts/route.py execute` does -- mint the input,
`begin`, one call per leg, `finish`, transfer back -- and hands it to the
wallet through dApp Kit. `Route` has no abilities, so a PTB that opens one
cannot be built without the `finish` that enforces `min_out` on the total; the
page cannot omit that check even if it wanted to. The input coin is minted in
the same transaction that spends it, which works only because
`braid_test_coins` shares its `TreasuryCap` on purpose -- testnet faucet
behaviour, documented in that package as never-on-mainnet. A transaction the
chain rejects still comes back with a digest, and the page says so rather than
reporting success: a route that cannot pay its `min_out` aborts whole. The
exact `sui client ptb` command is shown beside the button, which is also the
path when no wallet is installed.

Signing needs a wallet and a wallet needs a person, so that last step cannot be
covered by a test. Everything before it can:

```bash
cd web && npm run dry-run        # needs braid-server running
```

`web/scripts/dry-run-route.mts` reads live venue state, plans an order, builds
the transaction with `lib/buildRoute.ts` -- the module the page uses, not a copy
-- and asks the chain to execute it without a signature. Nothing is sent. It
then compares every `LegExecuted` event against the Rust prediction, the same
check `scripts/route.py execute` makes after a real send. A recent run, against
live pools:

```
venue      in (plan)  in (chain)  out (plan) out (chain)
cpmm           35984       35984       35247       35247  ok
stable        784404      784404      769456      769456  ok
clmm         1179612     1179612     1155970     1155970  ok
total                                1960673     1960673  ok
```

The Sui side talks **gRPC**, not JSON-RPC: public fullnodes have retired their
JSON-RPC methods, and building a transaction against one now fails with
`Method not found`.

## Deploying it

```bash
docker build -t braid .
docker run -p 3000:3000 braid      # http://localhost:3000
```

One image, both processes, one origin. The API and the page run side by side
behind port 3000, so `/api/*` is same-origin exactly as it is locally, and
`docker-entrypoint.sh` treats either process exiting as the container exiting --
a half-running Braid serves pages whose every number is an error, which is worse
than being down and restarted.

Alpine throughout, so the API is a static musl binary; nothing in
`braid-server` links C. The image carries `deployments/`, `bench/results/` and
`move/` because the API reads them at request time -- the verification page
counts the generated corpora from the files rather than repeating a number, and
that should stay true inside the image.

**What the deployed build cannot do is read live chain state.** That needs the
Sui CLI, which is ~800MB and vendored rather than installed. Rather than ship a
button that fails, the server reports the capability from `/api/health` and the
page hides its refresh control and says where to get it:

```bash
bash scripts/web.sh    # locally, with the CLI: live reads and executable routes
```

The committed snapshot and the offline router test world work either way, so
the explorer, the deployments, the benchmarks and the verification counts are
all fully live on the deployed site.

Two host configs are checked in, both free-tier:
[`render.yaml`](render.yaml) (Blueprint; sleeps when idle and cold-starts on the
next request) and [`fly.toml`](fly.toml) (`fly deploy`; scales to zero). The
image is host-agnostic -- anything that runs a container will do.

## Benchmarks

[`bench/`](bench) measures gas per venue on both chains and the replica's quote latency.
On Sui a swap's cost is almost entirely storage -- computation never leaves the smallest
bucket -- so the order book, which rewrites the most objects, is the priciest venue. On
Aptos the concentrated pool's tick walk is. A single quote takes 4 µs at p99; planning a
four-way split takes 4 ms, because the optimizer quotes hundreds of times.

## Notes from the build

- [Porting to Aptos Move](docs/aptos-port.md) -- what the dialect forces, and
  where the two chains genuinely disagree about what a program is.
- [Benchmarks](bench/README.md) -- what a trade costs on each chain, and why
  the two chains rank the venues differently.
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

The front end needs Node 18+ as well; `scripts/web.sh` installs its
dependencies on first run.

Every package's tests, in one go:

```bash
bash scripts/test.sh            # Sui: 570 Move tests, plus the Rust replica
bash scripts/test-aptos.sh      # Aptos: 574 Move tests
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
- [x] Aptos port: all four venues plus `braid_math` (537 tests), dialect writeup
- [x] `braid-difftest` emits both dialects; the formula corpora are byte-identical
- [x] Aptos port: `braid_router`, with transaction scripts in place of PTBs (36 tests)
- [x] Aptos deployment tooling: per-package resource accounts, seeding, a verified route (localnet)
- [x] Benchmarks: gas per venue on both chains, quote and planning latency
- [x] Web front end: Rust quote/route API, Next.js page, wallet execution
- [x] Aptos testnet: all seven packages published, four-venue route matching the plan
