"""Reference for braid_clmm::liquidity_math, used to derive test fixtures.

Position with liquidity L between sqrt-prices sa < sb (all Q64.64 raw):

    amount0 = L * (sb - sa) * 2^64 / (sa * sb)      the token0 leg
    amount1 = L * (sb - sa) / 2^64                  the token1 leg

Below the range the position is entirely token0; above it, entirely token1;
inside, the current price splits it.
"""
from decimal import Decimal, getcontext

getcontext().prec = 80
Q64 = 1 << 64
BASE = Decimal(10001) / Decimal(10000)
MAX_TICK = 689382
U256_MAX = (1 << 256) - 1

consts = [int((BASE ** (Decimal(-(2 ** i)) / 2)) * (1 << 128)) for i in range(20)]


def sqrt_price_at_tick(tick):
    a = abs(tick)
    ratio = 1 << 128
    for i, c in enumerate(consts):
        if a & (1 << i):
            ratio = (ratio * c) >> 128
    if tick > 0:
        ratio = U256_MAX // ratio
    return (ratio >> 64) + (0 if ratio % (1 << 64) == 0 else 1)


def ceil_div(n, d):
    q = n // d
    return q if n % d == 0 else q + 1


def amount0_delta(sa, sb, L, round_up):
    if sa > sb:
        sa, sb = sb, sa
    num = (L * (sb - sa)) << 64
    den = sa * sb
    return ceil_div(num, den) if round_up else num // den


def amount1_delta(sa, sb, L, round_up):
    if sa > sb:
        sa, sb = sb, sa
    num = L * (sb - sa)
    return ceil_div(num, Q64) if round_up else num >> 64


def amounts_for_liquidity(sp, sa, sb, L, round_up):
    if sa > sb:
        sa, sb = sb, sa
    if sp <= sa:
        return amount0_delta(sa, sb, L, round_up), 0
    if sp >= sb:
        return 0, amount1_delta(sa, sb, L, round_up)
    return amount0_delta(sp, sb, L, round_up), amount1_delta(sa, sp, L, round_up)


def liquidity_from_amount0(sa, sb, amount0):
    if sa > sb:
        sa, sb = sb, sa
    intermediate = (sa * sb) >> 64
    return (amount0 * intermediate) // (sb - sa)


def liquidity_from_amount1(sa, sb, amount1):
    if sa > sb:
        sa, sb = sb, sa
    return (amount1 << 64) // (sb - sa)


def liquidity_for_amounts(sp, sa, sb, a0, a1):
    if sa > sb:
        sa, sb = sb, sa
    if sp <= sa:
        return liquidity_from_amount0(sa, sb, a0)
    if sp >= sb:
        return liquidity_from_amount1(sa, sb, a1)
    return min(liquidity_from_amount0(sp, sb, a0), liquidity_from_amount1(sa, sp, a1))


if __name__ == "__main__":
    p0 = sqrt_price_at_tick(0)
    print(f"sqrt_price(0)      = {p0}")
    for t in (-1000, 1000, -100, 100, -60, 60):
        print(f"sqrt_price({t:>6}) = {sqrt_price_at_tick(t)}")

    sa = sqrt_price_at_tick(-1000)
    sb = sqrt_price_at_tick(1000)
    L = 1_000_000_000_000

    print("\n=== a symmetric position, L = 1e12, ticks -1000..1000 ===")
    for name, sp in [("below", sqrt_price_at_tick(-2000)),
                     ("at lower", sa),
                     ("at zero", p0),
                     ("at upper", sb),
                     ("above", sqrt_price_at_tick(2000))]:
        d = amounts_for_liquidity(sp, sa, sb, L, False)
        u = amounts_for_liquidity(sp, sa, sb, L, True)
        print(f"  {name:9} floor={d}  ceil={u}")

    print("\n=== single-sided legs ===")
    print(f"  amount0_delta(sa,sb,L,false) = {amount0_delta(sa, sb, L, False)}")
    print(f"  amount0_delta(sa,sb,L,true)  = {amount0_delta(sa, sb, L, True)}")
    print(f"  amount1_delta(sa,sb,L,false) = {amount1_delta(sa, sb, L, False)}")
    print(f"  amount1_delta(sa,sb,L,true)  = {amount1_delta(sa, sb, L, True)}")

    print("\n=== liquidity back out of amounts ===")
    a0, a1 = amounts_for_liquidity(p0, sa, sb, L, True)
    print(f"  deposit at price 1.0: amount0={a0} amount1={a1}")
    back = liquidity_for_amounts(p0, sa, sb, a0, a1)
    print(f"  liquidity_for_amounts -> {back}   (deposited L = {L}, delta {back - L})")
    print(f"  never exceeds L? {back <= L}")

    print(f"\n  liquidity_from_amount0(p0, sb, {a0}) = {liquidity_from_amount0(p0, sb, a0)}")
    print(f"  liquidity_from_amount1(sa, p0, {a1}) = {liquidity_from_amount1(sa, p0, a1)}")

    print("\n=== round-trip never mints value, across a sweep ===")
    bad = 0
    for tl in range(-5000, 5001, 250):
        for tu in range(tl + 250, 5001, 1000):
            lo, hi = sqrt_price_at_tick(tl), sqrt_price_at_tick(tu)
            for tp in (tl - 100, (tl + tu) // 2, tu + 100):
                sp = sqrt_price_at_tick(tp)
                x0, x1 = amounts_for_liquidity(sp, lo, hi, L, True)
                got = liquidity_for_amounts(sp, lo, hi, x0, x1)
                if got > L:
                    bad += 1
    print(f"  cases where recovered liquidity exceeded the deposit: {bad}")

    print("\n=== the property that actually matters ===")
    print("  credit L' = liquidity_for_amounts(paid), then re-price L' at ceil.")
    print("  The pool is safe iff that never exceeds what was paid.")
    bad = worst = 0
    checked = 0
    for tl in range(-5000, 5001, 250):
        for tu in range(tl + 250, 5001, 1000):
            lo, hi = sqrt_price_at_tick(tl), sqrt_price_at_tick(tu)
            for tp in (tl - 100, (tl + tu) // 2, tu + 100):
                sp = sqrt_price_at_tick(tp)
                paid0, paid1 = amounts_for_liquidity(sp, lo, hi, L, True)
                credited = liquidity_for_amounts(sp, lo, hi, paid0, paid1)
                need0, need1 = amounts_for_liquidity(sp, lo, hi, credited, True)
                checked += 1
                if need0 > paid0 or need1 > paid1:
                    bad += 1
                    worst = max(worst, need0 - paid0, need1 - paid1)
    print(f"  checked {checked} positions")
    print(f"  cases needing more than was paid: {bad}   worst shortfall: {worst} units")
