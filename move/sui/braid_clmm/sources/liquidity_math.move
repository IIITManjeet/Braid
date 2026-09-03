/// Converting between a position's liquidity and the token amounts backing it.
///
/// A concentrated position owns a fixed quantity of liquidity `L`, active only
/// while the price sits inside its range -- not a share of the whole pool. For
/// a range `sa < sb`, both Q64.64:
///
/// ```text
///   amount0 = L * (sb - sa) * 2^64 / (sa * sb)
///   amount1 = L * (sb - sa) / 2^64
/// ```
///
/// Both linear in the sqrt-price difference, which is why prices are carried as
/// square roots at all. Below its range a position is entirely token0 (the
/// price must rise through the range before any is sold); above it, entirely
/// token1; inside, the current price splits it.
///
/// `round_up` is a parameter, not a default. Minting rounds required amounts
/// up, burning rounds returned amounts down, and deriving liquidity from
/// amounts rounds down so credited depth is always backed.
module braid_clmm::liquidity_math {

    /// Range endpoints must be positive and distinct.
    const EInvalidPriceRange: u64 = 0;
    /// An intermediate or result did not fit its target width.
    const EOverflow: u64 = 1;

    const MAX_U64: u256 = 18446744073709551615;
    const MAX_U128: u256 = 340282366920938463463374607431768211455;
    /// `2^192 − 1`. `L · (sb − sa)` must stay inside this so the subsequent
    /// `<< 64` cannot silently discard high bits -- Move's shift truncates
    /// rather than aborting, so the guard has to be explicit.
    const MAX_U192: u256 =
        6277101735386680763835789423207666416102355444464034512895;

    // ------------------------------------------------------------------ //
    // Internal helpers                                                   //
    // ------------------------------------------------------------------ //

    fun ordered(sqrt_a: u128, sqrt_b: u128): (u256, u256) {
        assert!(sqrt_a > 0 && sqrt_b > 0, EInvalidPriceRange);
        if (sqrt_a <= sqrt_b) {
            ((sqrt_a as u256), (sqrt_b as u256))
        } else {
            ((sqrt_b as u256), (sqrt_a as u256))
        }
    }

    fun div_round(n: u256, d: u256, round_up: bool): u256 {
        let q = n / d;
        if (round_up && n % d != 0) { q + 1 } else { q }
    }

    fun to_u64(v: u256): u64 {
        assert!(v <= MAX_U64, EOverflow);
        (v as u64)
    }

    // ------------------------------------------------------------------ //
    // Liquidity -> amounts                                               //
    // ------------------------------------------------------------------ //

    /// The token0 a position of `liquidity` holds across `[sqrt_a, sqrt_b]`.
    ///
    /// `L · (sb − sa) · 2^64 / (sa · sb)`, done as a single division so the
    /// rounding happens once. The denominator `sa · sb` needs up to 226 bits
    /// and the numerator up to 256, which is why both are `u256`.
    public fun amount0_delta(
        sqrt_a: u128,
        sqrt_b: u128,
        liquidity: u128,
        round_up: bool,
    ): u64 {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        if (liquidity == 0 || lo == hi) return 0;

        let prod = (liquidity as u256) * (hi - lo);
        assert!(prod <= MAX_U192, EOverflow);

        to_u64(div_round(prod << 64, lo * hi, round_up))
    }

    /// The token1 a position of `liquidity` holds across `[sqrt_a, sqrt_b]`.
    ///
    /// `L · (sb − sa) / 2^64`. Simpler than the token0 leg because no division
    /// by the prices is involved -- token1 is denominated in the same direction
    /// the sqrt-price moves.
    public fun amount1_delta(
        sqrt_a: u128,
        sqrt_b: u128,
        liquidity: u128,
        round_up: bool,
    ): u64 {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        if (liquidity == 0 || lo == hi) return 0;

        let prod = (liquidity as u256) * (hi - lo);
        to_u64(div_round(prod, 1u256 << 64, round_up))
    }

    /// Both legs of a position, given where the price currently sits.
    ///
    /// Returns `(amount0, amount1)`.
    public fun amounts_for_liquidity(
        sqrt_price: u128,
        sqrt_a: u128,
        sqrt_b: u128,
        liquidity: u128,
        round_up: bool,
    ): (u64, u64) {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        let p = (sqrt_price as u256);

        if (p <= lo) {
            // Below the range: still waiting to sell, so all token0.
            (amount0_delta(sqrt_a, sqrt_b, liquidity, round_up), 0)
        } else if (p >= hi) {
            // Above the range: already sold out, so all token1.
            (0, amount1_delta(sqrt_a, sqrt_b, liquidity, round_up))
        } else {
            // Inside: the current price splits the position in two.
            (
                amount0_delta(sqrt_price, (hi as u128), liquidity, round_up),
                amount1_delta((lo as u128), sqrt_price, liquidity, round_up),
            )
        }
    }

    // ------------------------------------------------------------------ //
    // Amounts -> liquidity                                               //
    // ------------------------------------------------------------------ //

    /// The liquidity that `amount0` supports across `[sqrt_a, sqrt_b]`.
    ///
    /// Inverting the token0 formula: `L = amount0 · sa · sb / ((sb − sa) · 2^64)`.
    /// `sa · sb` is folded down by `2^64` first, because the full triple product
    /// would need about 290 bits. Always rounds down.
    public fun liquidity_from_amount0(
        sqrt_a: u128,
        sqrt_b: u128,
        amount0: u64,
    ): u128 {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        assert!(hi > lo, EInvalidPriceRange);

        let intermediate = (lo * hi) >> 64;
        let l = (amount0 as u256) * intermediate / (hi - lo);
        assert!(l <= MAX_U128, EOverflow);
        (l as u128)
    }

    /// The liquidity that `amount1` supports across `[sqrt_a, sqrt_b]`.
    ///
    /// `L = amount1 · 2^64 / (sb − sa)`. Always rounds down.
    public fun liquidity_from_amount1(
        sqrt_a: u128,
        sqrt_b: u128,
        amount1: u64,
    ): u128 {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        assert!(hi > lo, EInvalidPriceRange);

        let l = ((amount1 as u256) << 64) / (hi - lo);
        assert!(l <= MAX_U128, EOverflow);
        (l as u128)
    }

    /// The liquidity a deposit of `(amount0, amount1)` supports.
    ///
    /// Inside the range both legs are required, so the answer is the **smaller**
    /// of what each side supports -- the same "mint against the scarcer side"
    /// rule the constant-product pool uses, for the same reason: crediting the
    /// larger would mint depth the deposit does not back.
    public fun liquidity_for_amounts(
        sqrt_price: u128,
        sqrt_a: u128,
        sqrt_b: u128,
        amount0: u64,
        amount1: u64,
    ): u128 {
        let (lo, hi) = ordered(sqrt_a, sqrt_b);
        let p = (sqrt_price as u256);

        if (p <= lo) {
            liquidity_from_amount0(sqrt_a, sqrt_b, amount0)
        } else if (p >= hi) {
            liquidity_from_amount1(sqrt_a, sqrt_b, amount1)
        } else {
            let from_0 = liquidity_from_amount0(sqrt_price, (hi as u128), amount0);
            let from_1 = liquidity_from_amount1((lo as u128), sqrt_price, amount1);
            if (from_0 < from_1) { from_0 } else { from_1 }
        }
    }

    // ------------------------------------------------------------------ //
    // Liquidity bookkeeping                                              //
    // ------------------------------------------------------------------ //

    /// Apply a signed change to a pool's active liquidity.
    ///
    /// Separate from plain addition because a tick crossing subtracts the
    /// liquidity of every position ending there, and going below zero would
    /// mean the tick accounting has drifted -- an explicit abort beats a
    /// wrapped `u128`.
    public fun add_delta(liquidity: u128, delta: u128, is_add: bool): u128 {
        if (is_add) {
            let r = (liquidity as u256) + (delta as u256);
            assert!(r <= MAX_U128, EOverflow);
            (r as u128)
        } else {
            assert!(liquidity >= delta, EOverflow);
            liquidity - delta
        }
    }
}
