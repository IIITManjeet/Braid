#[test_only]
module braid_clmm::tick_math_tests {
    use braid_clmm::i32::{Self, I32};
    use braid_clmm::tick_math;

    /// `1.0` in Q64.64 — the price at tick 0.
    const ONE_Q64: u128 = 18446744073709551616;

    fun pos(v: u32): I32 { i32::from_u32(v) }
    fun neg(v: u32): I32 { i32::neg_from(v) }

    // ---------------------------------------------------------------- //
    // Fixtures                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun tick_zero_is_price_one() {
        // 1.0001^0 = 1, and sqrt(1) = 1.
        assert!(tick_math::sqrt_price_at_tick(i32::zero()) == ONE_Q64, 0);
    }

    #[test]
    fun sqrt_price_matches_the_reference_values() {
        // Computed independently at 120 decimal digits.
        assert!(tick_math::sqrt_price_at_tick(pos(1)) == 18447666387855959851, 0);
        assert!(tick_math::sqrt_price_at_tick(neg(1)) == 18445821805675392312, 1);
        assert!(tick_math::sqrt_price_at_tick(pos(100)) == 18539204128674405813, 2);
        assert!(tick_math::sqrt_price_at_tick(neg(100)) == 18354745142194483564, 3);
        assert!(tick_math::sqrt_price_at_tick(pos(1000)) == 19392480388906836278, 4);
        assert!(tick_math::sqrt_price_at_tick(neg(1000)) == 17547129613991598782, 5);
        assert!(tick_math::sqrt_price_at_tick(pos(100000)) == 2737055259406582257881, 6);
        assert!(tick_math::sqrt_price_at_tick(neg(100000)) == 124324258982887575, 7);
    }

    #[test]
    fun the_bounds_are_the_prices_at_the_extreme_ticks() {
        assert!(
            tick_math::sqrt_price_at_tick(tick_math::min_tick())
                == tick_math::min_sqrt_price(),
            0,
        );
        assert!(
            tick_math::sqrt_price_at_tick(tick_math::max_tick())
                == tick_math::max_sqrt_price(),
            1,
        );
        assert!(tick_math::min_sqrt_price() == 19812, 2);
        assert!(tick_math::max_sqrt_price() == 17175572088390372486202642652453860, 3);
    }

    #[test]
    fun one_tick_is_five_basis_points_of_sqrt_price() {
        // A tick is 1bp of *price*, so sqrt(price) moves by about half that.
        let at_zero = tick_math::sqrt_price_at_tick(i32::zero());
        let at_one = tick_math::sqrt_price_at_tick(pos(1));
        let delta = at_one - at_zero;
        // ~0.005% of 2^64 is ~9.2e14. Bracket it loosely; the point is the
        // order of magnitude, not the exact value.
        assert!(delta > 900000000000000, 0);
        assert!(delta < 930000000000000, 1);
    }

    // ---------------------------------------------------------------- //
    // Structure                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun price_is_strictly_increasing_in_tick() {
        // Sampled across the range rather than exhaustive — all 1,378,765
        // ticks were checked in the generator, this guards the port.
        let mut t: u32 = 0;
        let mut prev_pos = tick_math::sqrt_price_at_tick(i32::zero());
        let mut prev_neg = prev_pos;
        while (t < 689382) {
            t = t + 7919; // a prime step, so the sample is not aligned to bits
            if (t > 689382) break;

            let up = tick_math::sqrt_price_at_tick(pos(t));
            assert!(up > prev_pos, 0);
            prev_pos = up;

            let down = tick_math::sqrt_price_at_tick(neg(t));
            assert!(down < prev_neg, 1);
            prev_neg = down;
        };
    }

    #[test]
    fun negative_ticks_are_below_one_and_positive_above() {
        assert!(tick_math::sqrt_price_at_tick(neg(1)) < ONE_Q64, 0);
        assert!(tick_math::sqrt_price_at_tick(pos(1)) > ONE_Q64, 1);
        assert!(tick_math::sqrt_price_at_tick(tick_math::min_tick()) < ONE_Q64, 2);
        assert!(tick_math::sqrt_price_at_tick(tick_math::max_tick()) > ONE_Q64, 3);
    }

    #[test]
    fun opposite_ticks_are_reciprocal_prices() {
        // sqrt_price(t) * sqrt_price(-t) should be 1.0, i.e. 2^128 in raw
        // Q64.64 terms. Rounding makes it approximate, so allow a few ulp.
        let t = 5000;
        let up = (tick_math::sqrt_price_at_tick(pos(t)) as u256);
        let down = (tick_math::sqrt_price_at_tick(neg(t)) as u256);
        let product = up * down;
        let one = (ONE_Q64 as u256) * (ONE_Q64 as u256);
        let diff = if (product > one) product - one else one - product;
        // Within one part in 10^15 of exactly 1.0.
        assert!(diff / (one / 1000000000000000) == 0, 0);
    }

    // ---------------------------------------------------------------- //
    // The inverse                                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_inverse_recovers_the_tick_exactly() {
        let ticks = vector[0u32, 1, 100, 1000, 50000, 689382];
        let mut i = 0;
        while (i < 6) {
            let t = ticks[i];

            let up = pos(t);
            assert!(i32::eq(tick_math::tick_at_sqrt_price(tick_math::sqrt_price_at_tick(up)), up), i);

            let down = neg(t);
            assert!(
                i32::eq(tick_math::tick_at_sqrt_price(tick_math::sqrt_price_at_tick(down)), down),
                i + 100,
            );
            i = i + 1;
        };
    }

    #[test]
    fun the_inverse_rounds_down_between_ticks() {
        // A price just above tick 1000 still belongs to tick 1000, because the
        // inverse returns the greatest tick whose price does not exceed it.
        let at_1000 = tick_math::sqrt_price_at_tick(pos(1000));
        let at_1001 = tick_math::sqrt_price_at_tick(pos(1001));
        let between = at_1000 + (at_1001 - at_1000) / 2;

        assert!(i32::eq(tick_math::tick_at_sqrt_price(between), pos(1000)), 0);
        // One unit below the next tick is still the current tick.
        assert!(i32::eq(tick_math::tick_at_sqrt_price(at_1001 - 1), pos(1000)), 1);
        // And landing exactly on it crosses.
        assert!(i32::eq(tick_math::tick_at_sqrt_price(at_1001), pos(1001)), 2);
    }

    #[test]
    fun the_inverse_handles_the_bounds() {
        assert!(
            i32::eq(
                tick_math::tick_at_sqrt_price(tick_math::min_sqrt_price()),
                tick_math::min_tick(),
            ),
            0,
        );
        assert!(
            i32::eq(
                tick_math::tick_at_sqrt_price(tick_math::max_sqrt_price()),
                tick_math::max_tick(),
            ),
            1,
        );
    }

    // ---------------------------------------------------------------- //
    // Guards                                                           //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_range_check_agrees_with_the_bounds() {
        assert!(tick_math::is_valid_tick(tick_math::max_tick()), 0);
        assert!(tick_math::is_valid_tick(tick_math::min_tick()), 1);
        assert!(!tick_math::is_valid_tick(pos(689383)), 2);
        assert!(!tick_math::is_valid_tick(neg(689383)), 3);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_math::EInvalidTick)]
    fun a_tick_above_the_range_is_rejected() {
        tick_math::sqrt_price_at_tick(pos(689383));
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_math::EInvalidTick)]
    fun a_tick_below_the_range_is_rejected() {
        tick_math::sqrt_price_at_tick(neg(689383));
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_math::EInvalidSqrtPrice)]
    fun a_price_below_the_range_is_rejected() {
        tick_math::tick_at_sqrt_price(tick_math::min_sqrt_price() - 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_math::EInvalidSqrtPrice)]
    fun a_price_above_the_range_is_rejected() {
        tick_math::tick_at_sqrt_price(tick_math::max_sqrt_price() + 1);
    }
}
