# Threat model

What Braid defends against, how, and — more usefully — what it does not.

This is a testnet project. The point of writing this down is not to claim the
code is safe to hold money; it is that most of the design decisions in it are
security decisions, and they are easier to review when they are stated as such
rather than left implicit in a rounding direction.

---

## 1. Value leaking through rounding

**The attack.** Integer division truncates. A swap that rounds its output *up*,
or its fee *down*, gives away a unit. A unit is nothing; a unit per fill,
ground by a bot across a million dust trades, is the pool.

**The defence.** There is no default rounding anywhere in `braid_math`. Every
call site names a direction, and the convention is absolute: **round in favour
of the pool.** Output floors, required input ceilings, fee ceilings, LP minted
floors, LP burned pays out floored.

The fee specifically rounds *up*, so a one-unit trade pays one unit rather than
zero. That closes the obvious grind — splitting one trade into many trades whose
individual fees each round away.

**Why you can believe it.** This is the one invariant that is machine-checked
rather than argued. `cpmm_math.spec.move` states it and `aptos move prove`
discharges it for every `u64`:

```
ensures (reserve_in + amount_in) * (reserve_out - result) >= reserve_in * reserve_out;
```

Rounding the payout up instead of down — one word — fails that post-condition.
See [the prover section of the README](../README.md#machine-checked-not-just-fuzzed).

## 2. Draining a pool

**The attack.** Find an input for which the pricing function returns the whole
of the opposite reserve, leaving the pool empty and the invariant at zero.

**The defence.** For constant product it is structural: the quotient
`net * reserve_out / (reserve_in + net)` has a denominator strictly larger than
its numerator's `net` factor, so the output is strictly below `reserve_out` for
any finite input. Also machine-checked: `ensures result < reserve_out`.

The exact-out direction asserts `amount_out < reserve_out` explicitly, because
draining the pool exactly would require infinite input.

## 3. The first-depositor donation

**The attack.** Be the first depositor. Withdraw down to one LP unit. Transfer
a large amount directly into the reserves, bypassing `deposit`. Every later
depositor's LP now rounds to zero, and their deposit is yours.

**The defence.** `MINIMUM_LIQUIDITY` (1,000 units) is burned on first deposit
and is never recoverable, so the share floor cannot be driven to one. The
donation has to exceed what it can extract.

This is the Uniswap V2 mitigation, and it is a mitigation rather than a fix: it
raises the cost of the attack, it does not make it impossible.

## 4. Getting a worse price than quoted

**The attack.** The classic sandwich. See the victim's transaction, move the
price against them, let them execute, move it back.

**The defence.** Every path that can pay out takes a `min_out` and aborts below
it. What matters is *where* the check sits: on the **total**, in `finish`, not
per leg.

A per-leg bound would be the wrong check. The router's whole premise is that
legs trade off against one another — a leg that underperforms is fine if
another overperforms, and a per-leg minimum would abort routes that deliver
exactly what was promised in aggregate. Legs therefore pass zero minimums to
the venues, and the guarantee lives on the sum.

**The type system enforces that the check happens at all.** `Route` has no
abilities — not `drop`, not `store`, not `key`. A programmable transaction that
calls `begin` cannot be *built* without a `finish` to hand the value to. You
cannot forget the slippage check; the code does not compile without it. On
Aptos, where there are no PTBs, the same structure holds inside a transaction
script: delete the `finish` and the script does not compile.

## 5. Self-trading the order book

**The attack.** Be your own counterparty to paint volume, or to move the
recorded price with no economic risk.

**The defence.** The book refuses a taker whose order would cross its own
resting order. This is why `scripts/aptos.py` and `scripts/route.py` both send
routes from a *second* account: the publisher owns the resting asks, and routing
from it would be a self-trade the book rejects. The deployment scripts creating
a separate trader is not a convenience, it is the test that this rule works.

## 6. A solver that never terminates

**The attack.** Find pool parameters for which the StableSwap Newton–Raphson
iteration does not converge. If the implementation loops unboundedly, that is
gas exhaustion; if it reverts, that is a denial of service on the pool.

**The defence.** The iteration is bounded, and the non-convergent states are
characterised rather than hoped away. Curve's own implementation reverts on
them. `braid_stable` resolves them instead — the analysis is in
[stableswap-limit-cycles.md](stableswap-limit-cycles.md).

This is the one place where the reference implementation and this one
deliberately differ, which is why it has its own document.

## 7. Arithmetic overflow

**The attack.** Choose reserves and amounts whose intermediate product exceeds
the width, wrapping to a small number and a nonsensical price.

**The defence.** Every multiply-then-divide widens to `u256` before dividing and
asserts the quotient fits on the way back down. `mul_div_ceil` computes
`n/d` plus a correction rather than `(n + d - 1)/d`, because that `+ d - 1` can
itself overflow `u256` when `n` is near the top of the range.

Machine-checked: the prover's `aborts_if` clauses say overflow happens *exactly*
when the true arbitrary-precision quotient exceeds the type's maximum, and never
otherwise.

## 8. Quoting a price the chain will not honour

**The attack.** Not adversarial, but the most likely real failure: the off-chain
router promises an output the on-chain math does not produce, and every route
aborts — or worse, quietly pays less.

**The defence.** The differential fuzzer. `braid-quote` is a transliteration of
the Move, and 3,029 generated cases are executed by *both* Move VMs. A one-unit
disagreement fails the build. The corpora are committed, so a repricing shows up
as a reviewable diff rather than a silent change.

Verified against negative controls: flipping one `mul_div_floor` to
`mul_div_ceil` fails immediately, and letting the CLMM replica walk a sorted
tick list instead of the bitmap — as a natural reimplementation would — fails
58 of the 100 pool scenarios.

---

## Deliberately unsafe

`braid_test_coins` shares its `TreasuryCap`. **Anyone can mint any amount.**
That is exactly right for a testnet faucet coin and exactly wrong for anything
else, and the module says so in its own doc comment. It is what lets the web
page mint a route's input in the same transaction that spends it.

Nothing in this repository should be deployed to a network where the tokens have
value without removing that package first.

## Not defended, because not present

- **Oracle manipulation.** There is no oracle. `spot_price` exists for display
  and for the router's initial comparison, and its doc comment says never to
  price a fill with it. Every fill is priced from reserves at execution time.
- **Flash loan attacks.** There is no lending, and no callback into user code
  mid-swap. A venue's state changes are complete before it returns.
- **Reentrancy.** Move has no dynamic dispatch into caller-controlled code, and
  the router holds the `Route` by value between legs. There is no point at which
  a partially-updated venue is observable.
- **Admin key compromise.** There are no admin functions, no pause, no fee
  switch, no upgrade authority retained. On Aptos each package is published to a
  resource account whose signer capability is discarded at publish, which makes
  the packages immutable and means nobody holds their keys.

  That is the right shape for a demonstration and the wrong shape for
  production: a real deployment wants a way to pause and a way to upgrade, and
  those wants bring a governance problem this project does not have because it
  declined to have any privileged operation at all.

## What this does not establish

The differential fuzzer proves the implementations agree. The prover proves the
constant-product math cannot violate its invariant. Neither proves the design is
*economically* sound — two implementations can agree and both be wrong, and an
invariant can hold while the market structure around it is exploitable.

The parts most likely to be wrong, in order: the CLMM's fee-growth-inside
accounting across tick crossings, the CLOB's custody arithmetic when an order is
partially filled and then cancelled, and the router's assumption that venue
outputs are independent — true here because no two venues share an object, and
false the moment two of them do.

None of this has been audited.
