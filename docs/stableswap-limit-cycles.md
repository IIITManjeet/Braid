# When Newton–Raphson never converges

While porting Curve's StableSwap invariant to Move, the test suite turned up a
state where the solver runs forever. Not a slow convergence — a genuine
**limit cycle**, where the iteration steps around a small orbit of integers and
never satisfies its stopping condition.

This reproduces in Curve's own reference implementation. It is a property of the
algorithm, not of the port.

## The setup

StableSwap prices a pool by first solving its invariant `D`:

```
A·n^n·Σx  +  D  =  A·D·n^n  +  D^(n+1) / (n^n·Πx)
```

`D` cannot be isolated — for two coins it is a cubic — so it is found by
Newton–Raphson:

```
D_P  =  D^3 / (4·x₀·x₁)
D    ←  (Ann·S/AP + 2·D_P) · D  /  ((Ann − AP)·D/AP + 3·D_P)
```

seeded at `D = x₀ + x₁`, stopping when `|D − D_prev| ≤ 1`.

Over the reals this converges quadratically. It typically lands in 3–5 steps,
and the worst case observed across a 60,000-state sweep was 9.

## The failure

Every division above is **integer** division. That matters more than it looks:
the iteration is not a map on the reals that we sample, it is a map on the
integers in its own right. And a map on the integers need not have a fixed
point.

For reserves `(1e9, 1e6)` — a 1000:1 skew — at `A = 1`, the iterate ends up here:

```
… → 193404746 → 193404748 → 193404746 → 193404748 → …
```

A 2-cycle. The two values differ by 2, so `|D − D_prev| ≤ 1` never fires. Curve's
implementation exhausts its 255-iteration budget and reverts. A pool in this
state cannot be swapped against, cannot be quoted, and cannot be withdrawn from
by any path that needs `D`.

Longer orbits exist. For `(606615483488917, 302485337224)` at `A = 1`, the
iterate settles into a **5-cycle** spanning five consecutive integers:

```
93681094686182 → 93681094686185 → 93681094686183 → 93681094686186 → 93681094686184 → …
```

The true root lies inside that band. Every member is within a few units of it.
The iteration simply has nowhere to land.

## Why it happens

Newton's step lands within a fraction of a unit of the root, and the floor
truncates that fraction. Which way it truncates depends on which side of the
root the iterate is on, so the map alternates between rounding down from above
and rounding up from below. When the root sits near the middle of that band,
neither side is a fixed point and the iterate orbits it forever.

It needs extreme skew to appear: the reserve ratio has to be far enough out that
the constant-product term dominates, and `A` low enough that the curve is not
holding the pool near balance. Three of 60,000 random states hit it. Rare — and
a pool that hits it is permanently bricked, which makes rarity cold comfort.

## The fix

Detect the orbit, then pick a member of it.

`stable_math` keeps a ring buffer of the last 8 iterates. If a new value repeats
something still in the buffer, the sequence has closed a loop and will circle
forever, so the solver stops and returns.

**Which member it returns is a safety decision, not a coin flip.** The orbit's
members straddle the true root within a few units. The solver returns the
**maximum**:

- `D` is what the pool must maintain. Overstating it makes `get_y` solve for a
  larger post-trade balance on the output side, which pays the trader **less**.
- Understating it would pay out units the curve does not have — a small, repeatable
  leak, exactly the class of bug the rounding convention exists to prevent.

The scan starts at the matched index rather than covering the whole buffer,
because values seen *before* the orbit was entered are larger still — the
sequence descends toward the root — and including them would overstate `D` by
far more than a few units.

The same detector guards the `y` solver, which has the same structure and the
same exposure.

## Validation

A 60,000-state sweep over random reserves (10³ to 10¹⁶ per side) and eight
amplification settings from `A = 1` to `A = 10⁶`:

| | before | after |
|---|---|---|
| States where the solver fails to terminate | 2 | **0** |
| Orbits detected and resolved | — | 3 |
| Swaps where `D` decreased | 0 | **0** |

That last row is the one that matters. Resolving a cycle by taking the maximum
does not create a state where a swap lowers the invariant — which is the
property the pool asserts on-chain after every trade, and would abort on.

Three tests pin this down:

- `the_solver_resolves_states_where_the_reference_would_revert` — asserts the exact
  `D` for the 2-cycle and 5-cycle states above.
- `a_pool_in_a_limit_cycle_still_prices_swaps_safely` — trades against a pool in the
  2-cycle state and checks `D` does not fall.
- `newton_terminates_across_a_wide_range_of_states` — ratios out to 1:1000 at three
  amplifications.

## A related quirk

The same floor divisions make `get_d` **asymmetric in its arguments** at extreme
skew:

```
get_d(7, 999999) = 167134
get_d(999999, 7) = 167136
```

`D_P` accumulates its divisions one coin at a time, and floor division does not
commute with itself. This is harmless in a pool — coin order is fixed by the
struct, so a given pool always evaluates its own invariant the same way — but it
is pinned by a test so that a future refactor "tidying" the argument order gets
caught instead of silently repricing every pool.

## Takeaway

The interesting part is not that a fixed-point iteration failed to converge. It
is that *reasoning about it over the reals said it always would*. Quadratic
convergence is a theorem about a map on ℝ. Truncating every intermediate
produces a different map, on a different space, and that map's fixed points are
not guaranteed to exist at all.

Any on-chain solver — StableSwap `D` and `y`, a CLMM's tick math, a lending
protocol's rate curve — is subject to this. The stopping condition has to be
written for the map you actually iterate, not the one on the whiteboard.
