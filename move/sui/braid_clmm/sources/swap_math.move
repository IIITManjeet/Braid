/// Moving the price, and taking one step of a swap.
///
/// A constant-product swap is one formula because liquidity is the same at
/// every price. Here it differs by range, so a large trade walks through
/// several and the arithmetic restarts at each boundary. `compute_swap_step` is
/// one leg of that walk; the caller loops, crossing ticks and updating
/// liquidity between calls.
///
/// ```text
///   token0 in :  sp' = L*sp*2^64 / (L*2^64 + dx*sp)     price falls
///   token1 in :  sp' = sp + dy*2^64 / L                 price rises
/// ```
///
/// The token0 form is computed as `(L<<64) / ((L<<64)/sp + dx)` -- the inner
/// division first. Algebraically identical, but the direct form needs ~306 bits
/// and Move has no u512. Doing the division first costs under a unit of
/// precision, in the pool's favour: the truncation shrinks the denominator,
/// which raises sp', so the price moves less and less token1 leaves.
module braid_clmm::swap_math {
    use braid_clmm::liquidity_math;

    /// Liquidity was zero where a price move needs it.
    const EZeroLiquidity: u64 = 0;
    /// A result did not fit its target width.
    const EOverflow: u64 = 1;
    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 2;
    /// The move would take the price to or below zero.
    const EPriceUnderflow: u64 = 3;

    const MAX_U128: u256 = 340282366920938463463374607431768211455;
    const BPS_DENOM: u64 = 10000;
    /// 10%, matching the constant-product pool's ceiling.
    const MAX_FEE_BPS: u64 = 1000;

    public fun max_fee_bps(): u64 { MAX_FEE_BPS }

    fun ceil_div_u256(n: u256, d: u256): u256 {
        let q = n / d;
        if (n % d == 0) { q } else { q + 1 }
    }

    fun to_u128(v: u256): u128 {
        assert!(v <= MAX_U128, EOverflow);
        (v as u128)
    }

    // ------------------------------------------------------------------ //
    // Price movement                                                     //
    // ------------------------------------------------------------------ //

    /// The price after `amount` of token0 is added. Falls.
    ///
    /// Rounded **up**, so the price moves less than the exact result and the
    /// pool pays out less token1.
    public fun next_sqrt_price_from_amount0_in(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
    ): u128 {
        assert!(liquidity > 0, EZeroLiquidity);
        assert!(sqrt_price > 0, EPriceUnderflow);
        if (amount == 0) return sqrt_price;

        let num = (liquidity as u256) << 64;
        let denom = num / (sqrt_price as u256) + (amount as u256);
        to_u128(ceil_div_u256(num, denom))
    }

    /// The price after `amount` of token1 is added. Rises.
    ///
    /// Rounded **down**, so the price moves less and the pool pays out less
    /// token0.
    public fun next_sqrt_price_from_amount1_in(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
    ): u128 {
        assert!(liquidity > 0, EZeroLiquidity);
        if (amount == 0) return sqrt_price;

        let step = ((amount as u256) << 64) / (liquidity as u256);
        to_u128((sqrt_price as u256) + step)
    }

    /// The price after `amount` of token1 is removed. Falls.
    ///
    /// The step is rounded **up**, so the price falls further and the trade
    /// costs more token0 -- the exact-output direction of the same convention.
    public fun next_sqrt_price_from_amount1_out(
        sqrt_price: u128,
        liquidity: u128,
        amount: u64,
    ): u128 {
        assert!(liquidity > 0, EZeroLiquidity);
        if (amount == 0) return sqrt_price;

        let step = ceil_div_u256((amount as u256) << 64, (liquidity as u256));
        assert!((sqrt_price as u256) > step, EPriceUnderflow);
        to_u128((sqrt_price as u256) - step)
    }

    /// Dispatch on direction. `zero_for_one` means token0 in, price falling.
    public fun next_sqrt_price_from_input(
        sqrt_price: u128,
        liquidity: u128,
        amount_in: u64,
        zero_for_one: bool,
    ): u128 {
        if (zero_for_one) {
            next_sqrt_price_from_amount0_in(sqrt_price, liquidity, amount_in)
        } else {
            next_sqrt_price_from_amount1_in(sqrt_price, liquidity, amount_in)
        }
    }

    // ------------------------------------------------------------------ //
    // One step of a swap                                                 //
    // ------------------------------------------------------------------ //

    /// Advance the price toward `sqrt_target`, spending at most
    /// `amount_remaining` of input.
    ///
    /// Returns `(sqrt_next, amount_in, amount_out, fee_amount)`, where
    /// `amount_in` excludes the fee and `amount_in + fee_amount` never exceeds
    /// `amount_remaining`.
    ///
    /// Two outcomes:
    ///
    ///   - **The step reaches the boundary.** The input was more than enough.
    ///     `sqrt_next == sqrt_target`, and the caller crosses the tick, updates
    ///     liquidity, and calls again with what is left.
    ///   - **The step runs out first.** The price stops partway and the swap is
    ///     over. The fee is then whatever of the budget was not spent as input,
    ///     rather than a percentage -- which is what keeps the two summing to
    ///     exactly the amount the trader handed over.
    ///
    /// Exact-in only. Exact-out reuses the price-movement functions above but
    /// bounds on the output instead, and is not needed until the router quotes
    /// in that direction.
    public fun compute_swap_step(
        sqrt_current: u128,
        sqrt_target: u128,
        liquidity: u128,
        amount_remaining: u64,
        fee_bps: u64,
    ): (u128, u64, u64, u64) {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(liquidity > 0, EZeroLiquidity);

        let zero_for_one = sqrt_current >= sqrt_target;

        // The fee is taken off the top; only the remainder reaches the curve.
        let fee_on_budget = ceil_div_u256(
            (amount_remaining as u256) * (fee_bps as u256),
            (BPS_DENOM as u256),
        );
        let remaining_less_fee = ((amount_remaining as u256) - fee_on_budget as u64);

        // What it would cost to walk the whole way to the boundary.
        let to_target = if (zero_for_one) {
            liquidity_math::amount0_delta(sqrt_target, sqrt_current, liquidity, true)
        } else {
            liquidity_math::amount1_delta(sqrt_current, sqrt_target, liquidity, true)
        };

        let sqrt_next = if (remaining_less_fee >= to_target) {
            sqrt_target
        } else {
            next_sqrt_price_from_input(
                sqrt_current,
                liquidity,
                remaining_less_fee,
                zero_for_one,
            )
        };

        let reached_target = sqrt_next == sqrt_target;

        // Input rounds up, output rounds down. Both favour the pool.
        let (amount_in, amount_out) = if (zero_for_one) {
            (
                if (reached_target) { to_target } else {
                    liquidity_math::amount0_delta(sqrt_next, sqrt_current, liquidity, true)
                },
                liquidity_math::amount1_delta(sqrt_next, sqrt_current, liquidity, false),
            )
        } else {
            (
                if (reached_target) { to_target } else {
                    liquidity_math::amount1_delta(sqrt_current, sqrt_next, liquidity, true)
                },
                liquidity_math::amount0_delta(sqrt_current, sqrt_next, liquidity, false),
            )
        };

        let fee_amount = if (reached_target) {
            // A normal proportional fee on what was actually swapped.
            (ceil_div_u256(
                (amount_in as u256) * (fee_bps as u256),
                ((BPS_DENOM - fee_bps) as u256),
            ) as u64)
        } else {
            // The swap ended here, so the fee is the rest of the budget. This
            // is what makes `amount_in + fee_amount == amount_remaining`
            // exactly, with no dust stranded in the caller's accounting.
            amount_remaining - amount_in
        };

        (sqrt_next, amount_in, amount_out, fee_amount)
    }
}
