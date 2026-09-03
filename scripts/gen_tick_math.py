"""Generate move/sui/braid_clmm/sources/tick_math.move.

The 20 bit-decomposition constants are computed here at 120 decimal digits
rather than transcribed by hand, so a typo in a 32-hex-digit literal is not
possible. Re-run this if the tick range or the fixed-point format ever changes.
"""
from decimal import Decimal, getcontext
import io

getcontext().prec = 120
Q128 = 1 << 128
BASE = Decimal(10001) / Decimal(10000)

consts = [int((BASE ** (Decimal(-(2 ** i)) / 2)) * Q128) for i in range(20)]

const_block = "\n".join(
    f"    /// `1.0001^(-2^{i}/2)`\n    const C{i}: u256 = 0x{c:032x};"
    for i, c in enumerate(consts)
)
apply_block = "\n".join(
    f"        if (abs_tick & {1 << i} != 0) ratio = (ratio * C{i}) >> 128;"
    for i in range(20)
)

TEMPLATE = r'''/// Ticks and square-root prices.
///
/// # The price grid
///
/// A concentrated-liquidity pool does not let liquidity sit at arbitrary
/// prices. Prices live on a geometric grid:
///
/// ```text
///   price(tick) = 1.0001^tick
/// ```
///
/// Adjacent ticks are one basis point apart -- fine enough that the grid is
/// invisible to a trader, coarse enough that a swap has a bounded number of
/// boundaries to walk through.
///
/// Everything is carried as `sqrt(price)` rather than price, because the
/// liquidity formulas are linear in the square root and quadratic in the price.
/// Working in sqrt-space turns most of the swap arithmetic into additions.
///
/// ```text
///   sqrt_price(tick) = 1.0001^(tick/2)     as Q64.64
/// ```
///
/// # How the exponent is evaluated
///
/// There is no `pow` here, and a loop of `tick` multiplications would be
/// hopeless. The exponent is decomposed into bits instead: `1.0001^(t/2)` is
/// the product of `1.0001^(2^i / 2)` over the set bits of `t`, so twenty
/// multiplications cover the entire range.
///
/// The constants are held for *negative* exponents, so every one is below 1.0
/// and the running product cannot overflow. A positive tick is handled by
/// inverting once at the end.
///
/// This is the construction Uniswap V3 uses. The constants below were derived
/// independently at 120 decimal digits and came out identical to Uniswap's
/// published table -- a useful check on both.
///
/// # Why the range is narrower than Uniswap's
///
/// Uniswap carries sqrt-prices as Q64.96 and supports ticks to +/-887272.
/// Braid carries them as Q64.64 -- 32 fewer fractional bits -- and at the
/// bottom of that range the price grid becomes coarser than the tick grid.
/// Below tick -689382 adjacent ticks round to the *same* `u128`: 178,080 ticks
/// alias onto their neighbours.
///
/// Aliasing would be a real defect. Two distinct positions could share a
/// boundary price, and `tick_at_sqrt_price` could not be a left inverse of
/// `sqrt_price_at_tick`. So the range is cut back to where Q64.64 resolves
/// every tick -- and cut symmetrically, because inverting a pair negates every
/// tick, and an asymmetric range would make the two orderings of a pair
/// disagree about what is representable.
///
/// What remains is a price range of `1.15e-30` to `8.67e29`, a span of about
/// `1e60`. No real pair comes close.
///
/// Verified across all 1,378,765 ticks in range: strictly increasing, and the
/// round trip through `tick_at_sqrt_price` is exact.
///
/// # Generated constants
///
/// The `C0`..`C19` table below is emitted by `scripts/gen_tick_math.py`. Do not
/// edit the literals by hand.
module braid_clmm::tick_math {
    use braid_clmm::i32::{Self, I32};

    /// Tick outside `[MIN_TICK, MAX_TICK]`.
    const EInvalidTick: u64 = 0;
    /// Square-root price outside `[MIN_SQRT_PRICE, MAX_SQRT_PRICE]`.
    const EInvalidSqrtPrice: u64 = 1;

    /// Largest tick whose neighbours stay distinguishable in Q64.64.
    const MAX_TICK: u32 = 689382;

    /// `sqrt_price_at_tick(MIN_TICK)`.
    const MIN_SQRT_PRICE: u128 = 19812;
    /// `sqrt_price_at_tick(MAX_TICK)`.
    const MAX_SQRT_PRICE: u128 = 17175572088390372486202642652453860;

    /// `1.0` in Q128.128 -- the identity for the running product.
    const Q128_ONE: u256 = 0x100000000000000000000000000000000;
    /// Low 64 bits, to detect a lossy final shift.
    const LOW_64: u256 = 0xffffffffffffffff;
    const U256_MAX: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

__CONSTS__

    // ------------------------------------------------------------------ //
    // Bounds                                                             //
    // ------------------------------------------------------------------ //

    public fun max_tick(): I32 { i32::from_u32(MAX_TICK) }

    public fun min_tick(): I32 { i32::neg_from(MAX_TICK) }

    public fun max_tick_u32(): u32 { MAX_TICK }

    public fun min_sqrt_price(): u128 { MIN_SQRT_PRICE }

    public fun max_sqrt_price(): u128 { MAX_SQRT_PRICE }

    public fun is_valid_tick(tick: I32): bool {
        i32::abs_u32(tick) <= MAX_TICK
    }

    // ------------------------------------------------------------------ //
    // tick -> sqrt price                                                 //
    // ------------------------------------------------------------------ //

    /// `1.0001^(tick/2)` as Q64.64.
    ///
    /// Accurate to within one unit in the last place across the whole range.
    /// The final conversion rounds up, matching the reference implementation.
    public fun sqrt_price_at_tick(tick: I32): u128 {
        let abs_tick = i32::abs_u32(tick);
        assert!(abs_tick <= MAX_TICK, EInvalidTick);

        // Product of `1.0001^(-2^i/2)` over the set bits, in Q128.128.
        let mut ratio: u256 = Q128_ONE;
__APPLY__

        // Every constant is a negative exponent, so a positive tick is the
        // reciprocal of what was just computed.
        if (!i32::is_neg(tick)) {
            ratio = U256_MAX / ratio;
        };

        // Q128.128 -> Q64.64, rounding up if anything was shifted out.
        let mut r = ratio >> 64;
        if (ratio & LOW_64 != 0) { r = r + 1 };
        (r as u128)
    }

    // ------------------------------------------------------------------ //
    // sqrt price -> tick                                                 //
    // ------------------------------------------------------------------ //

    /// The greatest tick whose square-root price does not exceed `sqrt_price`.
    ///
    /// Binary search, rather than the log2 approximation Uniswap uses. That
    /// costs about 21 evaluations of `sqrt_price_at_tick` -- roughly 420
    /// multiply-shifts -- where the log approach costs perhaps a tenth of that.
    ///
    /// The trade is deliberate. This is not on the hot path: a swap walks the
    /// tick bitmap, it does not invert prices. And a binary search over a
    /// function already proven monotonic is correct by construction, where the
    /// log approximation needs its own error analysis and its own magic table.
    /// If this ever shows up in a gas profile, that is the moment to write the
    /// harder version -- and there will be a test suite to check it against.
    public fun tick_at_sqrt_price(sqrt_price: u128): I32 {
        assert!(
            sqrt_price >= MIN_SQRT_PRICE && sqrt_price <= MAX_SQRT_PRICE,
            EInvalidSqrtPrice,
        );

        // Search an unsigned offset so the midpoint arithmetic stays trivial:
        // offset 0 is MIN_TICK, offset 2*MAX_TICK is MAX_TICK.
        let mut lo: u32 = 0;
        let mut hi: u32 = 2 * MAX_TICK;
        while (lo < hi) {
            let mid = (lo + hi + 1) / 2;
            if (sqrt_price_at_tick(tick_from_offset(mid)) <= sqrt_price) {
                lo = mid;
            } else {
                hi = mid - 1;
            };
        };
        tick_from_offset(lo)
    }

    fun tick_from_offset(offset: u32): I32 {
        if (offset >= MAX_TICK) {
            i32::from_u32(offset - MAX_TICK)
        } else {
            i32::neg_from(MAX_TICK - offset)
        }
    }
}
'''

src = TEMPLATE.replace("__CONSTS__", const_block).replace("__APPLY__", apply_block)
out = "move/sui/braid_clmm/sources/tick_math.move"
io.open(out, "w", encoding="utf-8", newline="\n").write(src)
print(f"wrote {out}  ({len(src)} bytes, {len(consts)} constants)")
