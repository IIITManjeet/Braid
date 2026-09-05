#[test_only]
module braid_clmm::tick_tests {
    use braid_clmm::fee_math;
    use braid_clmm::i128;
    use braid_clmm::tick;

    const L: u128 = 1000000000000;
    const NO_CAP: u128 = 340282366920938463463374607431768211455;

    // ---------------------------------------------------------------- //
    // i128                                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun signed_liquidity_deltas_behave() {
        assert!(i128::is_zero(i128::zero()), 0);
        assert!(!i128::is_neg(i128::from_u128(5)), 1);
        assert!(i128::is_neg(i128::neg_from(5)), 2);
        assert!(i128::abs_u128(i128::neg_from(5)) == 5, 3);

        // Adding opposites cancels.
        assert!(i128::is_zero(i128::add(i128::from_u128(L), i128::neg_from(L))), 4);

        // Crossing zero from the negative side.
        let r = i128::add(i128::neg_from(5), i128::from_u128(8));
        assert!(!i128::is_neg(r) && i128::abs_u128(r) == 3, 5);

        // from_delta / to_delta round-trip.
        let (m, pos) = i128::to_delta(i128::from_delta(L, false));
        assert!(m == L && !pos, 6);
    }

    // ---------------------------------------------------------------- //
    // The liquidity cap                                                //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_cap_scales_with_tick_spacing() {
        // Wider spacing means fewer usable ticks, so each may carry more.
        let tight = tick::max_liquidity_per_tick(1);
        let wide = tick::max_liquidity_per_tick(60);
        assert!(wide > tight, 0);
        // And even the tight cap is enormous -- this bounds pathological
        // arrangements, it does not constrain real positions.
        assert!(tight > 1000000000000000000000000, 1);
    }

    // ---------------------------------------------------------------- //
    // Opening and closing                                              //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_first_position_flips_the_tick_on() {
        let mut t = tick::empty();
        assert!(!tick::is_initialized(&t), 0);

        let flipped = tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);
        assert!(flipped, 1);
        assert!(tick::is_initialized(&t), 2);
        assert!(tick::liquidity_gross(&t) == L, 3);
    }

    #[test]
    fun a_second_position_does_not_flip_it_again() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);

        let flipped = tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);
        assert!(!flipped, 0);
        assert!(tick::liquidity_gross(&t) == L * 2, 1);
    }

    #[test]
    fun removing_the_last_position_flips_it_off() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);

        let flipped = tick::update(&mut t, true, L, false, false, 0, 0, NO_CAP);
        assert!(flipped, 0);
        assert!(!tick::is_initialized(&t), 1);
        assert!(tick::liquidity_gross(&t) == 0, 2);
    }

    #[test]
    fun lower_and_upper_ticks_take_opposite_signs() {
        // A lower tick brings liquidity into range on the way up.
        let mut lower = tick::empty();
        tick::update(&mut lower, true, L, true, false, 0, 0, NO_CAP);
        assert!(!i128::is_neg(tick::liquidity_net(&lower)), 0);
        assert!(i128::abs_u128(tick::liquidity_net(&lower)) == L, 1);

        // An upper tick takes it back out.
        let mut upper = tick::empty();
        tick::update(&mut upper, true, L, true, true, 0, 0, NO_CAP);
        assert!(i128::is_neg(tick::liquidity_net(&upper)), 2);
        assert!(i128::abs_u128(tick::liquidity_net(&upper)) == L, 3);
    }

    #[test]
    fun a_tick_serving_two_positions_can_net_to_zero_while_staying_alive() {
        // This is why gross and net are tracked separately. One position ends
        // here and another begins, so the net change on crossing is nothing --
        // but the tick is still real and still holds fee data.
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, true, 0, 0, NO_CAP);   // upper of one
        tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);  // lower of another

        assert!(i128::is_zero(tick::liquidity_net(&t)), 0);
        assert!(tick::liquidity_gross(&t) == L * 2, 1);
        // Net zero must not be mistaken for "delete me".
        assert!(tick::is_initialized(&t), 2);
    }

    #[test]
    fun a_new_tick_below_the_price_inherits_the_fee_history() {
        let global0: u256 = 5_000_000;
        let global1: u256 = 7_000_000;

        // At or below the current price: everything so far is "outside".
        let mut below = tick::empty();
        tick::update(&mut below, true, L, true, false, global0, global1, NO_CAP);
        assert!(tick::fee_growth_outside_0(&below) == global0, 0);
        assert!(tick::fee_growth_outside_1(&below) == global1, 1);

        // Above it: nothing has accrued on the far side yet.
        let mut above = tick::empty();
        tick::update(&mut above, false, L, true, false, global0, global1, NO_CAP);
        assert!(tick::fee_growth_outside_0(&above) == 0, 2);
        assert!(tick::fee_growth_outside_1(&above) == 0, 3);
    }

    #[test]
    fun the_fee_snapshot_is_only_taken_once() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 1000, 2000, NO_CAP);
        // A later position on the same tick must not re-snapshot, or the fees
        // already earned by the first would be silently rewritten.
        tick::update(&mut t, true, L, true, false, 9_999_999, 8_888_888, NO_CAP);
        assert!(tick::fee_growth_outside_0(&t) == 1000, 0);
        assert!(tick::fee_growth_outside_1(&t) == 2000, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick::ELiquidityOverflow)]
    fun exceeding_the_per_tick_cap_is_rejected() {
        let mut t = tick::empty();
        tick::update(&mut t, true, 1001, true, false, 0, 0, 1000);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick::ELiquidityUnderflow)]
    fun removing_more_than_the_tick_holds_is_rejected() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);
        tick::update(&mut t, true, L + 1, false, false, 0, 0, NO_CAP);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick::EInvalidTickSpacing)]
    fun a_zero_spacing_has_no_cap() {
        tick::max_liquidity_per_tick(0);
    }

    // ---------------------------------------------------------------- //
    // Crossing                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun crossing_returns_the_net_and_flips_the_fee_side() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 0, 0, NO_CAP);

        let global0: u256 = 3_000_000;
        let global1: u256 = 4_000_000;
        let net = tick::cross(&mut t, global0, global1);

        assert!(!i128::is_neg(net) && i128::abs_u128(net) == L, 0);
        // Outside was 0, so after crossing it holds the whole global.
        assert!(tick::fee_growth_outside_0(&t) == global0, 1);
        assert!(tick::fee_growth_outside_1(&t) == global1, 2);
    }

    #[test]
    fun crossing_back_restores_the_tick() {
        let mut t = tick::empty();
        tick::update(&mut t, true, L, true, false, 1000, 2000, NO_CAP);
        let before0 = tick::fee_growth_outside_0(&t);
        let before1 = tick::fee_growth_outside_1(&t);

        // Cross and cross back with the globals unchanged.
        tick::cross(&mut t, 5000, 6000);
        tick::cross(&mut t, 5000, 6000);

        assert!(tick::fee_growth_outside_0(&t) == before0, 0);
        assert!(tick::fee_growth_outside_1(&t) == before1, 1);
    }

    #[test]
    fun crossing_a_tick_that_was_initialized_late_wraps_cleanly() {
        // Outside larger than the global, which happens whenever a tick is
        // created after fees have accrued and the price then moves past it.
        let mut t = tick::new_for_testing(L, i128::from_u128(L), 900, 900, true);
        tick::cross(&mut t, 100, 100);
        assert!(tick::fee_growth_outside_0(&t) == fee_math::wrapping_sub(100, 900), 0);
        // Still reversible.
        tick::cross(&mut t, 100, 100);
        assert!(tick::fee_growth_outside_0(&t) == 900, 1);
    }
}
