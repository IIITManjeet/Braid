#[test_only]
module braid_clmm::liquidity_math_tests {
    use braid_clmm::i32;
    use braid_clmm::liquidity_math as lm;
    use braid_clmm::tick_math;

    /// A symmetric position around price 1.0, ticks -1000 .. +1000.
    const SA: u128 = 17547129613991598782; // sqrt_price(-1000)
    const SB: u128 = 19392480388906836278; // sqrt_price(+1000)
    const P0: u128 = 18446744073709551616; // sqrt_price(0) = 1.0
    const L: u128 = 1000000000000;         // 1e12

    fun pos(v: u32): u128 { tick_math::sqrt_price_at_tick(i32::from_u32(v)) }
    fun neg(v: u32): u128 { tick_math::sqrt_price_at_tick(i32::neg_from(v)) }

    #[test]
    fun the_fixture_prices_are_what_tick_math_says() {
        assert!(neg(1000) == SA, 0);
        assert!(pos(1000) == SB, 1);
        assert!(tick_math::sqrt_price_at_tick(i32::zero()) == P0, 2);
    }

    // ---------------------------------------------------------------- //
    // Liquidity -> amounts                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_position_below_its_range_is_all_token0() {
        // The price has to rise through the range before any token0 is sold,
        // so the position is entirely waiting-to-sell inventory.
        let (a0, a1) = lm::amounts_for_liquidity(neg(2000), SA, SB, L, false);
        assert!(a0 == 100036665958, 0);
        assert!(a1 == 0, 1);

        // Exactly at the lower bound is still "below" — the range is
        // half-open, so no token1 has accumulated yet.
        let (b0, b1) = lm::amounts_for_liquidity(SA, SA, SB, L, false);
        assert!(b0 == 100036665958 && b1 == 0, 2);
    }

    #[test]
    fun a_position_above_its_range_is_all_token1() {
        let (a0, a1) = lm::amounts_for_liquidity(pos(2000), SA, SB, L, false);
        assert!(a0 == 0, 0);
        assert!(a1 == 100036665958, 1);

        let (b0, b1) = lm::amounts_for_liquidity(SB, SA, SB, L, false);
        assert!(b0 == 0 && b1 == 100036665958, 2);
    }

    #[test]
    fun a_symmetric_position_at_price_one_holds_both_sides_equally() {
        let (a0, a1) = lm::amounts_for_liquidity(P0, SA, SB, L, false);
        assert!(a0 == 48768197581, 0);
        assert!(a1 == 48768197581, 1);
        // Symmetry: the range is symmetric in ticks and the price is at its
        // centre, so both legs match exactly.
        assert!(a0 == a1, 2);
    }

    #[test]
    fun rounding_up_never_returns_less_than_rounding_down() {
        let (d0, d1) = lm::amounts_for_liquidity(P0, SA, SB, L, false);
        let (u0, u1) = lm::amounts_for_liquidity(P0, SA, SB, L, true);
        assert!(u0 == d0 + 1 && u1 == d1 + 1, 0);
        assert!(u0 == 48768197582 && u1 == 48768197582, 1);
    }

    #[test]
    fun the_single_sided_legs_match_the_reference() {
        assert!(lm::amount0_delta(SA, SB, L, false) == 100036665958, 0);
        assert!(lm::amount0_delta(SA, SB, L, true) == 100036665959, 1);
        assert!(lm::amount1_delta(SA, SB, L, false) == 100036665958, 2);
        assert!(lm::amount1_delta(SA, SB, L, true) == 100036665959, 3);
    }

    #[test]
    fun argument_order_does_not_matter() {
        // The endpoints are sorted internally, so a caller cannot get this
        // wrong by passing the range backwards.
        assert!(
            lm::amount0_delta(SA, SB, L, false) == lm::amount0_delta(SB, SA, L, false),
            0,
        );
        assert!(
            lm::amount1_delta(SA, SB, L, false) == lm::amount1_delta(SB, SA, L, false),
            1,
        );
    }

    #[test]
    fun degenerate_inputs_yield_nothing() {
        assert!(lm::amount0_delta(SA, SB, 0, true) == 0, 0);
        assert!(lm::amount1_delta(SA, SB, 0, true) == 0, 1);
        // A zero-width range holds nothing regardless of liquidity.
        assert!(lm::amount0_delta(SA, SA, L, true) == 0, 2);
        assert!(lm::amount1_delta(SA, SA, L, true) == 0, 3);
    }

    #[test]
    fun a_narrower_range_concentrates_more_depth_per_token() {
        // The entire point of the venue: the same tokens spread over a tighter
        // range buy strictly more liquidity.
        let wide = lm::liquidity_for_amounts(P0, neg(10000), pos(10000), 1000000, 1000000);
        let narrow = lm::liquidity_for_amounts(P0, neg(100), pos(100), 1000000, 1000000);
        assert!(narrow > wide, 0);
        // Two orders of magnitude tighter is worth roughly two orders of
        // magnitude more depth.
        assert!(narrow > wide * 50, 1);
    }

    // ---------------------------------------------------------------- //
    // Amounts -> liquidity                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun liquidity_from_each_leg_matches_the_reference() {
        assert!(lm::liquidity_from_amount0(P0, SB, 48768197582) == 1000000000014, 0);
        assert!(lm::liquidity_from_amount1(SA, P0, 48768197582) == 1000000000014, 1);
    }

    #[test]
    fun liquidity_is_taken_from_the_scarcer_side() {
        // Plenty of token1, barely any token0: the token0 leg binds.
        let scarce_0 = lm::liquidity_for_amounts(P0, SA, SB, 1000, 1000000000);
        let from_0_alone = lm::liquidity_from_amount0(P0, SB, 1000);
        assert!(scarce_0 == from_0_alone, 0);

        // And the mirror image.
        let scarce_1 = lm::liquidity_for_amounts(P0, SA, SB, 1000000000, 1000);
        let from_1_alone = lm::liquidity_from_amount1(SA, P0, 1000);
        assert!(scarce_1 == from_1_alone, 1);
    }

    #[test]
    fun outside_the_range_only_one_amount_is_consulted() {
        // Below the range, token1 is irrelevant — passing none changes nothing.
        let a = lm::liquidity_for_amounts(neg(2000), SA, SB, 1000000, 0);
        let b = lm::liquidity_for_amounts(neg(2000), SA, SB, 1000000, 999999999);
        assert!(a == b, 0);

        // Above the range, token0 is irrelevant.
        let c = lm::liquidity_for_amounts(pos(2000), SA, SB, 0, 1000000);
        let d = lm::liquidity_for_amounts(pos(2000), SA, SB, 999999999, 1000000);
        assert!(c == d, 1);
    }

    // ---------------------------------------------------------------- //
    // The safety property                                              //
    // ---------------------------------------------------------------- //

    #[test]
    fun credited_liquidity_is_always_backed_by_what_was_paid() {
        // The invariant that matters for minting. Price a position at ceil,
        // credit the liquidity those amounts support, then re-price that
        // liquidity at ceil. It must never demand more than was handed over.
        //
        // Note this is *not* the same as "recovered liquidity <= deposited" --
        // that is false, and harmlessly so, because rounding the amounts up
        // genuinely buys a little more depth.
        let ranges = vector[100u32, 1000, 10000, 100000];
        let mut i = 0;
        while (i < 4) {
            let w = ranges[i];
            let lo = neg(w);
            let hi = pos(w);
            let prices = vector[neg(w + 500), P0, pos(w + 500)];
            let mut j = 0;
            while (j < 3) {
                let p = prices[j];
                let (paid0, paid1) = lm::amounts_for_liquidity(p, lo, hi, L, true);
                let credited = lm::liquidity_for_amounts(p, lo, hi, paid0, paid1);
                let (need0, need1) = lm::amounts_for_liquidity(p, lo, hi, credited, true);
                assert!(need0 <= paid0, i * 10 + j);
                assert!(need1 <= paid1, 100 + i * 10 + j);
                j = j + 1;
            };
            i = i + 1;
        };
    }

    #[test]
    fun burning_never_pays_out_more_than_minting_took() {
        // Mint at ceil, burn at floor. The pool keeps the difference, which is
        // the only direction that is safe.
        let (in0, in1) = lm::amounts_for_liquidity(P0, SA, SB, L, true);
        let (out0, out1) = lm::amounts_for_liquidity(P0, SA, SB, L, false);
        assert!(out0 <= in0, 0);
        assert!(out1 <= in1, 1);
    }

    // ---------------------------------------------------------------- //
    // Liquidity bookkeeping                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun add_delta_moves_in_both_directions() {
        assert!(lm::add_delta(100, 50, true) == 150, 0);
        assert!(lm::add_delta(100, 50, false) == 50, 1);
        assert!(lm::add_delta(100, 100, false) == 0, 2);
        assert!(lm::add_delta(0, 0, true) == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::liquidity_math::EOverflow)]
    fun removing_more_liquidity_than_exists_aborts() {
        // Would mean the tick accounting has drifted. Better to stop than to
        // wrap around to an enormous liquidity value.
        lm::add_delta(100, 101, false);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::liquidity_math::EInvalidPriceRange)]
    fun a_zero_price_is_rejected() {
        lm::amount0_delta(0, SB, L, false);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::liquidity_math::EInvalidPriceRange)]
    fun deriving_liquidity_from_a_zero_width_range_is_rejected() {
        lm::liquidity_from_amount1(SA, SA, 1000);
    }
}
