# Contention: what each chain charges for a shared venue

Sui and Aptos both execute transactions in parallel, and they disagree about
almost everything else: how parallelism is decided, when it is decided, and what
a developer has to do to get it. Braid has four venues on each chain, and they
sit in very different places on that spectrum. This is what that costs.

None of it shows up in the gas benchmarks. Gas prices one transaction in
isolation; contention is about what happens when a thousand of them want the
same object at the same time, and it is usually the thing that actually limits
a venue.

---

## The two models

**Sui decides before execution, from the transaction itself.** Every input is
either *owned* (one address controls it) or *shared*. A transaction touching
only owned objects needs no consensus at all — it is ordered by its owner, and
Sui can execute it immediately. A transaction touching a shared object must go
through consensus to fix its position in the sequence, because two transactions
mutating the same shared object have to agree on which went first.

So on Sui, contention is a *property of the object model*, visible in the
transaction before anything runs.

**Aptos decides during execution, optimistically.** Block-STM runs the whole
block in parallel, speculatively, tracking what each transaction read and wrote.
When it finds that transaction *j* read a location transaction *i* later wrote,
it aborts *j* and re-runs it. There is no declaration of intent; the scheduler
discovers the conflict.

So on Aptos, contention is a *property of the access pattern at runtime*, and it
costs re-execution rather than consensus.

## Where Braid's venues land

| Venue | Sui | Aptos |
|---|---|---|
| CPMM | shared `Pool` — consensus | one resource, write-write on every swap |
| StableSwap | shared `StablePool` — consensus | same |
| CLMM | shared `Pool` + dynamic fields per tick | same, plus per-tick table entries |
| CLOB | shared `Market` — consensus | same, plus per-level entries |
| Router | no state of its own | no state of its own |

The router is the one piece that is free on both. It holds no state — `Route` is
a value that lives for the length of one transaction — so it adds no contention
of its own. Whatever the legs contend on, they would have contended on anyway.

Everything else is a shared mutable object, and that is the honest summary: **in
its current shape, every Braid venue serialises.** Two traders swapping against
the same CPMM pool cannot execute in parallel on either chain. On Sui they queue
through consensus; on Aptos they collide in Block-STM and one re-runs.

That is normal for an AMM — a pool is a single shared accumulator and every swap
writes it — but it is worth saying plainly rather than implying the four venues
are independently scalable. They are independent of *each other*, which is what
makes the router's "the total is the sum of the legs" claim true. They are not
internally parallel.

## Where the order book is different, and worse

The CPMM writes two reserves. The order book, on a single taker fill, rewrites:

- the level it consumed, or removes it
- the crit-bit node structure, if removing that level changed the tree
- the taker's proceeds
- the maker's claimable balance

That is what the gas benchmark already shows on Sui — the book is the priciest
venue there because Sui charges for storage and the book rewrites the most
objects. The contention story is the same fact seen from the other side: more
written locations means a larger conflict footprint, so under Block-STM a book
fill is more likely to invalidate a concurrent transaction and force a re-run.

On Aptos this is sharpened by *where* the writes land. Every taker touches the
same best-price level, and every maker at that price shares it. Block-STM sees a
write-write conflict on one table entry and serialises the lot. The tree nodes
near the root have the same problem: they change whenever a level at the edge is
created or removed, so they are hot regardless of which price anyone traded at.

The generic fix is to stop accumulating into one location — Aptos ships
`Aggregator` for exactly this, a counter Block-STM can resolve without ordering
the writers. It works for totals. It does not work for a book, because a fill is
not a commutative increment: who gets filled depends on the order.

## What an owned-object design would change on Sui

This is the part Sui makes available and Braid does not currently use.

A resting order does not have to live inside the shared `Market`. It could be an
owned object held by the maker, with the market holding only the price index.
Then:

- **Placing an order** touches only objects the maker owns. No consensus. On
  Sui that is the fast path — sub-second, and it does not compete with anything.
- **Cancelling** is likewise owned-only.
- **Taking** still needs the shared market, because the taker must be ordered
  against other takers.

That splits the book's traffic into a large owned-object part that parallelises
freely and a small shared part that does not. For a venue where quotes churn far
more often than they trade — which is every real order book — that is the
difference that matters.

The cost is real: the matching engine can no longer simply mutate the maker's
order in place, because it does not own it. Designs that do this make the taker
produce a claim the maker settles later, which is more moving parts, a second
transaction for the maker, and a new class of bug around claims that are never
collected. Braid does not do this. `braid_clob` keeps orders inside the shared
`Market` and pays for it in contention, which is the simpler and slower choice.

Aptos has no equivalent lever. There are no owned objects in that sense; the
closest analogue is to shard the state — a table keyed so that unrelated traders
touch unrelated entries — which helps only when the access pattern is actually
disjoint. For a book converging on the best price, it is not.

## The sequencing the router forces

One more thing the router does to contention, which is easy to miss: a
four-venue route touches **all four venues in one transaction**.

On Sui, that means the transaction's shared-input set is every venue it routes
through, so it must be ordered against every other transaction touching any of
them. A route is strictly more contended than any single swap it replaces. The
split buys a better price and pays for it in scheduling.

On Aptos the same trade appears as a wider read/write footprint, so a routed
transaction is more likely to be the one Block-STM aborts and re-runs.

This is a genuine tension in the design and it is not resolved here. The
optimizer maximises output per order and is indifferent to how contended the
resulting transaction is. A production router would weigh them — sometimes the
two-venue split that clears is worth more than the four-venue split that
re-runs — which needs a cost model this project does not have.

## What would be needed to measure any of this

Everything above is reasoning from the execution models and from the write sets
the code actually produces. It is not measured, and the benchmark harness in
`bench/` cannot measure it: it times one transaction at a time.

Measuring it means submitting concurrent conflicting transactions and reading
what the chain did with them — on Aptos, comparing observed block throughput
against the serial baseline and watching the re-execution counters; on Sui,
comparing latency for an owned-object-only transaction against one that takes
the shared market. That is a different harness and a different kind of
deployment from the one this project has, and claiming numbers without it would
be inventing them.

## Further reading

- Block-STM: *Block-STM: Scaling Blockchain Execution by Turning Ordering
  Curse to a Performance Blessing* (Gelashvili et al.)
- Sui's owned/shared distinction and the single-owner fast path, in the Sui
  developer documentation on object ownership and consensus.
