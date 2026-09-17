/// What each initialized tick remembers.
///
/// A tick is a boundary. Positions start and end at them, and the pool's active
/// liquidity changes as the price crosses one. Each initialized tick stores two
/// liquidity figures that are easy to confuse:
///
///   - **gross** -- how much liquidity references this tick at all, from either
///     side. It only decides whether the tick exists: when it reaches zero the
///     tick is uninitialized and its bit is cleared from the bitmap.
///   - **net** -- the signed change to *active* liquidity when the price
///     crosses this tick upward. A position's lower tick contributes `+L` and
///     its upper contributes `-L`, so a tick serving as the top of one position
///     and the bottom of another can net to anything, including zero.
///
/// Gross is what keeps the tick alive; net is what the swap loop applies. A
/// tick with net zero and gross non-zero is a real tick that happens to have
/// balanced positions on both sides -- deleting it would corrupt the fee
/// accounting, which is why the two are tracked separately.
///
/// Plus the two `fee_growth_outside` counters, which `fee_math` explains.
module braid_clmm::tick {
    use braid_clmm::fee_math;
    use braid_clmm::i128::{Self, I128};
    use braid_clmm::tick_math;

    /// Liquidity on a single tick would exceed the per-tick cap.
    const ELiquidityOverflow: u64 = 0;
    /// Removing more liquidity than the tick carries.
    const ELiquidityUnderflow: u64 = 1;
    /// Tick spacing must be positive.
    const EInvalidTickSpacing: u64 = 2;

    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    public struct TickInfo has copy, drop, store {
        liquidity_gross: u128,
        liquidity_net: I128,
        fee_growth_outside_0: u256,
        fee_growth_outside_1: u256,
        initialized: bool,
    }

    // ------------------------------------------------------------------ //
    // Construction and access                                            //
    // ------------------------------------------------------------------ //

    public fun empty(): TickInfo {
        TickInfo {
            liquidity_gross: 0,
            liquidity_net: i128::zero(),
            fee_growth_outside_0: 0,
            fee_growth_outside_1: 0,
            initialized: false,
        }
    }

    public fun liquidity_gross(t: &TickInfo): u128 { t.liquidity_gross }

    public fun liquidity_net(t: &TickInfo): I128 { t.liquidity_net }

    public fun fee_growth_outside_0(t: &TickInfo): u256 { t.fee_growth_outside_0 }

    public fun fee_growth_outside_1(t: &TickInfo): u256 { t.fee_growth_outside_1 }

    public fun is_initialized(t: &TickInfo): bool { t.initialized }

    // ------------------------------------------------------------------ //
    // The per-tick liquidity cap                                         //
    // ------------------------------------------------------------------ //

    /// The most liquidity any one tick may carry.
    ///
    /// `u128::MAX` spread evenly over every usable tick. The cap exists so that
    /// the pool's *active* liquidity -- the sum over all ticks the price sits
    /// between -- cannot overflow however positions are arranged. Without it a
    /// few maximal positions could make the running total unrepresentable, and
    /// a swap would abort with the pool stuck.
    public fun max_liquidity_per_tick(tick_spacing: u32): u128 {
        assert!(tick_spacing > 0, EInvalidTickSpacing);
        let usable = 2 * ((tick_math::max_tick_u32() / tick_spacing) as u128) + 1;
        MAX_U128 / usable
    }

    // ------------------------------------------------------------------ //
    // Opening and closing positions                                      //
    // ------------------------------------------------------------------ //

    /// Apply a position's liquidity change to one of its boundary ticks.
    ///
    /// Returns whether the tick *flipped* -- came into existence or went out of
    /// it -- which is exactly when the caller must toggle its bit in the bitmap.
    ///
    /// `is_upper` says which end of the position this tick is. It only affects
    /// the sign of the net: crossing upward past a position's lower tick brings
    /// that liquidity into range, and crossing past its upper takes it out.
    public fun update(
        t: &mut TickInfo,
        tick_at_or_below_current: bool,
        liquidity_delta: u128,
        is_add: bool,
        is_upper: bool,
        fee_growth_global_0: u256,
        fee_growth_global_1: u256,
        max_liquidity: u128,
    ): bool {
        let gross_before = t.liquidity_gross;

        let gross_after = if (is_add) {
            let sum = (gross_before as u256) + (liquidity_delta as u256);
            assert!(sum <= (max_liquidity as u256), ELiquidityOverflow);
            (sum as u128)
        } else {
            assert!(gross_before >= liquidity_delta, ELiquidityUnderflow);
            gross_before - liquidity_delta
        };

        let flipped = (gross_after == 0) != (gross_before == 0);

        // A tick coming into existence adopts the convention fee_math sets:
        // everything accrued so far counts as "outside" it if it sits at or
        // below the current price. Ticks above start at zero.
        if (gross_before == 0) {
            t.fee_growth_outside_0 =
                fee_math::initial_outside(tick_at_or_below_current, fee_growth_global_0);
            t.fee_growth_outside_1 =
                fee_math::initial_outside(tick_at_or_below_current, fee_growth_global_1);
            t.initialized = true;
        };

        t.liquidity_gross = gross_after;
        if (gross_after == 0) {
            t.initialized = false;
        };

        // Lower ticks add on the way up, upper ticks subtract.
        let signed = i128::from_delta(liquidity_delta, is_add != is_upper);
        t.liquidity_net = i128::add(t.liquidity_net, signed);

        flipped
    }

    // ------------------------------------------------------------------ //
    // Crossing                                                           //
    // ------------------------------------------------------------------ //

    /// Move the price across this tick, returning the change to apply to the
    /// pool's active liquidity.
    ///
    /// The returned net is oriented for an *upward* crossing. Going down, the
    /// caller negates it -- the same boundary, walked the other way.
    public fun cross(
        t: &mut TickInfo,
        fee_growth_global_0: u256,
        fee_growth_global_1: u256,
    ): I128 {
        t.fee_growth_outside_0 = fee_math::cross(t.fee_growth_outside_0, fee_growth_global_0);
        t.fee_growth_outside_1 = fee_math::cross(t.fee_growth_outside_1, fee_growth_global_1);
        t.liquidity_net
    }

    #[test_only]
    public fun new_for_testing(
        liquidity_gross: u128,
        liquidity_net: I128,
        fee_growth_outside_0: u256,
        fee_growth_outside_1: u256,
        initialized: bool,
    ): TickInfo {
        TickInfo {
            liquidity_gross,
            liquidity_net,
            fee_growth_outside_0,
            fee_growth_outside_1,
            initialized,
        }
    }
}
