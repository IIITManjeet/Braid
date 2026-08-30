#[test_only]
module braid_math::q64_tests {
    use braid_math::q64;
    use braid_math::full_math;

    const MAX_U64: u64 = 18446744073709551615;
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// 2^64 -- 1.0
    const ONE: u128 = 18446744073709551616;
    /// 2^63 -- 0.5
    const HALF: u128 = 9223372036854775808;
    /// 2^62 -- 0.25
    const QUARTER: u128 = 4611686018427387904;
    /// floor(2^64 / 3) -- the canonical inexact value
    const THIRD_FLOOR: u128 = 6148914691236517205;

    // ---------------------------------------------------------------- //
    // Representation                                                   //
    // ---------------------------------------------------------------- //

    #[test]
    fun constants_are_the_representation_they_claim() {
        assert!(q64::one() == ONE, 0);
        assert!(q64::zero() == 0, 1);
        assert!(q64::fractional_bits() == 64, 2);
        assert!(q64::is_zero(0), 3);
        assert!(!q64::is_zero(1), 4);
    }

    #[test]
    fun integers_convert_exactly_and_round_trip() {
        assert!(q64::from_u64(0) == 0, 0);
        assert!(q64::from_u64(1) == ONE, 1);
        assert!(q64::from_u64(5) == 5 * ONE, 2);
        assert!(q64::to_u64_floor(q64::from_u64(5)) == 5, 3);
        assert!(q64::to_u64_ceil(q64::from_u64(5)) == 5, 4);
        // The widest integer still fits, because (2^64 - 1) * 2^64 < 2^128.
        assert!(q64::to_u64_floor(q64::from_u64(MAX_U64)) == MAX_U64, 5);
    }

    #[test]
    fun fractions_split_into_integer_and_fractional_parts() {
        let v = q64::from_u64(5) + HALF; // 5.5
        assert!(q64::floor(v) == q64::from_u64(5), 0);
        assert!(q64::fract(v) == HALF, 1);
        assert!(q64::to_u64_floor(v) == 5, 2);
        assert!(q64::to_u64_ceil(v) == 6, 3);
        // A whole number has no fraction to carry.
        assert!(q64::fract(q64::from_u64(5)) == 0, 4);
    }

    #[test]
    fun from_frac_brackets_the_true_value() {
        assert!(q64::from_frac_floor(1, 2) == HALF, 0);
        assert!(q64::from_frac_ceil(1, 2) == HALF, 1); // exact: both agree
        assert!(q64::from_frac_floor(1, 3) == THIRD_FLOOR, 2);
        assert!(q64::from_frac_ceil(1, 3) == THIRD_FLOOR + 1, 3);
        assert!(q64::from_frac_floor(7, 1) == q64::from_u64(7), 4);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EOverflow)]
    fun to_u64_ceil_rejects_a_carry_out_of_the_integer_field() {
        // MAX_U128 is 2^64 - 1 plus a fraction; rounding up needs 2^64.
        q64::to_u64_ceil(MAX_U128);
    }

    // ---------------------------------------------------------------- //
    // Arithmetic                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun add_and_sub_are_exact() {
        assert!(q64::add(HALF, HALF) == ONE, 0);
        assert!(q64::sub(ONE, HALF) == HALF, 1);
        assert!(q64::sub(ONE, ONE) == 0, 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EUnderflow)]
    fun sub_rejects_going_below_zero() {
        q64::sub(HALF, ONE);
    }

    #[test]
    fun multiplying_by_one_is_the_identity() {
        assert!(q64::mul_floor(THIRD_FLOOR, ONE) == THIRD_FLOOR, 0);
        assert!(q64::mul_ceil(THIRD_FLOOR, ONE) == THIRD_FLOOR, 1);
        assert!(q64::div_floor(THIRD_FLOOR, ONE) == THIRD_FLOOR, 2);
        assert!(q64::div_ceil(THIRD_FLOOR, ONE) == THIRD_FLOOR, 3);
    }

    #[test]
    fun mul_and_div_agree_with_the_scaled_arithmetic() {
        assert!(q64::mul_floor(HALF, HALF) == QUARTER, 0);
        assert!(q64::mul_floor(q64::from_u64(3), q64::from_u64(4)) == q64::from_u64(12), 1);
        assert!(q64::div_floor(q64::from_u64(12), q64::from_u64(4)) == q64::from_u64(3), 2);
        assert!(q64::div_floor(ONE, q64::from_u64(2)) == HALF, 3);
    }

    #[test]
    fun rounding_pairs_differ_by_exactly_one_when_inexact() {
        // (2^64/3)^2 is not a multiple of 2^64, so the shift truncates.
        let f = q64::mul_floor(THIRD_FLOOR, THIRD_FLOOR);
        assert!(q64::mul_ceil(THIRD_FLOOR, THIRD_FLOOR) == f + 1, 0);

        // 1 / 3 again, this time through the divide path.
        assert!(q64::div_floor(ONE, q64::from_u64(3)) == THIRD_FLOOR, 1);
        assert!(q64::div_ceil(ONE, q64::from_u64(3)) == THIRD_FLOOR + 1, 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::full_math::EDivideByZero)]
    fun div_floor_reports_a_zero_denominator_through_full_math() {
        q64::div_floor(ONE, 0);
    }

    // ---------------------------------------------------------------- //
    // Mixed integer / fixed-point -- where the rounding is money        //
    // ---------------------------------------------------------------- //

    #[test]
    fun scaling_an_integer_by_one_returns_it_unchanged() {
        assert!(q64::mul_u64_floor(1000, ONE) == 1000, 0);
        assert!(q64::mul_u64_ceil(1000, ONE) == 1000, 1);
        assert!(q64::div_u64_floor(1000, ONE) == 1000, 2);
        assert!(q64::div_u64_ceil(1000, ONE) == 1000, 3);
        assert!(q64::mul_u64_floor(MAX_U64, ONE) == MAX_U64, 4);
    }

    #[test]
    fun scaling_an_integer_rounds_in_the_stated_direction() {
        // 1000 * (1/3) = 333.33...
        assert!(q64::mul_u64_floor(1000, THIRD_FLOOR) == 333, 0);
        assert!(q64::mul_u64_ceil(1000, THIRD_FLOOR) == 334, 1);

        // 1000 / 3 = 333.33...
        assert!(q64::div_u64_floor(1000, q64::from_u64(3)) == 333, 2);
        assert!(q64::div_u64_ceil(1000, q64::from_u64(3)) == 334, 3);

        // Exact division carries no correction.
        assert!(q64::div_u64_floor(1000, q64::from_u64(4)) == 250, 4);
        assert!(q64::div_u64_ceil(1000, q64::from_u64(4)) == 250, 5);

        // Scaling to zero: a floor payout can round away the whole amount,
        // which is exactly why the collect-side uses ceil.
        assert!(q64::mul_u64_floor(1, HALF) == 0, 6);
        assert!(q64::mul_u64_ceil(1, HALF) == 1, 7);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EOverflow)]
    fun mul_u64_floor_rejects_a_result_wider_than_u64() {
        q64::mul_u64_floor(MAX_U64, q64::from_u64(2));
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EOverflow)]
    fun div_u64_floor_rejects_a_result_wider_than_u64() {
        // Dividing by a value below 1.0 magnifies.
        q64::div_u64_floor(MAX_U64, HALF);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EDivideByZero)]
    fun div_u64_floor_rejects_a_zero_divisor() {
        q64::div_u64_floor(1, 0);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EDivideByZero)]
    fun div_u64_ceil_rejects_a_zero_divisor() {
        q64::div_u64_ceil(1, 0);
    }

    // ---------------------------------------------------------------- //
    // sqrt                                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun sqrt_is_exact_on_perfect_squares() {
        assert!(q64::sqrt(0) == 0, 0);
        assert!(q64::sqrt(ONE) == ONE, 1);
        assert!(q64::sqrt(q64::from_u64(4)) == q64::from_u64(2), 2);
        assert!(q64::sqrt(q64::from_u64(9)) == q64::from_u64(3), 3);
        assert!(q64::sqrt(QUARTER) == HALF, 4);
    }

    #[test]
    fun sqrt_returns_the_floor_of_the_true_root() {
        // r^2 <= v * 2^64 < (r+1)^2, checked in raw units at u256 width.
        let mut i: u128 = 1;
        while (i < 1000000000000000000) {
            let r = q64::sqrt(i);
            let scaled = (i as u256) << 64;
            assert!(full_math::full_mul(r, r) <= scaled, 0);
            assert!(full_math::full_mul(r + 1, r + 1) > scaled, 1);
            i = i * 13 + 7;
        };
    }

    #[test]
    fun sqrt_survives_the_top_of_the_range() {
        // The shift to 192 bits is the whole reason this needs a u256.
        let r = q64::sqrt(MAX_U128);
        assert!(full_math::full_mul(r, r) <= ((MAX_U128 as u256) << 64), 0);
        assert!(full_math::full_mul(r + 1, r + 1) > ((MAX_U128 as u256) << 64), 1);
    }

    // ---------------------------------------------------------------- //
    // Reciprocal                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun recip_inverts_exact_powers_of_two() {
        assert!(q64::recip_floor(ONE) == ONE, 0);
        assert!(q64::recip_ceil(ONE) == ONE, 1);
        assert!(q64::recip_floor(q64::from_u64(2)) == HALF, 2);
        assert!(q64::recip_floor(q64::from_u64(4)) == QUARTER, 3);
        assert!(q64::recip_floor(HALF) == q64::from_u64(2), 4);
    }

    #[test]
    fun recip_brackets_one_from_both_sides() {
        // v * floor(1/v) <= 1 <= v * ceil(1/v), for a value with no exact inverse.
        let v = q64::from_u64(3);
        assert!(q64::mul_floor(v, q64::recip_floor(v)) <= ONE, 0);
        assert!(q64::mul_ceil(v, q64::recip_ceil(v)) >= ONE, 1);
        assert!(q64::recip_ceil(v) == q64::recip_floor(v) + 1, 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EDivideByZero)]
    fun recip_floor_rejects_zero() {
        q64::recip_floor(0);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EDivideByZero)]
    fun recip_ceil_rejects_zero() {
        q64::recip_ceil(0);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::q64::EOverflow)]
    fun recip_floor_rejects_an_inverse_past_the_range() {
        // The smallest representable value, 2^-64, inverts to 2^64 -- which as
        // a Q64.64 raw value is 2^128 and does not fit.
        q64::recip_floor(1);
    }

    // ---------------------------------------------------------------- //
    // pow                                                              //
    // ---------------------------------------------------------------- //

    #[test]
    fun pow_handles_the_degenerate_exponents() {
        assert!(q64::pow_floor(q64::from_u64(7), 0) == ONE, 0);
        assert!(q64::pow_floor(q64::from_u64(7), 1) == q64::from_u64(7), 1);
        assert!(q64::pow_floor(ONE, 1000) == ONE, 2);
        assert!(q64::pow_floor(0, 5) == 0, 3);
    }

    #[test]
    fun pow_is_exact_on_powers_of_two() {
        assert!(q64::pow_floor(q64::from_u64(2), 10) == q64::from_u64(1024), 0);
        assert!(q64::pow_floor(q64::from_u64(2), 63) == q64::from_u64(1 << 63), 1);
        assert!(q64::pow_floor(HALF, 2) == QUARTER, 2);
        assert!(q64::pow_floor(HALF, 64) == 1, 3); // 2^-64, the last representable bit
    }

    #[test]
    fun pow_stays_inside_the_repeated_multiplication_bracket() {
        // Repeated multiplication truncates once per step; squaring truncates
        // once per *bit* of the exponent. Both under-approximate the true
        // power, but squaring loses less, so `pow_floor` lands at or above the
        // floor-rounded loop -- and never above the ceil-rounded one, which
        // over-approximates.
        let base = q64::from_u64(1) + q64::from_frac_floor(1, 100); // 1.01
        let mut lo = ONE;
        let mut hi = ONE;
        let mut i: u64 = 0;
        while (i < 20) {
            lo = q64::mul_floor(lo, base);
            hi = q64::mul_ceil(hi, base);
            i = i + 1;
        };
        let got = q64::pow_floor(base, 20);
        assert!(got >= lo, 0);
        assert!(got <= hi, 1);
        // The whole spread is a handful of ulp on a value of ~1.22 * 2^64.
        assert!(full_math::abs_diff(hi, lo) < 64, 2);
    }

    // ---------------------------------------------------------------- //
    // Comparison                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun min_and_max_pick_the_right_side() {
        assert!(q64::min(HALF, ONE) == HALF, 0);
        assert!(q64::max(HALF, ONE) == ONE, 1);
        assert!(q64::min(ONE, ONE) == ONE, 2);
    }
}
