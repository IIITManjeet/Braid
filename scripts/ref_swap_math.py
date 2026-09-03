"""Reference for braid_clmm::swap_math.

Two jobs:

  1. Move the sqrt-price when a known amount goes in or out.
  2. Take one step of a swap, bounded by the next tick boundary.

Rounding must always leave the pool no worse off, so this checks each
direction against exact rational arithmetic rather than asserting it.
"""
from fractions import Fraction
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from liq import sqrt_price_at_tick, amount0_delta, amount1_delta, ceil_div  # noqa: E402

Q64 = 1 << 64
BPS = 10_000


# --------------------------------------------------------------------------
# Price movement
# --------------------------------------------------------------------------

def next_sqrt_price_from_amount0_in(sp, L, dx):
    """Token0 goes in, so the price falls.

    Exact:  sp' = L*sp*2^64 / (L*2^64 + dx*sp)

    Computed as  (L<<64) / ((L<<64)/sp + dx)  -- the inner division first, so
    no intermediate can exceed u256. Both the inner truncation and the outer
    ceil push sp' *up*, i.e. the price moves less, i.e. less token1 leaves.
    """
    if dx == 0:
        return sp
    num = L << 64
    return ceil_div(num, num // sp + dx)


def next_sqrt_price_from_amount1_in(sp, L, dy):
    """Token1 goes in, so the price rises.  sp' = sp + dy*2^64/L, rounded down."""
    if dy == 0:
        return sp
    return sp + ((dy << 64) // L)


def next_sqrt_price_from_amount1_out(sp, L, dy):
    """Token1 goes out, so the price falls.  Quotient rounds up, so the price
    falls further and the trade costs more token0."""
    if dy == 0:
        return sp
    step = ceil_div(dy << 64, L)
    assert sp > step, "price would cross zero"
    return sp - step


def exact_next_sqrt_price_from_amount0_in(sp, L, dx):
    return Fraction(L * sp * Q64, L * Q64 + dx * sp)


# --------------------------------------------------------------------------
# One step of a swap
# --------------------------------------------------------------------------

def compute_swap_step(sp, target, L, amount_remaining, fee_bps):
    """Exact-in. Returns (sqrt_next, amount_in, amount_out, fee)."""
    zero_for_one = sp >= target

    remaining_less_fee = amount_remaining - ceil_div(amount_remaining * fee_bps, BPS)

    if zero_for_one:
        to_target = amount0_delta(target, sp, L, True)
    else:
        to_target = amount1_delta(sp, target, L, True)

    if remaining_less_fee >= to_target:
        sqrt_next = target
        amount_in = to_target
    else:
        amount_in = remaining_less_fee
        if zero_for_one:
            sqrt_next = next_sqrt_price_from_amount0_in(sp, L, remaining_less_fee)
        else:
            sqrt_next = next_sqrt_price_from_amount1_in(sp, L, remaining_less_fee)

    reached = sqrt_next == target

    if zero_for_one:
        if not reached:
            amount_in = amount0_delta(sqrt_next, sp, L, True)
        amount_out = amount1_delta(sqrt_next, sp, L, False)
    else:
        if not reached:
            amount_in = amount1_delta(sp, sqrt_next, L, True)
        amount_out = amount0_delta(sp, sqrt_next, L, False)

    if not reached:
        # The step consumed everything left; the fee is whatever is not input.
        fee = amount_remaining - amount_in
    else:
        fee = ceil_div(amount_in * fee_bps, BPS - fee_bps)

    return sqrt_next, amount_in, amount_out, fee


if __name__ == "__main__":
    P0 = sqrt_price_at_tick(0)
    L = 1_000_000_000_000

    print("=== price movement ===")
    for dx in (1_000_000, 1_000_000_000, 100_000_000_000):
        got = next_sqrt_price_from_amount0_in(P0, L, dx)
        exact = exact_next_sqrt_price_from_amount0_in(P0, L, dx)
        print(f"  dx={dx:>15}  sp'={got:>22}  exact={float(exact):.4f}  "
              f"conservative={'yes' if got >= exact else 'NO'}")
    for dy in (1_000_000, 1_000_000_000):
        got = next_sqrt_price_from_amount1_in(P0, L, dy)
        exact = P0 + Fraction(dy * Q64, L)
        print(f"  dy={dy:>15}  sp'={got:>22}  conservative={'yes' if got <= exact else 'NO'}")

    print("\n=== conservatism sweep (price must never move too far) ===")
    bad0 = bad1 = 0
    for tick in range(-20000, 20001, 977):
        sp = sqrt_price_at_tick(tick)
        for liq in (10**9, 10**12, 10**15):
            for amt in (1, 10**3, 10**6, 10**9, 10**12):
                g = next_sqrt_price_from_amount0_in(sp, liq, amt)
                if g < exact_next_sqrt_price_from_amount0_in(sp, liq, amt):
                    bad0 += 1
                g1 = next_sqrt_price_from_amount1_in(sp, liq, amt)
                if g1 > sp + Fraction(amt * Q64, liq):
                    bad1 += 1
    print(f"  token0-in cases where the price fell too far : {bad0}")
    print(f"  token1-in cases where the price rose too far : {bad1}")

    print("\n=== one swap step, tick 0 -> tick -100, L=1e12, 30bps ===")
    target = sqrt_price_at_tick(-100)
    for amt in (1_000_000, 100_000_000, 10_000_000_000):
        sn, ain, aout, fee = compute_swap_step(P0, target, L, amt, 30)
        hit = "target" if sn == target else "partial"
        print(f"  in={amt:>14}  -> next={sn:>22} {hit:>8}  "
              f"in={ain:>13} out={aout:>13} fee={fee}")

    print("\n=== the same, upward (token1 in) ===")
    target_up = sqrt_price_at_tick(100)
    for amt in (1_000_000, 100_000_000, 10_000_000_000):
        sn, ain, aout, fee = compute_swap_step(P0, target_up, L, amt, 30)
        hit = "target" if sn == target_up else "partial"
        print(f"  in={amt:>14}  -> next={sn:>22} {hit:>8}  "
              f"in={ain:>13} out={aout:>13} fee={fee}")

    print("\n=== a step never spends more than it was given ===")
    over = 0
    for tick in range(-5000, 5001, 313):
        sp = sqrt_price_at_tick(tick)
        tgt = sqrt_price_at_tick(tick - 100)
        for amt in (1, 10**4, 10**7, 10**10, 10**13):
            _, ain, _, fee = compute_swap_step(sp, tgt, L, amt, 30)
            if ain + fee > amt:
                over += 1
    print(f"  cases where amount_in + fee exceeded the budget: {over}")
