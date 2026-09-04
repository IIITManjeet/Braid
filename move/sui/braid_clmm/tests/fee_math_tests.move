#[test_only]
module braid_clmm::fee_math_tests {
    use braid_clmm::fee_math as fm;

    const U256_MAX: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    const Q128: u256 = 340282366920938463463374607431768211456;
    const L: u128 = 1000000000000; // 1e12

    // ---------------------------------------------------------------- //
    // Modular arithmetic                                               //
    // ---------------------------------------------------------------- //

    #[test]
    fun wrapping_add_matches_normal_addition_until_it_cannot() {
        assert!(fm::wrapping_add(2, 3) == 5, 0);
        assert!(fm::wrapping_add(0, 0) == 0, 1);
        assert!(fm::wrapping_add(U256_MAX, 0) == U256_MAX, 2);

        // One past the top comes back to zero.
        assert!(fm::wrapping_add(U256_MAX, 1) == 0, 3);
        assert!(fm::wrapping_add(U256_MAX, 2) == 1, 4);
        assert!(fm::wrapping_add(U256_MAX - 5, 10) == 4, 5);
    }

    #[test]
    fun wrapping_sub_goes_round_the_bottom() {
        assert!(fm::wrapping_sub(5, 3) == 2, 0);
        assert!(fm::wrapping_sub(5, 5) == 0, 1);

        // Below zero wraps to the top.
        assert!(fm::wrapping_sub(0, 1) == U256_MAX, 2);
        assert!(fm::wrapping_sub(0, 2) == U256_MAX - 1, 3);
        assert!(fm::wrapping_sub(3, 10) == U256_MAX - 6, 4);
    }

    #[test]
    fun the_two_are_inverses_even_across_the_boundary() {
        // This is the property the whole scheme rests on: a counter read
        // modulo 2^256 still gives correct differences.
        let values = vector[0u256, 1, 12345, Q128, U256_MAX - 1, U256_MAX];
        let mut i = 0;
        while (i < 6) {
            let a = values[i];
            let mut j = 0;
            while (j < 6) {
                let b = values[j];
                assert!(fm::wrapping_sub(fm::wrapping_add(a, b), b) == a, i * 10 + j);
                assert!(fm::wrapping_add(fm::wrapping_sub(a, b), b) == a, 100 + i * 10 + j);
                j = j + 1;
            };
            i = i + 1;
        };
    }

    // ---------------------------------------------------------------- //
    // The global counter                                               //
    // ---------------------------------------------------------------- //

    #[test]
    fun growth_is_fees_per_unit_of_liquidity() {
        let a = fm::growth_from_fee(1000, L);
        assert!(a == 1000 * Q128 / (L as u256), 0);

        // Twice the liquidity, half the growth: the same fee shared wider.
        // Exact, because nested floor division composes.
        assert!(fm::growth_from_fee(1000, L * 2) == a / 2, 1);

        // Twice the fee is *not* exactly twice the growth. Each call floors
        // once, and `2 * floor(x)` is not `floor(2x)`. The gap is one unit of
        // a counter scaled by 2^128, so it is irrelevant to any payout -- but
        // it is the reason not to assume this function is linear.
        let doubled = fm::growth_from_fee(2000, L);
        assert!(doubled >= a * 2, 2);
        assert!(doubled - a * 2 <= 1, 3);
    }

    #[test]
    fun degenerate_inputs_grow_nothing() {
        assert!(fm::growth_from_fee(0, L) == 0, 0);
        assert!(fm::growth_from_fee(1000, 0) == 0, 1);
        assert!(fm::accrue(999, 0, L) == 999, 2);
    }

    #[test]
    fun accrue_accumulates() {
        let mut g: u256 = 0;
        g = fm::accrue(g, 1000, L);
        g = fm::accrue(g, 1000, L);
        g = fm::accrue(g, 1000, L);
        assert!(g == fm::growth_from_fee(1000, L) * 3, 0);
    }

    #[test]
    fun no_fee_is_ever_lost_at_the_growth_step() {
        // The Q128 scale is chosen so this cannot round to zero: liquidity is
        // a u128, so 2^128 / liquidity is at least 1 even at the maximum. A
        // single unit of fee against the deepest possible pool still moves the
        // counter. Q64.64 would not have this property, which is why fee
        // growth uses a wider scale than prices do.
        let max_liquidity: u128 = 340282366920938463463374607431768211455;
        assert!(fm::growth_from_fee(1, max_liquidity) == 1, 0);
        assert!(fm::growth_from_fee(1, L) > 0, 1);
    }

    // ---------------------------------------------------------------- //
    // Per-tick                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_tick_starts_with_everything_or_nothing_outside_it() {
        let global: u256 = 5000;
        assert!(fm::initial_outside(true, global) == global, 0);
        assert!(fm::initial_outside(false, global) == 0, 1);
    }

    #[test]
    fun crossing_a_tick_twice_returns_it_to_where_it_was() {
        // Crossing swaps which side is "outside". Cross back with the global
        // unchanged and the tick must be exactly as it started.
        let global: u256 = 9_000_000;
        let outside: u256 = 3_500_000;
        assert!(fm::cross(fm::cross(outside, global), global) == outside, 0);
    }

    #[test]
    fun crossing_works_when_the_subtraction_wraps() {
        // A tick initialized late can hold an outside value larger than the
        // region it describes. The wrap is expected, not an error.
        let global: u256 = 100;
        let outside: u256 = 500;
        let crossed = fm::cross(outside, global);
        assert!(crossed == fm::wrapping_sub(100, 500), 0);
        // And it still round-trips.
        assert!(fm::cross(crossed, global) == outside, 1);
    }

    // ---------------------------------------------------------------- //
    // Fee growth inside a range                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun inside_a_range_with_no_history_outside_is_the_whole_global() {
        // Price inside the range, both ticks initialized before any fees.
        let global: u256 = 1_000_000;
        let inside = fm::fee_growth_inside(global, 0, 0, true, true);
        assert!(inside == global, 0);
    }

    #[test]
    fun growth_outside_the_range_is_excluded() {
        let global: u256 = 1_000_000;
        // 300k accrued below the lower tick, 200k above the upper.
        let inside = fm::fee_growth_inside(global, 300_000, 200_000, true, true);
        assert!(inside == 500_000, 0);
    }

    #[test]
    fun the_price_being_outside_flips_which_side_is_subtracted() {
        let global: u256 = 1_000_000;
        let lower_outside: u256 = 300_000;
        let upper_outside: u256 = 200_000;

        // Price below the range: the lower tick's stored value now describes
        // the side the price is on, so the complement is what sits below.
        let below_range =
            fm::fee_growth_inside(global, lower_outside, upper_outside, false, true);
        assert!(below_range == fm::wrapping_sub(
            fm::wrapping_sub(global, fm::wrapping_sub(global, lower_outside)),
            upper_outside,
        ), 0);

        // Price above the range, mirrored.
        let above_range =
            fm::fee_growth_inside(global, lower_outside, upper_outside, true, false);
        assert!(above_range == fm::wrapping_sub(
            fm::wrapping_sub(global, lower_outside),
            fm::wrapping_sub(global, upper_outside),
        ), 1);
    }

    #[test]
    fun a_range_that_has_earned_nothing_reports_nothing() {
        // Price sits below the range the whole time, so everything the pool
        // earned is "below" and the range is owed zero.
        let global: u256 = 1_000_000;
        // The lower tick was crossed downward, so its outside holds the lot.
        let inside = fm::fee_growth_inside(global, global, 0, true, true);
        assert!(inside == 0, 0);
    }

    #[test]
    fun inside_growth_is_correct_even_when_every_step_wraps() {
        // The case the design exists for. Start the global counter near the
        // top so the intermediates go round, and check the answer against the
        // same computation done with small numbers.
        let base: u256 = 1_000_000;
        let lower: u256 = 300_000;
        let upper: u256 = 200_000;
        let small = fm::fee_growth_inside(base, lower, upper, true, true);

        // Shift everything by the same offset. Differences are unchanged, so
        // the answer must be too, even though the arithmetic now wraps.
        let offset = U256_MAX - 400_000;
        let shifted = fm::fee_growth_inside(
            fm::wrapping_add(base, offset),
            fm::wrapping_add(lower, offset),
            fm::wrapping_add(upper, offset),
            true,
            true,
        );
        assert!(small == 500_000, 0);
        // Shifting all three moves the result by exactly one offset.
        assert!(shifted == fm::wrapping_sub(small, offset), 1);
    }

    // ---------------------------------------------------------------- //
    // What a position is owed                                          //
    // ---------------------------------------------------------------- //

    #[test]
    fun fees_owed_is_liquidity_times_growth_less_the_truncation() {
        // A position holding *all* the liquidity gets 999 of a 1000-unit fee,
        // not 1000. Growth floors on the way in and the payout floors on the
        // way out, so a unit is left behind.
        //
        // That is the correct direction. The unit stays in the reserve, which
        // is exactly where an unclaimable fraction should sit -- crediting it
        // would mean paying out a fee the pool never collected.
        let growth = fm::growth_from_fee(1000, L);
        assert!(fm::fees_owed(L, growth, 0) == 999, 0);

        // Half the liquidity earns half, less the same rounding.
        assert!(fm::fees_owed(L / 2, growth, 0) == 499, 1);

        // The shares can never add up to more than the fee charged.
        assert!(fm::fees_owed(L / 2, growth, 0) * 2 <= 1000, 2);
    }

    #[test]
    fun only_growth_since_the_last_settlement_counts() {
        let g1 = fm::accrue(0, 1000, L);
        let g2 = fm::accrue(g1, 1000, L);

        // Settled at g1, so only the second swap's fee is owed.
        assert!(fm::fees_owed(L, g2, g1) == 999, 0);
        // Settled at g2, nothing owed.
        assert!(fm::fees_owed(L, g2, g2) == 0, 1);
    }

    #[test]
    fun a_position_with_no_liquidity_is_owed_nothing() {
        assert!(fm::fees_owed(0, fm::growth_from_fee(1000, L), 0) == 0, 0);
    }

    #[test]
    fun fees_owed_survives_a_wrapped_checkpoint() {
        // A position last settled just before the counter wrapped. The
        // difference is still small and the answer still right.
        let last = U256_MAX - 100;
        let now = fm::wrapping_add(last, fm::growth_from_fee(1000, L));
        // Same answer as the unwrapped case: the difference is what matters,
        // not where on the counter it sits.
        assert!(fm::fees_owed(L, now, last) == 999, 0);
        assert!(fm::fees_owed(L, now, last) == fm::fees_owed(L, fm::growth_from_fee(1000, L), 0), 1);
    }

    #[test]
    fun rounding_leaves_the_remainder_with_the_pool() {
        // 1 unit of fee against 3e12 liquidity, claimed by a third of it:
        // the true share is fractional and must round down, not up.
        let growth = fm::growth_from_fee(1, L * 3);
        let owed = fm::fees_owed(L, growth, 0);
        assert!(owed == 0, 0);
    }
}
