#[test_only]
module braid_clmm::i32_tests {
    use braid_clmm::i32;

    #[test]
    fun construction_and_sign() {
        assert!(!i32::is_neg(i32::zero()), 0);
        assert!(!i32::is_neg(i32::from_u32(5)), 1);
        assert!(i32::is_neg(i32::neg_from(5)), 2);
        // Negative zero does not exist in two's complement.
        assert!(!i32::is_neg(i32::neg_from(0)), 3);
        assert!(i32::eq(i32::neg_from(0), i32::zero()), 4);
    }

    #[test]
    fun magnitude_survives_the_round_trip() {
        assert!(i32::abs_u32(i32::from_u32(689382)) == 689382, 0);
        assert!(i32::abs_u32(i32::neg_from(689382)) == 689382, 1);
        assert!(i32::abs_u32(i32::zero()) == 0, 2);
        // The extremes of the representable range.
        assert!(i32::abs_u32(i32::from_u32(2147483647)) == 2147483647, 3);
        assert!(i32::abs_u32(i32::neg_from(2147483647)) == 2147483647, 4);
    }

    #[test]
    fun negation_is_an_involution() {
        let a = i32::from_u32(12345);
        assert!(i32::eq(i32::neg(i32::neg(a)), a), 0);
        let b = i32::neg_from(12345);
        assert!(i32::eq(i32::neg(i32::neg(b)), b), 1);
        assert!(i32::eq(i32::neg(i32::zero()), i32::zero()), 2);
        assert!(i32::eq(i32::neg(a), b), 3);
    }

    #[test]
    fun addition_crosses_zero_correctly() {
        // -5 + 3 = -2
        let r = i32::add(i32::neg_from(5), i32::from_u32(3));
        assert!(i32::is_neg(r) && i32::abs_u32(r) == 2, 0);
        // 5 + (-3) = 2
        let r2 = i32::add(i32::from_u32(5), i32::neg_from(3));
        assert!(!i32::is_neg(r2) && i32::abs_u32(r2) == 2, 1);
        // 5 + (-5) = 0
        assert!(i32::eq(i32::add(i32::from_u32(5), i32::neg_from(5)), i32::zero()), 2);
        // -5 + -3 = -8
        let r3 = i32::add(i32::neg_from(5), i32::neg_from(3));
        assert!(i32::is_neg(r3) && i32::abs_u32(r3) == 8, 3);
    }

    #[test]
    fun subtraction_matches_adding_the_negation() {
        // 3 - 5 = -2
        let r = i32::sub(i32::from_u32(3), i32::from_u32(5));
        assert!(i32::is_neg(r) && i32::abs_u32(r) == 2, 0);
        // -3 - (-5) = 2
        let r2 = i32::sub(i32::neg_from(3), i32::neg_from(5));
        assert!(!i32::is_neg(r2) && i32::abs_u32(r2) == 2, 1);
        // x - x = 0, either sign
        assert!(i32::eq(i32::sub(i32::from_u32(77), i32::from_u32(77)), i32::zero()), 2);
        assert!(i32::eq(i32::sub(i32::neg_from(77), i32::neg_from(77)), i32::zero()), 3);
    }

    #[test]
    fun comparison_is_signed_not_unsigned() {
        // The trap: as raw bits, -1 is 0xFFFFFFFF and would compare as the
        // largest value of all. Signed comparison must put it below zero.
        assert!(i32::lt(i32::neg_from(1), i32::zero()), 0);
        assert!(i32::lt(i32::neg_from(1), i32::from_u32(1)), 1);
        assert!(i32::lt(i32::neg_from(2), i32::neg_from(1)), 2);
        assert!(i32::gt(i32::from_u32(1), i32::neg_from(1)), 3);
        assert!(i32::lt(i32::neg_from(689382), i32::neg_from(1)), 4);

        assert!(i32::lte(i32::from_u32(5), i32::from_u32(5)), 5);
        assert!(i32::gte(i32::from_u32(5), i32::from_u32(5)), 6);
        assert!(!i32::lt(i32::from_u32(5), i32::from_u32(5)), 7);
    }

    #[test]
    fun min_and_max_respect_sign() {
        let neg = i32::neg_from(100);
        let pos = i32::from_u32(100);
        assert!(i32::eq(i32::min(neg, pos), neg), 0);
        assert!(i32::eq(i32::max(neg, pos), pos), 1);
        assert!(i32::eq(i32::min(i32::neg_from(5), i32::neg_from(9)), i32::neg_from(9)), 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::i32::EOverflow)]
    fun a_magnitude_past_the_signed_range_is_rejected() {
        i32::from_u32(2147483648);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::i32::EOverflow)]
    fun a_negative_magnitude_past_the_signed_range_is_rejected() {
        i32::neg_from(2147483648);
    }
}
