#[test_only]
module braid_cpmm::cpmm_math_tests {
    use braid_cpmm::cpmm_math;

    const MAX_U64: u64 = 18446744073709551615;

    /// A pool deep enough that rounding is visible but not dominant.
    const R: u64 = 1000000;
    /// 0.30%, the conventional CPMM fee.
    const FEE: u64 = 30;

    // ---------------------------------------------------------------- //
    // Fees                                                             //
    // ---------------------------------------------------------------- //

    #[test]
    fun fee_is_charged_on_the_input_and_rounded_up() {
        assert!(cpmm_math::fee_amount(1000, FEE) == 3, 0); // exactly 3
        assert!(cpmm_math::fee_amount(0, FEE) == 0, 1);
        // The grind guard: any non-zero trade pays at least one unit.
        assert!(cpmm_math::fee_amount(1, FEE) == 1, 2);
        assert!(cpmm_math::fee_amount(333, FEE) == 1, 3); // 0.999 -> 1
        assert!(cpmm_math::fee_amount(1000, 0) == 0, 4);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EInvalidFee)]
    fun fee_above_the_cap_is_rejected() {
        cpmm_math::fee_amount(1000, cpmm_math::max_fee_bps() + 1);
    }

    // ---------------------------------------------------------------- //
    // Exact-in                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun amount_out_matches_the_hand_computed_quote() {
        // fee = ceil(1000 * 30 / 10000) = 3, so 997 reaches the curve.
        // floor(997 * 1000000 / 1000997) = 996
        assert!(cpmm_math::amount_out(1000, R, R, FEE) == 996, 0);
        // Without the fee the whole 1000 reaches the curve.
        // floor(1000 * 1000000 / 1001000) = 999
        assert!(cpmm_math::amount_out(1000, R, R, 0) == 999, 1);
    }

    #[test]
    fun output_is_always_strictly_below_the_output_reserve() {
        // Even an input that dwarfs the pool cannot drain it.
        let out = cpmm_math::amount_out(MAX_U64 / 2, R, R, FEE);
        assert!(out < R, 0);
        assert!(out > 0, 1);
    }

    #[test]
    fun a_trade_too_small_to_survive_the_fee_returns_nothing() {
        // 1 unit in at 10% fee: the fee rounds up and consumes the whole input.
        assert!(cpmm_math::amount_out(1, R, R, cpmm_math::max_fee_bps()) == 0, 0);
    }

    #[test]
    fun price_impact_is_monotone_and_concave() {
        // Twice the input never yields twice the output -- that is the slippage.
        let small = cpmm_math::amount_out(1000, R, R, FEE);
        let large = cpmm_math::amount_out(2000, R, R, FEE);
        assert!(large > small, 0);
        assert!(large < small * 2, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EZeroAmount)]
    fun amount_out_rejects_a_zero_input() {
        cpmm_math::amount_out(0, R, R, FEE);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EInsufficientLiquidity)]
    fun amount_out_rejects_an_empty_pool() {
        cpmm_math::amount_out(1000, 0, R, FEE);
    }

    // ---------------------------------------------------------------- //
    // Exact-out                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun amount_in_matches_the_hand_computed_quote() {
        // ceil(996 * 1000000 / 999004) = 997 on the curve,
        // grossed up: ceil(997 * 10000 / 9970) = 1000.
        assert!(cpmm_math::amount_in(996, R, R, FEE) == 1000, 0);
    }

    #[test]
    fun the_two_directions_are_a_conservative_inverse() {
        // Quoting out-then-in never asks for more than the original input;
        // quoting in-then-out never delivers less than the original output.
        let mut amount = 1u64;
        while (amount < 100000) {
            let out = cpmm_math::amount_out(amount, R, R, FEE);
            if (out > 0) {
                let back = cpmm_math::amount_in(out, R, R, FEE);
                assert!(back <= amount, 0);
                // And re-quoting that input still clears the output.
                assert!(cpmm_math::amount_out(back, R, R, FEE) >= out, 1);
            };
            amount = amount * 3 + 1;
        };
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EInsufficientLiquidity)]
    fun amount_in_refuses_to_quote_the_whole_reserve() {
        // Draining the pool exactly would take infinite input.
        cpmm_math::amount_in(R, R, R, FEE);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EOverflow)]
    fun amount_in_rejects_a_price_that_overflows_u64() {
        // Buying almost the entire output reserve of a pool whose input
        // reserve is enormous needs more input than a u64 can hold.
        cpmm_math::amount_in(R - 1, MAX_U64, R, FEE);
    }

    // ---------------------------------------------------------------- //
    // The invariant                                                    //
    // ---------------------------------------------------------------- //

    #[test]
    fun k_never_decreases_across_a_swap() {
        let mut amount = 1u64;
        while (amount < 500000) {
            let out = cpmm_math::amount_out(amount, R, R, FEE);
            let before = cpmm_math::k(R, R);
            let after = cpmm_math::k(R + amount, R - out);
            assert!(after >= before, 0);
            amount = amount * 7 + 1;
        };
    }

    #[test]
    fun the_fee_is_what_makes_k_strictly_grow() {
        let amount = 100000;
        let before = cpmm_math::k(R, R);

        let out_with_fee = cpmm_math::amount_out(amount, R, R, FEE);
        assert!(cpmm_math::k(R + amount, R - out_with_fee) > before, 0);

        // At zero fee the growth is only what truncation leaves behind, so the
        // invariant holds but barely -- this is the LP's entire income.
        let out_no_fee = cpmm_math::amount_out(amount, R, R, 0);
        assert!(out_no_fee > out_with_fee, 1);
        assert!(cpmm_math::k(R + amount, R - out_no_fee) >= before, 2);
    }

    #[test]
    fun k_uses_a_u256_and_does_not_wrap() {
        // Two near-max reserves would overflow any u128 product.
        let big = MAX_U64;
        assert!(cpmm_math::k(big, big) > (big as u256), 0);
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun initial_lp_is_the_geometric_mean_less_the_locked_floor() {
        assert!(cpmm_math::initial_lp(R, R) == R - cpmm_math::minimum_liquidity(), 0);
        // sqrt(1e6 * 4e6) = 2e6
        assert!(cpmm_math::initial_lp(R, 4 * R) == 2 * R - cpmm_math::minimum_liquidity(), 1);
        // Doubling both reserves doubles the shares.
        assert!(
            cpmm_math::initial_lp(2 * R, 2 * R) + cpmm_math::minimum_liquidity()
                == 2 * (cpmm_math::initial_lp(R, R) + cpmm_math::minimum_liquidity()),
            2,
        );
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EInsufficientLiquidity)]
    fun a_seed_that_cannot_cover_the_locked_floor_is_rejected() {
        let min = cpmm_math::minimum_liquidity();
        cpmm_math::initial_lp(min, min);
    }

    #[test]
    fun deposits_mint_against_the_scarcer_side() {
        let supply = R; // sqrt(R * R), i.e. the pool above including the lock
        // On ratio: mints proportionally.
        assert!(cpmm_math::lp_for_deposit(1000, 1000, R, R, supply) == 1000, 0);
        // Off ratio: the surplus B is a donation, not extra shares.
        assert!(cpmm_math::lp_for_deposit(1000, 5000, R, R, supply) == 1000, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EZeroLiquidityMinted)]
    fun a_deposit_too_small_to_mint_a_share_is_rejected() {
        // Rounding down to zero shares would be a pure donation; make it abort
        // rather than silently confiscate the deposit.
        cpmm_math::lp_for_deposit(1, 1, MAX_U64 / 2, MAX_U64 / 2, 1000);
    }

    #[test]
    fun optimal_deposit_pivots_to_whichever_side_binds() {
        // B is plentiful: take all of A and the matching B.
        let (a, b) = cpmm_math::optimal_deposit(1000, 5000, R, 2 * R);
        assert!(a == 1000 && b == 2000, 0);

        // A is plentiful: pivot and take all of B instead.
        let (a2, b2) = cpmm_math::optimal_deposit(5000, 2000, R, 2 * R);
        assert!(a2 == 1000 && b2 == 2000, 1);

        // Never asks for more than was offered.
        assert!(a2 <= 5000 && b2 <= 2000, 2);
    }

    #[test]
    fun withdrawing_is_proportional_and_rounds_down() {
        let (a, b) = cpmm_math::withdraw_amounts(1000, R, 2 * R, R);
        assert!(a == 1000 && b == 2000, 0);

        // Burning everything cannot pay out more than the reserves hold.
        let (all_a, all_b) = cpmm_math::withdraw_amounts(R, R, 2 * R, R);
        assert!(all_a == R && all_b == 2 * R, 1);
    }

    #[test]
    fun deposit_then_withdraw_never_profits() {
        // Round-tripping a deposit through the LP accounting must return at
        // most what went in -- otherwise it is a mint.
        let supply = R;
        let minted = cpmm_math::lp_for_deposit(12345, 12345, R, R, supply);
        let (back_a, back_b) = cpmm_math::withdraw_amounts(
            minted,
            R + 12345,
            R + 12345,
            supply + minted,
        );
        assert!(back_a <= 12345, 0);
        assert!(back_b <= 12345, 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::cpmm_math::EInsufficientLiquidity)]
    fun withdrawing_more_than_the_supply_is_rejected() {
        cpmm_math::withdraw_amounts(R + 1, R, R, R);
    }

    // ---------------------------------------------------------------- //
    // Spot price                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun spot_price_is_q64_64() {
        // 2e6 of B per 1e6 of A = 2.0
        assert!(cpmm_math::spot_price(R, 2 * R) == 2 << 64, 0);
        assert!(cpmm_math::spot_price(R, R) == 1 << 64, 1);
        // Half a B per A.
        assert!(cpmm_math::spot_price(2 * R, R) == 1 << 63, 2);
    }

    #[test]
    fun spot_price_is_the_limit_of_the_execution_price() {
        // A vanishingly small trade executes at close to spot; a large one does
        // not. Compare 1 unit in against the marginal rate at zero fee.
        let out = cpmm_math::amount_out(1000, R, 2 * R, 0);
        // Spot says 2000; slippage makes it slightly less.
        assert!(out < 2000, 0);
        assert!(out > 1990, 1);
    }
}
