#[test_only]
module braid_math::full_math_tests {
    use braid_math::full_math;

    const MAX_U64: u64 = 18446744073709551615;
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    // ---------------------------------------------------------------- //
    // full_mul                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun full_mul_is_exact() {
        assert!(full_math::full_mul(2, 3) == 6, 0);
        assert!(full_math::full_mul(0, MAX_U128) == 0, 1);
        // The whole point: this product needs 256 bits and must not abort.
        let big = full_math::full_mul(MAX_U128, MAX_U128);
        assert!(big > 0, 2);
    }

    // ---------------------------------------------------------------- //
    // Rounding direction -- the part that actually leaks money          //
    // ---------------------------------------------------------------- //

    #[test]
    fun rounding_modes_differ_on_a_remainder() {
        // 100 / 3 = 33.333...
        assert!(full_math::mul_div_floor(10, 10, 3) == 33, 0);
        assert!(full_math::mul_div_ceil(10, 10, 3) == 34, 1);
        assert!(full_math::mul_div_round(10, 10, 3) == 33, 2);

        // 100 / 6 = 16.666... -> round goes up
        assert!(full_math::mul_div_round(10, 10, 6) == 17, 3);

        // Exactly .5 -> ties away from zero
        assert!(full_math::mul_div_round(1, 1, 2) == 1, 4);
        assert!(full_math::mul_div_floor(1, 1, 2) == 0, 5);
    }

    #[test]
    fun rounding_modes_agree_when_exact() {
        assert!(full_math::mul_div_floor(10, 10, 5) == 20, 0);
        assert!(full_math::mul_div_ceil(10, 10, 5) == 20, 1);
        assert!(full_math::mul_div_round(10, 10, 5) == 20, 2);
    }

    // ---------------------------------------------------------------- //
    // The overflow this library exists to prevent                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun mul_div_survives_a_u128_overflowing_intermediate() {
        // a * b overflows u128 by a mile; a * b / d fits exactly.
        assert!(full_math::mul_div_floor(MAX_U128, MAX_U128, MAX_U128) == MAX_U128, 0);
        assert!(full_math::mul_div_ceil(MAX_U128, MAX_U128, MAX_U128) == MAX_U128, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::full_math::EOverflow)]
    fun mul_div_rejects_a_result_wider_than_u128() {
        // MAX * MAX / 1 does not fit in u128.
        full_math::mul_div_floor(MAX_U128, MAX_U128, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::full_math::EDivideByZero)]
    fun mul_div_floor_rejects_zero_denominator() {
        full_math::mul_div_floor(1, 1, 0);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::full_math::EDivideByZero)]
    fun mul_div_ceil_rejects_zero_denominator() {
        full_math::mul_div_ceil(1, 1, 0);
    }

    // ---------------------------------------------------------------- //
    // u64 wrappers                                                     //
    // ---------------------------------------------------------------- //

    #[test]
    fun u64_wrappers_match_their_u128_counterparts() {
        assert!(full_math::mul_div_floor_u64(10, 10, 3) == 33, 0);
        assert!(full_math::mul_div_ceil_u64(10, 10, 3) == 34, 1);
        assert!(full_math::mul_div_floor_u64(MAX_U64, MAX_U64, MAX_U64) == MAX_U64, 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_math::full_math::EOverflow)]
    fun u64_wrapper_rejects_a_result_wider_than_u64() {
        full_math::mul_div_floor_u64(MAX_U64, MAX_U64, 1);
    }

    // ---------------------------------------------------------------- //
    // Shifts -- the fixed-point primitives                              //
    // ---------------------------------------------------------------- //

    #[test]
    fun shifts_round_in_the_stated_direction() {
        // 7 * 1 / 2^1 = 3.5
        assert!(full_math::mul_shr(7, 1, 1) == 3, 0);
        assert!(full_math::mul_shr_ceil(7, 1, 1) == 4, 1);
        // Exact: no correction applied.
        assert!(full_math::mul_shr(8, 1, 1) == 4, 2);
        assert!(full_math::mul_shr_ceil(8, 1, 1) == 4, 3);

        // (3 << 1) / 4 = 1.5
        assert!(full_math::shl_div(3, 4, 1) == 1, 4);
        assert!(full_math::shl_div_ceil(3, 4, 1) == 2, 5);
    }

    #[test]
    fun shl_div_can_scale_past_u128() {
        // 1 << 127, divided by 1 -- exercises the u256 intermediate.
        assert!(full_math::shl_div(1, 1, 127) == 1 << 127, 0);
    }

    // ---------------------------------------------------------------- //
    // bit_length                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun bit_length_counts_significant_bits() {
        assert!(full_math::bit_length(0) == 0, 0);
        assert!(full_math::bit_length(1) == 1, 1);
        assert!(full_math::bit_length(2) == 2, 2);
        assert!(full_math::bit_length(3) == 2, 3);
        assert!(full_math::bit_length(255) == 8, 4);
        assert!(full_math::bit_length(256) == 9, 5);
        assert!(full_math::bit_length(1 << 200) == 201, 6);
    }

    // ---------------------------------------------------------------- //
    // sqrt                                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun sqrt_returns_the_floor() {
        assert!(full_math::sqrt_u256(0) == 0, 0);
        assert!(full_math::sqrt_u256(1) == 1, 1);
        assert!(full_math::sqrt_u256(2) == 1, 2);
        assert!(full_math::sqrt_u256(3) == 1, 3);
        assert!(full_math::sqrt_u256(4) == 2, 4);
        assert!(full_math::sqrt_u256(8) == 2, 5);
        assert!(full_math::sqrt_u256(9) == 3, 6);
        assert!(full_math::sqrt_u256(15) == 3, 7);
        assert!(full_math::sqrt_u256(16) == 4, 8);
        assert!(full_math::sqrt_u256(9999) == 99, 9);
        assert!(full_math::sqrt_u256(10000) == 100, 10);
    }

    #[test]
    fun sqrt_is_exact_at_the_top_of_the_range() {
        // (2^128 - 1)^2 is the largest square we ever take.
        let n = full_math::full_mul(MAX_U128, MAX_U128);
        assert!(full_math::sqrt_u256(n) == (MAX_U128 as u256), 0);
        // One less must land one below.
        assert!(full_math::sqrt_u256(n - 1) == (MAX_U128 as u256) - 1, 1);
    }

    #[test]
    fun sqrt_never_overestimates() {
        // z*z <= x < (z+1)*(z+1) for a scattering of inputs.
        let mut i: u256 = 1;
        while (i < 100000) {
            let z = full_math::sqrt_u256(i);
            assert!(z * z <= i, 0);
            assert!((z + 1) * (z + 1) > i, 1);
            i = i * 7 + 1;
        };
    }

    #[test]
    fun sqrt_mul_is_the_initial_lp_share_formula() {
        // sqrt(1_000_000 * 4_000_000) = sqrt(4e12) = 2_000_000
        assert!(full_math::sqrt_mul(1000000, 4000000) == 2000000, 0);
        // Would overflow u128 if the product were not widened first.
        assert!(full_math::sqrt_mul(MAX_U128, MAX_U128) == MAX_U128, 1);
    }

    #[test]
    fun sqrt_u128_agrees_with_sqrt_u256() {
        assert!(full_math::sqrt_u128(10000) == 100, 0);
        assert!(full_math::sqrt_u128(MAX_U128) == (full_math::sqrt_u256(MAX_U128 as u256) as u128), 1);
    }

    // ---------------------------------------------------------------- //
    // Misc                                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun comparators_and_abs_diff() {
        assert!(full_math::min_u128(3, 9) == 3, 0);
        assert!(full_math::max_of_u128(3, 9) == 9, 1);
        assert!(full_math::min_u64(3, 9) == 3, 2);
        assert!(full_math::max_of_u64(3, 9) == 9, 3);
        assert!(full_math::abs_diff(9, 3) == 6, 4);
        assert!(full_math::abs_diff(3, 9) == 6, 5);
        assert!(full_math::abs_diff(5, 5) == 0, 6);
        assert!(full_math::max_u64() == MAX_U64, 7);
        assert!(full_math::max_u128() == MAX_U128, 8);
    }
}
