# Benchmarks

Two questions: what does a trade through each venue cost on chain, and how
fast can the off-chain replica quote one?

```bash
python bench/gas.py sui                        # dry runs against the live Sui testnet pools
python bench/gas.py aptos --network local      # executes against scripts/aptos.py's venues
cargo run --release -p braid-bench             # from node/: quote latency
```

Raw output is in [`results/`](results).

## Gas per venue

Every row is a route through `braid_router`, so both chains do the same work:
an empty route (open, close, pay out: the router's own overhead), a single-leg
route through each venue at 100,000 TUSD, and one route splitting 100,000 four
ways. A venue's own cost is its row minus the empty route.

### Sui testnet, dry run, in MIST

| route | computation | storage | rebate | net | over empty |
|---|---:|---:|---:|---:|---:|
| empty route | 1,000,000 | 5,335,200 | 1,685,376 | 4,649,824 | 0 |
| cpmm | 1,000,000 | 7,562,000 | 3,889,908 | 4,672,092 | 22,268 |
| stable | 1,000,000 | 7,668,400 | 3,995,244 | 4,673,156 | 23,332 |
| clmm | 1,000,000 | 9,264,400 | 5,575,284 | 4,689,116 | 39,292 |
| clob | 1,000,000 | 10,450,000 | 6,749,028 | 4,700,972 | 51,148 |
| all four | 1,000,000 | 18,939,200 | 15,153,336 | 4,785,864 | 136,040 |

**Computation never moves.** Sui charges computation in buckets, and every
route here, all four legs included, fits in the smallest. What separates
the venues is storage. A leg rewrites the objects it touches, pays storage for
the new bytes and gets back the deposit on the old ones, so a venue's cost is
roughly the size of what it rewrites. The order book is the most expensive for
that reason, not because it computes more: a fill rewrites the price level,
the resting order and the maker's claim, each a dynamic-field object of its
own.

The empty route already costs about 4.6M MIST, mostly storage for the two
coins it creates and the treasury it rewrites. Against that, the whole
four-venue split adds 2.9%.

### Aptos localnet, executed, in gas units at 100 octas

| route | gas units | over empty | fee (octas) |
|---|---:|---:|---:|
| empty route | 13 | 0 | 1,300 |
| cpmm | 17 | 4 | 1,700 |
| stable | 18 | 5 | 1,800 |
| clmm | 23 | 10 | 2,300 |
| clob | 17 | 4 | 1,700 |
| all four | 29 | 16 | 2,900 |

The ordering changes. On Aptos the concentrated pool is the expensive venue
and the book is as cheap as the constant-product pool. A tick walk is real
computation, with bitmap-word lookups and `u256` fee-growth arithmetic, and
Aptos meters execution finely enough to see it. A book fill is a few table
writes, and Aptos meters a table write as one slot rather than re-storing a
whole object, so the book's large rewrite footprint on Sui disappears. The
Newton solver in the stable pool costs one unit more than `x * y = k`.

The route itself is cheap on both chains. On Aptos the four-way split costs
16 units over the empty route, less than the 23 that the four single-venue
rows add up to. Internal gas is rounded to whole units once per transaction,
so differences of a unit or two here are not meaningful.

These are localnet numbers, from a genesis built by the same CLI (7.2.0) as
the testnet deployment tooling, so the gas schedule is the release's own.

## Quote latency

`braid-bench` times the Rust replica one call at a time: every venue's quote
and a full `optimize` (the split across all four), against two states. The
router test world is what the Move route tests and the Aptos deployment trade.
The Sui testnet snapshot is the real state the first live route was planned
against, with every tick the concentrated pool held on chain. Amounts are
log-uniform from 1 to 16M, since a quote's cost grows with its size.

AMD Ryzen 7 5800H, Windows 11, rustc 1.96.1, release build, 200,000 samples
per venue. Microseconds:

| Sui testnet snapshot | p50 | p99 | p99.9 | max |
|---|---:|---:|---:|---:|
| cpmm | 0.10 | 0.20 | 0.50 | 21.3 |
| stable | 0.80 | 1.40 | 2.00 | 688.3 |
| clmm | 2.30 | 4.10 | 20.4 | 567.5 |
| clob | 0.10 | 0.20 | 0.40 | 10.2 |
| **optimize** | **1,755** | **3,861** | **6,493** | 24,160 |

The router test world gives similar figures, with `optimize` about 10%
slower; see [`results/latency.md`](results/latency.md).

- **A single quote is not the bottleneck.** Even the concentrated pool,
  walking ticks with 256-bit intermediates, has a p99 of about 4 µs. The
  constant-product and book figures sit at the Windows timer's 100 ns
  resolution, so read them as an upper bound.
- **Planning is.** `optimize` quotes every venue hundreds of times as it
  fills in chunks and then rebalances by halving transfers. At a p99 near
  4 ms, a node could re-plan every order on every block of either chain, but
  not thousands of orders on every block. The next speedup would come from
  quoting fewer times, for example by warm-starting from the previous block's
  split, not from faster quotes.
- **The max column is the OS**, not the code: single samples descheduled
  mid-call. p99.9 is the tail worth reading.
