/// Working out what fees a position has earned.
///
/// # The problem
///
/// A constant-product pool can pay fees by simply leaving them in the reserve:
/// every LP owns a fraction of the whole pool, so growing the pool pays
/// everyone proportionally. That does not work here. A position only earns
/// while the price is inside its range, and there may be thousands of positions
/// with different ranges. Crediting each one on every swap would cost
/// unbounded gas.
///
/// # The trick
///
/// Track one global counter of fees *per unit of liquidity*, and have each tick
/// remember how much of that counter accumulated on the far side of it. Fees
/// earned inside a range are then the global total minus what accumulated below
/// the lower tick and above the upper one -- three reads and two subtractions,
/// no matter how many positions exist.
///
/// A position stores the value of that figure when it was last touched. The
/// difference since then, times its liquidity, is what it is owed.
///
/// # Why the subtraction is allowed to wrap
///
/// "Below the lower tick" is itself computed by subtraction, and those
/// intermediates routinely go negative -- a tick initialized after fees had
/// already accrued starts with an outside value larger than the region it
/// describes. Uniswap leans on Solidity's unchecked wrapping for this. Move
/// aborts on underflow, so the wrap has to be written out.
///
/// It is sound because **only differences are ever used**. Every quantity here
/// is a counter read modulo 2^256, and the difference of two wrapped counters
/// is correct as long as the true difference fits -- which it does, because
/// fees earned between two updates are bounded by the pool's own balances.
///
/// # Scale
///
/// Fee growth is held as Q128.128, not the Q64.64 used for prices elsewhere. It
/// is a rate -- fees divided by liquidity -- and with liquidity up to `2^128` a
/// 64-bit fraction would round most swaps to zero growth. The extra bits cost
/// nothing here because the counter is a `u256` either way.
module braid_clmm::fee_math {

    /// A result did not fit its target width.
    const EOverflow: u64 = 0;

    const U256_MAX: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    const MAX_U64: u256 = 18446744073709551615;
    /// `2^128`, the scale factor for fee growth.
    const Q128: u256 = 340282366920938463463374607431768211456;

    // ------------------------------------------------------------------ //
    // Modular arithmetic                                                 //
    // ------------------------------------------------------------------ //

    /// `a + b` modulo `2^256`.
    public fun wrapping_add(a: u256, b: u256): u256 {
        if (a > U256_MAX - b) {
            // Wrapped: the part that fits, then the remainder from zero.
            a - (U256_MAX - b) - 1
        } else {
            a + b
        }
    }

    /// `a - b` modulo `2^256`.
    ///
    /// Deliberately silent about going negative. Callers only ever use the
    /// result as one half of a difference, so a wrapped value is the correct
    /// intermediate rather than an error.
    public fun wrapping_sub(a: u256, b: u256): u256 {
        if (a >= b) {
            a - b
        } else {
            (U256_MAX - b) + a + 1
        }
    }

    // ------------------------------------------------------------------ //
    // The global counter                                                 //
    // ------------------------------------------------------------------ //

    /// How much a fee of `fee_amount` adds to the global counter.
    ///
    /// `fee * 2^128 / liquidity` -- fees per unit of liquidity, so a position's
    /// share is just its liquidity times the growth over its lifetime.
    /// Rounded down: the remainder stays in the pool rather than being credited
    /// to anyone.
    public fun growth_from_fee(fee_amount: u64, liquidity: u128): u256 {
        if (liquidity == 0 || fee_amount == 0) return 0;
        (fee_amount as u256) * Q128 / (liquidity as u256)
    }

    /// Fold a swap's fee into the running total.
    public fun accrue(fee_growth_global: u256, fee_amount: u64, liquidity: u128): u256 {
        wrapping_add(fee_growth_global, growth_from_fee(fee_amount, liquidity))
    }

    // ------------------------------------------------------------------ //
    // Per-tick accounting                                                //
    // ------------------------------------------------------------------ //

    /// The value a tick's `fee_growth_outside` starts at.
    ///
    /// The convention is that "outside" means the side away from the current
    /// price. A tick at or below the current price has the whole history so far
    /// on its far side, so it starts at the global total; one above starts at
    /// zero. The choice is arbitrary in itself -- what matters is that the same
    /// convention is applied when the tick is crossed, so the differences stay
    /// consistent.
    public fun initial_outside(
        tick_initialized_at_or_below_current: bool,
        fee_growth_global: u256,
    ): u256 {
        if (tick_initialized_at_or_below_current) { fee_growth_global } else { 0 }
    }

    /// Update a tick's `fee_growth_outside` as the price crosses it.
    ///
    /// Crossing swaps which side is "outside", so the recorded value becomes
    /// everything that is not it.
    public fun cross(fee_growth_outside: u256, fee_growth_global: u256): u256 {
        wrapping_sub(fee_growth_global, fee_growth_outside)
    }

    // ------------------------------------------------------------------ //
    // Per-position accounting                                            //
    // ------------------------------------------------------------------ //

    /// Fee growth accumulated inside `[tick_lower, tick_upper]`.
    ///
    /// `current_at_or_above_lower` and `current_below_upper` describe where the
    /// price sits; passing them in rather than the ticks keeps this free of the
    /// tick type and trivially testable.
    ///
    /// Both subtractions can wrap, and both are supposed to.
    public fun fee_growth_inside(
        fee_growth_global: u256,
        lower_outside: u256,
        upper_outside: u256,
        current_at_or_above_lower: bool,
        current_below_upper: bool,
    ): u256 {
        let below = if (current_at_or_above_lower) {
            lower_outside
        } else {
            wrapping_sub(fee_growth_global, lower_outside)
        };

        let above = if (current_below_upper) {
            upper_outside
        } else {
            wrapping_sub(fee_growth_global, upper_outside)
        };

        wrapping_sub(wrapping_sub(fee_growth_global, below), above)
    }

    /// What a position is owed since it was last settled.
    ///
    /// The multiply aborts rather than truncating if it leaves `u256`. A
    /// product that large means the position's recorded checkpoint no longer
    /// relates to the current counter, and a wrong fee is worse than a failed
    /// call.
    public fun fees_owed(
        liquidity: u128,
        fee_growth_inside_now: u256,
        fee_growth_inside_last: u256,
    ): u64 {
        if (liquidity == 0) return 0;
        let delta = wrapping_sub(fee_growth_inside_now, fee_growth_inside_last);
        if (delta == 0) return 0;

        let owed = delta * (liquidity as u256) / Q128;
        assert!(owed <= MAX_U64, EOverflow);
        (owed as u64)
    }

    public fun q128(): u256 { Q128 }
}
