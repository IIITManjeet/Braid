#[test_only]
module braid_clmm::swap_math_tests {
    use braid_clmm::i32;
    use braid_clmm::swap_math as sm;
    use braid_clmm::tick_math;

    const P0: u128 = 18446744073709551616; // sqrt_price(0) = 1.0
    const L: u128 = 1000000000000;         // 1e12
    const FEE: u64 = 30;                   // 30 bps

    fun pos(v: u32): u128 { tick_math::sqrt_price_at_tick(i32::from_u32(v)) }
    fun neg(v: u32): u128 { tick_math::sqrt_price_at_tick(i32::neg_from(v)) }

    // ---------------------------------------------------------------- //
    // Price movement                                                   //
    // ---------------------------------------------------------------- //

    #[test]
    fun token0_in_moves_the_price_down() {
        // Values from the reference implementation.
        assert!(sm::next_sqrt_price_from_amount0_in(P0, L, 1000000) == 18446725626983924633, 0);
        assert!(sm::next_sqrt_price_from_amount0_in(P0, L, 1000000000) == 18428315757951600016, 1);
        assert!(sm::next_sqrt_price_from_amount0_in(P0, L, 100000000000) == 16769767339735956015, 2);

        // Monotone: more token0 in, lower price.
        let a = sm::next_sqrt_price_from_amount0_in(P0, L, 1000000);
        let b = sm::next_sqrt_price_from_amount0_in(P0, L, 1000000000);
        assert!(a < P0, 3);
        assert!(b < a, 4);
    }

    #[test]
    fun token1_in_moves_the_price_up() {
        assert!(sm::next_sqrt_price_from_amount1_in(P0, L, 1000000) == 18446762520453625325, 0);
        assert!(sm::next_sqrt_price_from_amount1_in(P0, L, 1000000000) == 18465190817783261167, 1);

        let a = sm::next_sqrt_price_from_amount1_in(P0, L, 1000000);
        let b = sm::next_sqrt_price_from_amount1_in(P0, L, 1000000000);
        assert!(a > P0, 2);
        assert!(b > a, 3);
    }

    #[test]
    fun token1_out_moves_the_price_down_further_than_token1_in_moves_it_up() {
        // The out-direction rounds its step up, the in-direction rounds down.
        // Both cost the trader; that asymmetry is the convention working.
        let up = sm::next_sqrt_price_from_amount1_in(P0, L, 1000000) - P0;
        let down = P0 - sm::next_sqrt_price_from_amount1_out(P0, L, 1000000);
        assert!(down >= up, 0);
        assert!(down - up <= 1, 1);
    }

    #[test]
    fun a_zero_amount_leaves_the_price_alone() {
        assert!(sm::next_sqrt_price_from_amount0_in(P0, L, 0) == P0, 0);
        assert!(sm::next_sqrt_price_from_amount1_in(P0, L, 0) == P0, 1);
        assert!(sm::next_sqrt_price_from_amount1_out(P0, L, 0) == P0, 2);
    }

    #[test]
    fun deeper_liquidity_moves_the_price_less() {
        // The whole point of depth: the same trade against more liquidity
        // barely shifts the price.
        let shallow = sm::next_sqrt_price_from_amount0_in(P0, 1000000000, 1000000);
        let deep = sm::next_sqrt_price_from_amount0_in(P0, 1000000000000000, 1000000);
        assert!(P0 - deep < P0 - shallow, 0);
    }

    #[test]
    fun the_price_never_moves_further_than_it_should() {
        // Conservatism, checked structurally rather than against a fixture:
        // adding token0 then reading the price back must not have overshot.
        // sp' >= L*sp*2^64 / (L*2^64 + dx*sp)  <=>  sp'*(L*2^64 + dx*sp) >= L*sp*2^64
        let amounts = vector[1u64, 1000, 1000000, 1000000000];
        let mut i = 0;
        while (i < 4) {
            let dx = amounts[i];
            let next = sm::next_sqrt_price_from_amount0_in(P0, L, dx);
            let lhs = (next as u256) * ((L as u256) * (1u256 << 64) + (dx as u256) * (P0 as u256));
            let rhs = (L as u256) * (P0 as u256) * (1u256 << 64);
            assert!(lhs >= rhs, i);
            i = i + 1;
        };
    }

    // ---------------------------------------------------------------- //
    // One swap step                                                    //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_small_trade_stops_short_of_the_boundary() {
        let target = neg(100);
        let (next, amount_in, amount_out, fee) = sm::compute_swap_step(P0, target, L, 1000000, FEE);

        assert!(next == 18446725682324046339, 0);
        assert!(next != target, 1);        // did not reach the boundary
        assert!(next < P0, 2);             // but did move
        assert!(amount_in == 997000, 3);
        assert!(amount_out == 996999, 4);
        assert!(fee == 3000, 5);
        // The whole budget is accounted for, with nothing stranded.
        assert!(amount_in + fee == 1000000, 6);
    }

    #[test]
    fun a_large_trade_stops_exactly_at_the_boundary() {
        let target = neg(100);
        let (next, amount_in, amount_out, fee) =
            sm::compute_swap_step(P0, target, L, 10000000000, FEE);

        assert!(next == target, 0);
        assert!(amount_in == 5012269624, 1);
        assert!(amount_out == 4987272070, 2);
        assert!(fee == 15082056, 3);
        // Stopping at the boundary leaves budget for the next step.
        assert!(amount_in + fee < 10000000000, 4);
    }

    #[test]
    fun the_two_directions_are_symmetric_at_price_one() {
        // Same distance either way from 1.0, same liquidity: the numbers
        // should mirror exactly.
        let (down_next, down_in, down_out, down_fee) =
            sm::compute_swap_step(P0, neg(100), L, 10000000000, FEE);
        let (up_next, up_in, up_out, up_fee) =
            sm::compute_swap_step(P0, pos(100), L, 10000000000, FEE);

        assert!(down_next == neg(100) && up_next == pos(100), 0);
        assert!(down_in == up_in, 1);
        assert!(down_out == up_out, 2);
        assert!(down_fee == up_fee, 3);
    }

    #[test]
    fun a_step_never_spends_more_than_the_budget() {
        let budgets = vector[1u64, 10000, 10000000, 10000000000, 100000000000];
        let mut i = 0;
        while (i < 5) {
            let budget = budgets[i];
            let (_, amount_in, _, fee) = sm::compute_swap_step(P0, neg(100), L, budget, FEE);
            assert!(amount_in + fee <= budget, i);
            i = i + 1;
        };
    }

    #[test]
    fun the_output_is_never_more_than_the_input_buys() {
        // At a price of 1.0 the two tokens are interchangeable, so the output
        // must not exceed the input net of fees -- anything more would be the
        // pool paying for the privilege.
        let (_, amount_in, amount_out, _) =
            sm::compute_swap_step(P0, neg(1000), L, 1000000000, FEE);
        assert!(amount_out <= amount_in, 0);
    }

    #[test]
    fun a_zero_fee_pool_charges_nothing() {
        let (_, amount_in, _, fee) = sm::compute_swap_step(P0, neg(100), L, 1000000, 0);
        assert!(fee == 0, 0);
        assert!(amount_in == 1000000, 1);
    }

    #[test]
    fun walking_two_steps_matches_one_larger_trade_in_direction() {
        // A swap that crosses a boundary is two calls. The price after the
        // second must be past the boundary, and the totals must add up.
        let boundary = neg(100);
        let budget = 10000000000;

        let (mid, in1, out1, fee1) = sm::compute_swap_step(P0, boundary, L, budget, FEE);
        assert!(mid == boundary, 0);

        let left = budget - in1 - fee1;
        let (fin, in2, out2, fee2) = sm::compute_swap_step(mid, neg(200), L, left, FEE);

        assert!(fin < boundary, 1);
        assert!(in1 + fee1 + in2 + fee2 <= budget, 2);
        assert!(out1 + out2 > out1, 3);
    }

    // ---------------------------------------------------------------- //
    // Guards                                                           //
    // ---------------------------------------------------------------- //

    #[test]
    #[expected_failure(abort_code = braid_clmm::swap_math::EZeroLiquidity)]
    fun a_price_move_with_no_liquidity_is_rejected() {
        sm::next_sqrt_price_from_amount0_in(P0, 0, 1000);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::swap_math::EInvalidFee)]
    fun a_fee_above_the_cap_is_rejected() {
        sm::compute_swap_step(P0, neg(100), L, 1000, sm::max_fee_bps() + 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::swap_math::EPriceUnderflow)]
    fun removing_more_token1_than_the_price_supports_is_rejected() {
        // Would take the sqrt price to zero or below.
        sm::next_sqrt_price_from_amount1_out(P0, L, 18446744073709551615);
    }
}
