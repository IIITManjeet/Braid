#[test_only]
module braid_stable::stable_math_tests {
    use braid_stable::stable_math;
    use braid_cpmm::cpmm_math;

    /// 1e9 units a side. Big enough that a 10% trade is a real trade.
    const R: u64 = 1000000000;
    /// `A = 100`, stored pre-multiplied by A_PRECISION.
    const AMP: u64 = 10000;
    /// 4 bps -- typical for a stable pair.
    const FEE: u64 = 4;

    const ONE_Q64: u128 = 18446744073709551616;

    // ---------------------------------------------------------------- //
    // D -- the invariant                                               //
    // ---------------------------------------------------------------- //

    #[test]
    fun d_is_the_sum_when_the_pool_is_balanced() {
        // At the balance point the constant-sum term dominates exactly, so the
        // invariant collapses to x + y. True for any amplification.
        assert!(stable_math::get_d(R, R, AMP) == 2000000000, 0);
        assert!(stable_math::get_d(R, R, 100) == 2000000000, 1);
        assert!(stable_math::get_d(R, R, 100000000) == 2000000000, 2);
        assert!(stable_math::get_d(1, 1, AMP) == 2, 3);
    }

    #[test]
    fun d_falls_below_the_sum_once_the_pool_is_skewed() {
        // 2:1 skew. Value computed independently from Curve's reference.
        let d = stable_math::get_d(R, R / 2, AMP);
        assert!(d == 1499073492, 0);
        assert!(d < ((R + R / 2) as u128), 1);
    }

    #[test]
    fun d_is_symmetric_at_moderate_skew_but_not_at_extremes() {
        // Where the solver converges cleanly, argument order is irrelevant.
        assert!(stable_math::get_d(R, R / 2, AMP) == stable_math::get_d(R / 2, R, AMP), 0);

        // At extreme skew it is *not* symmetric, and that is a property of the
        // reference algorithm rather than a defect here: D_P accumulates its
        // floor divisions one coin at a time, and floor division does not
        // commute with itself. Two units apart on a D of ~167k.
        assert!(stable_math::get_d(7, 999999, AMP) == 167134, 1);
        assert!(stable_math::get_d(999999, 7, AMP) == 167136, 2);

        // Which is harmless in a pool -- the coin order is fixed by the struct,
        // so a given pool always evaluates its own invariant the same way. It
        // is recorded here so a future refactor that "tidies" the argument
        // order gets caught rather than silently repricing every pool.
    }

    #[test]
    fun newton_terminates_across_a_wide_range_of_states() {
        // Reserve ratios from 1:1 out to roughly 1:1000, at three very
        // different amplifications. The solver aborts rather than return a
        // wrong price, so reaching the end of this test is the assertion.
        let amps = vector[100u64, 10000u64, 100000000u64];
        let mut a = 0;
        while (a < 3) {
            let amp = amps[a];
            let mut x = 1000000u64;
            while (x < 250000000) {
                let d = stable_math::get_d(R, x, amp);
                assert!(d > 0, 0);
                // D never exceeds the sum, and never falls to zero.
                assert!(d <= ((R as u128) + (x as u128)), 1);
                x = x * 3;
            };
            a = a + 1;
        };
    }

    #[test]
    fun the_solver_resolves_states_where_the_reference_would_revert() {
        // Each of these drives the iteration into a limit cycle: it steps
        // between a handful of adjacent integers forever and the plain
        // |D - D_prev| <= 1 rule never fires. Curve's implementation burns all
        // 255 iterations here and reverts; the orbit detector returns.

        // A 1000:1 skew at A = 1 -- a 2-cycle between ...746 and ...748.
        assert!(stable_math::get_d(R, 1000000, 100) == 193404748, 0);

        // A 2000:1 skew at A = 1 -- a 5-cycle spanning ...182 to ...186.
        assert!(stable_math::get_d(606615483488917, 302485337224, 100) == 93681094686186, 1);

        // The most degenerate pool that can exist: one unit against a billion.
        assert!(stable_math::get_d(R, 1, AMP) == 9254663, 2);
    }

    #[test]
    fun a_pool_in_a_limit_cycle_still_prices_swaps_safely() {
        // The state from the 2-cycle above, actually traded against. The
        // invariant must still not fall.
        let skewed = 1000000;
        let before = stable_math::get_d(R, skewed, 100);
        let out = stable_math::amount_out(500000, R, skewed, 100, FEE);
        assert!(out > 0, 0);
        assert!(out < skewed, 1);
        let after = stable_math::get_d(R + 500000, skewed - out, 100);
        assert!(after >= before, 2);
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun amount_out_matches_the_reference_implementation() {
        // Three trade sizes against a balanced 1e9 pool, each value produced by
        // an independent implementation of Curve's algorithm.
        assert!(stable_math::amount_out(1000000, R, R, AMP, FEE) == 999590, 0);
        assert!(stable_math::amount_out(10000000, R, R, AMP, FEE) == 9995009, 1);
        assert!(stable_math::amount_out(100000000, R, R, AMP, FEE) == 99860149, 2);
    }

    #[test]
    fun the_curve_is_flat_near_the_peg() {
        // A 0.1% trade loses ~4bps -- essentially just the fee.
        let out = stable_math::amount_out(1000000, R, R, AMP, FEE);
        let loss_bps = (1000000 - out) * 10000 / 1000000;
        assert!(loss_bps <= 5, 0);

        // A 10% trade still only loses ~14bps. On a constant-product pool the
        // same trade loses over 900bps.
        let big = stable_math::amount_out(100000000, R, R, AMP, FEE);
        let big_loss_bps = (100000000 - big) * 10000 / 100000000;
        assert!(big_loss_bps <= 20, 1);
    }

    #[test]
    fun stableswap_beats_constant_product_on_a_pegged_pair() {
        // The entire reason this venue exists, checked against the real CPMM
        // package rather than a remembered number.
        let sizes = vector[1000000u64, 10000000u64, 100000000u64];
        let mut i = 0;
        while (i < 3) {
            let dx = sizes[i];
            let stable = stable_math::amount_out(dx, R, R, AMP, FEE);
            let cp = cpmm_math::amount_out(dx, R, R, FEE);
            assert!(stable > cp, i);
            i = i + 1;
        };

        // And the gap widens with size: at 10% of the pool the stableswap pays
        // out ~9% more than constant product does.
        let stable = stable_math::amount_out(100000000, R, R, AMP, FEE);
        let cp = cpmm_math::amount_out(100000000, R, R, FEE);
        assert!(stable == 99860149, 10);
        assert!(cp == 90876031, 11);
        assert!(stable - cp > 8000000, 12);
    }

    #[test]
    fun higher_amplification_flattens_the_curve() {
        // A = 10, 100, 1000 against the same 10% trade.
        let low = stable_math::amount_out(100000000, R, R, 1000, FEE);
        let mid = stable_math::amount_out(100000000, R, R, 10000, FEE);
        let high = stable_math::amount_out(100000000, R, R, 100000, FEE);

        assert!(low == 99052097, 0);
        assert!(mid == 99860149, 1);
        assert!(high == 99949914, 2);
        assert!(low < mid && mid < high, 3);

        // Even the flattest setting still charges something -- it is never a
        // pure constant-sum pool, which is what stops a depeg draining it.
        assert!(high < 100000000, 4);
    }

    #[test]
    fun price_impact_grows_with_size() {
        let a = stable_math::amount_out(1000000, R, R, AMP, FEE);
        let b = stable_math::amount_out(10000000, R, R, AMP, FEE);
        // Ten times the input yields strictly less than ten times the output.
        assert!(b < a * 10, 0);
    }

    #[test]
    fun a_swap_never_lowers_the_invariant() {
        let sizes = vector[1000u64, 1000000u64, 100000000u64, 400000000u64];
        let mut i = 0;
        while (i < 4) {
            let dx = sizes[i];
            let before = stable_math::get_d(R, R, AMP);
            let out = stable_math::amount_out(dx, R, R, AMP, FEE);
            let after = stable_math::get_d(R + dx, R - out, AMP);
            // The fee plus the rounding unit make it strictly grow.
            assert!(after > before, i);
            i = i + 1;
        };
    }

    #[test]
    fun the_swap_direction_is_symmetric_on_a_balanced_pool() {
        assert!(
            stable_math::amount_out(1000000, R, R, AMP, FEE)
                == stable_math::amount_out(1000000, R, R, AMP, FEE),
            0,
        );
        // Skewing one way and quoting the other reverses the advantage.
        let into_deep = stable_math::amount_out(1000000, R / 2, R, AMP, FEE);
        let into_shallow = stable_math::amount_out(1000000, R, R / 2, AMP, FEE);
        assert!(into_deep > into_shallow, 1);
    }

    // ---------------------------------------------------------------- //
    // Exact-out                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun amount_in_matches_the_reference_implementation() {
        assert!(stable_math::amount_in(999590, R, R, AMP, FEE) == 1000001, 0);
    }

    #[test]
    fun paying_the_exact_out_quote_always_clears_the_target() {
        // The direction that matters: a trader who asks for exactly `dy` and
        // pays the quoted input must never receive less than `dy`.
        let targets = vector[1000u64, 999590u64, 9995009u64, 50000000u64];
        let mut i = 0;
        while (i < 4) {
            let dy = targets[i];
            let dx = stable_math::amount_in(dy, R, R, AMP, FEE);
            let got = stable_math::amount_out(dx, R, R, AMP, FEE);
            assert!(got >= dy, i);
            i = i + 1;
        };
    }

    #[test]
    fun the_exact_out_quote_errs_towards_the_pool() {
        // Round-tripping a quote back through the other direction asks for at
        // most one extra unit -- never one fewer.
        let dx = 1000000;
        let out = stable_math::amount_out(dx, R, R, AMP, FEE);
        let back = stable_math::amount_in(out, R, R, AMP, FEE);
        assert!(back >= dx, 0);
        assert!(back <= dx + 1, 1);
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun initial_lp_is_the_invariant_itself() {
        // Shares denominated in D, so a fresh share is worth exactly 1.0.
        assert!(stable_math::initial_lp(R, R, AMP) == 2000000000, 0);
    }

    #[test]
    fun a_balanced_deposit_pays_no_imbalance_fee() {
        let (minted, fee_0, fee_1) =
            stable_math::lp_for_deposit(1000000, 1000000, R, R, 2 * R, AMP, FEE);
        assert!(minted == 2000000, 0); // exactly proportional
        assert!(fee_0 == 0 && fee_1 == 0, 1);
    }

    #[test]
    fun a_one_sided_deposit_is_charged_for_the_imbalance() {
        // Same total value as the balanced deposit above, all on one side.
        let (minted, fee_0, fee_1) =
            stable_math::lp_for_deposit(2000000, 0, R, R, 2 * R, AMP, FEE);
        assert!(minted == 1999589, 0);
        assert!(fee_0 == 201 && fee_1 == 200, 1);

        // Strictly worse than depositing on ratio -- which is the point. Free
        // one-sided deposits are a swap that pays no swap fee.
        let (balanced, _, _) =
            stable_math::lp_for_deposit(1000000, 1000000, R, R, 2 * R, AMP, FEE);
        assert!(minted < balanced, 2);
    }

    #[test]
    fun the_imbalance_fee_is_half_the_swap_fee_for_two_coins() {
        // n / (4(n-1)) at n = 2.
        assert!(stable_math::imbalance_fee_bps(4) == 2, 0);
        assert!(stable_math::imbalance_fee_bps(100) == 50, 1);
        // Rounded up, so an odd fee never rounds to the trader's benefit.
        assert!(stable_math::imbalance_fee_bps(5) == 3, 2);
        assert!(stable_math::imbalance_fee_bps(0) == 0, 3);
    }

    #[test]
    fun withdrawing_is_proportional() {
        let (a, b) = stable_math::withdraw_amounts(2000000, R, R, 2 * R);
        assert!(a == 1000000 && b == 1000000, 0);
        // Skewed pool pays out the skew, not the peg.
        let (c, d) = stable_math::withdraw_amounts(1000000, R, R / 2, 2 * R);
        assert!(c == 500000 && d == 250000, 1);
    }

    #[test]
    fun deposit_then_withdraw_never_profits() {
        let (minted, fee_0, fee_1) =
            stable_math::lp_for_deposit(1000000, 1000000, R, R, 2 * R, AMP, FEE);
        let (back_a, back_b) = stable_math::withdraw_amounts(
            minted,
            R + 1000000 - fee_0,
            R + 1000000 - fee_1,
            2 * R + minted,
        );
        assert!(back_a <= 1000000, 0);
        assert!(back_b <= 1000000, 1);
    }

    // ---------------------------------------------------------------- //
    // Virtual price -- the number LPs actually watch                    //
    // ---------------------------------------------------------------- //

    #[test]
    fun virtual_price_starts_at_exactly_one() {
        assert!(stable_math::virtual_price(R, R, 2 * R, AMP) == ONE_Q64, 0);
    }

    #[test]
    fun virtual_price_only_ever_rises() {
        let before = stable_math::virtual_price(R, R, 2 * R, AMP);

        // A swap raises D without minting a single share.
        let out = stable_math::amount_out(10000000, R, R, AMP, FEE);
        let after = stable_math::virtual_price(R + 10000000, R - out, 2 * R, AMP);
        assert!(after > before, 0);

        // D grew by the fee plus the rounding unit.
        assert!(stable_math::get_d(R + 10000000, R - out, AMP) == 2000004001, 1);
    }

    // ---------------------------------------------------------------- //
    // Guards                                                           //
    // ---------------------------------------------------------------- //

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInvalidAmp)]
    fun amplification_below_the_floor_is_rejected() {
        stable_math::get_d(R, R, stable_math::min_amp() - 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInvalidAmp)]
    fun amplification_above_the_ceiling_is_rejected() {
        stable_math::get_d(R, R, stable_math::max_amp() + 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInvalidFee)]
    fun a_fee_above_the_cap_is_rejected() {
        stable_math::amount_out(1000, R, R, AMP, stable_math::max_fee_bps() + 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EZeroAmount)]
    fun a_zero_input_is_rejected() {
        stable_math::amount_out(0, R, R, AMP, FEE);
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInsufficientLiquidity)]
    fun an_empty_reserve_is_rejected() {
        stable_math::amount_out(1000, 0, R, AMP, FEE);
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInsufficientLiquidity)]
    fun buying_the_whole_output_reserve_is_rejected() {
        stable_math::amount_in(R, R, R, AMP, FEE);
    }
}
