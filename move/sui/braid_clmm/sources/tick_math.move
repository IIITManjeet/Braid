/// Ticks and square-root prices.
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

    /// `1.0001^(-2^0/2)`
    const C0: u256 = 0xfffcb933bd6fad37aa2d162d1a594001;
    /// `1.0001^(-2^1/2)`
    const C1: u256 = 0xfff97272373d413259a46990580e2139;
    /// `1.0001^(-2^2/2)`
    const C2: u256 = 0xfff2e50f5f656932ef12357cf3c7fdcb;
    /// `1.0001^(-2^3/2)`
    const C3: u256 = 0xffe5caca7e10e4e61c3624eaa0941ccf;
    /// `1.0001^(-2^4/2)`
    const C4: u256 = 0xffcb9843d60f6159c9db58835c926643;
    /// `1.0001^(-2^5/2)`
    const C5: u256 = 0xff973b41fa98c081472e6896dfb254bf;
    /// `1.0001^(-2^6/2)`
    const C6: u256 = 0xff2ea16466c96a3843ec78b326b52860;
    /// `1.0001^(-2^7/2)`
    const C7: u256 = 0xfe5dee046a99a2a811c461f1969c3052;
    /// `1.0001^(-2^8/2)`
    const C8: u256 = 0xfcbe86c7900a88aedcffc83b479aa3a3;
    /// `1.0001^(-2^9/2)`
    const C9: u256 = 0xf987a7253ac413176f2b074cf7815e53;
    /// `1.0001^(-2^10/2)`
    const C10: u256 = 0xf3392b0822b70005940c7a398e4b70f2;
    /// `1.0001^(-2^11/2)`
    const C11: u256 = 0xe7159475a2c29b7443b29c7fa6e889d8;
    /// `1.0001^(-2^12/2)`
    const C12: u256 = 0xd097f3bdfd2022b8845ad8f792aa5825;
    /// `1.0001^(-2^13/2)`
    const C13: u256 = 0xa9f746462d870fdf8a65dc1f90e061e4;
    /// `1.0001^(-2^14/2)`
    const C14: u256 = 0x70d869a156d2a1b890bb3df62baf32f6;
    /// `1.0001^(-2^15/2)`
    const C15: u256 = 0x31be135f97d08fd981231505542fcfa5;
    /// `1.0001^(-2^16/2)`
    const C16: u256 = 0x09aa508b5b7a84e1c677de54f3e99bc8;
    /// `1.0001^(-2^17/2)`
    const C17: u256 = 0x005d6af8dedb81196699c329225ee604;
    /// `1.0001^(-2^18/2)`
    const C18: u256 = 0x00002216e584f5fa1ea926041bedfe97;
    /// `1.0001^(-2^19/2)`
    const C19: u256 = 0x00000000048a170391f7dc42444e8fa2;

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
        if (abs_tick & 1 != 0) ratio = (ratio * C0) >> 128;
        if (abs_tick & 2 != 0) ratio = (ratio * C1) >> 128;
        if (abs_tick & 4 != 0) ratio = (ratio * C2) >> 128;
        if (abs_tick & 8 != 0) ratio = (ratio * C3) >> 128;
        if (abs_tick & 16 != 0) ratio = (ratio * C4) >> 128;
        if (abs_tick & 32 != 0) ratio = (ratio * C5) >> 128;
        if (abs_tick & 64 != 0) ratio = (ratio * C6) >> 128;
        if (abs_tick & 128 != 0) ratio = (ratio * C7) >> 128;
        if (abs_tick & 256 != 0) ratio = (ratio * C8) >> 128;
        if (abs_tick & 512 != 0) ratio = (ratio * C9) >> 128;
        if (abs_tick & 1024 != 0) ratio = (ratio * C10) >> 128;
        if (abs_tick & 2048 != 0) ratio = (ratio * C11) >> 128;
        if (abs_tick & 4096 != 0) ratio = (ratio * C12) >> 128;
        if (abs_tick & 8192 != 0) ratio = (ratio * C13) >> 128;
        if (abs_tick & 16384 != 0) ratio = (ratio * C14) >> 128;
        if (abs_tick & 32768 != 0) ratio = (ratio * C15) >> 128;
        if (abs_tick & 65536 != 0) ratio = (ratio * C16) >> 128;
        if (abs_tick & 131072 != 0) ratio = (ratio * C17) >> 128;
        if (abs_tick & 262144 != 0) ratio = (ratio * C18) >> 128;
        if (abs_tick & 524288 != 0) ratio = (ratio * C19) >> 128;

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
