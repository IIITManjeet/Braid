#[test_only]
module braid_stable::pool_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};

    use braid_stable::pool::{Self, StablePool, SLP};
    use braid_stable::stable_math;

    /// A pegged pair.
    public struct USDC has drop {}
    public struct USDT has drop {}

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    const R: u64 = 1000000000;
    const AMP: u64 = 10000; // A = 100
    const FEE: u64 = 4;     // 4 bps

    const ONE_Q64: u128 = 18446744073709551616;

    fun seed_pool(scenario: &mut Scenario, a: u64, b: u64, amp: u64, fee_bps: u64) {
        let ctx = scenario.ctx();
        let coin_a = coin::mint_for_testing<USDC>(a, ctx);
        let coin_b = coin::mint_for_testing<USDT>(b, ctx);
        let lp = pool::create_pool(coin_a, coin_b, amp, fee_bps, ctx);
        transfer::public_transfer(lp, ADMIN);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_fresh_pool_has_shares_worth_exactly_one() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(ADMIN);
        {
            let p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R && reserve_b == R, 0);
            assert!(pool::amp(&p) == AMP, 1);
            assert!(pool::fee_bps(&p) == FEE, 2);

            // Shares are denominated in D, and D == the sum at balance.
            assert!(pool::invariant_d(&p) == 2000000000, 3);
            assert!(pool::lp_supply_value(&p) == 2000000000, 4);
            assert!(pool::virtual_price(&p) == ONE_Q64, 5);
            ts::return_shared(p);

            let lp = scenario.take_from_sender<Coin<SLP<USDC, USDT>>>();
            assert!(coin::value(&lp) == 2000000000 - stable_math::minimum_liquidity(), 6);
            ts::return_to_sender(&scenario, lp);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() {
        let mut scenario = ts::begin(ADMIN);
        {
            let ctx = scenario.ctx();
            let coin_a = coin::mint_for_testing<USDC>(R, ctx);
            let coin_b = coin::mint_for_testing<USDC>(R, ctx);
            let lp = pool::create_pool(coin_a, coin_b, AMP, FEE, ctx);
            transfer::public_transfer(lp, ADMIN);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::stable_math::EInvalidAmp)]
    fun an_out_of_range_amplification_is_rejected() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, stable_math::max_amp() + 1, FEE);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::pool::EInvalidFee)]
    fun a_fee_above_the_cap_is_rejected() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, stable_math::max_fee_bps() + 1);
        scenario.end();
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_pays_exactly_what_the_quote_promised() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let quoted = pool::quote_a_for_b(&p, 1000000);
            let d_before = pool::invariant_d(&p);

            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(1000000, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);

            assert!(coin::value(&out) == quoted, 0);
            assert!(quoted == 999590, 1);
            // 0.1% of the pool traded for a total cost of ~4bps -- the fee.
            assert!(1000000 - quoted == 410, 2);

            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R + 1000000, 3);
            assert!(reserve_b == R - quoted, 4);
            assert!(pool::invariant_d(&p) > d_before, 5);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun the_pool_stays_flat_under_a_large_trade() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            // 10% of the pool in one trade.
            let coin_in = coin::mint_for_testing<USDC>(100000000, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
            assert!(coin::value(&out) == 99860149, 0);
            // Under 15bps all-in, on a trade that would cost >900bps on a
            // constant-product pool of the same depth.
            assert!((100000000 - coin::value(&out)) * 10000 / 100000000 <= 15, 1);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_stable::pool::ESlippage)]
    fun a_swap_below_min_out_aborts() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(1000000, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 999591, ctx);
            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun a_round_trip_loses_only_the_two_fees() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(10000000, ctx);
            let mid = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
            let back = pool::swap_b_for_a(&mut p, mid, 0, ctx);

            let returned = coin::value(&back);
            assert!(returned < 10000000, 0);
            // Two 4bps fees plus a little curvature: well under 20bps total.
            assert!((10000000 - returned) * 10000 / 10000000 <= 20, 1);

            coin::burn_for_testing(back);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun swapping_the_pool_far_off_peg_still_holds_the_invariant() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        // Five large same-direction trades, driving the pool badly off balance.
        let mut n = 0;
        while (n < 5) {
            scenario.next_tx(TRADER);
            {
                let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
                let d_before = pool::invariant_d(&p);
                let ctx = scenario.ctx();
                let coin_in = coin::mint_for_testing<USDC>(150000000, ctx);
                let out = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
                assert!(pool::invariant_d(&p) >= d_before, 0);
                coin::burn_for_testing(out);
                ts::return_shared(p);
            };
            n = n + 1;
        };

        scenario.next_tx(TRADER);
        {
            let p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            // Deeply skewed -- and still solvent and still quoting.
            assert!(reserve_a > reserve_b * 2, 1);
            assert!(pool::quote_a_for_b(&p, 1000000) > 0, 2);
            // Pushing further into the shallow side now costs real money,
            // which is exactly the constant-product floor doing its job.
            assert!(pool::quote_a_for_b(&p, 1000000) < 999590, 3);
            ts::return_shared(p);
        };
        scenario.end();
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_balanced_deposit_mints_proportionally_and_free() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            let coin_a = coin::mint_for_testing<USDC>(1000000, ctx);
            let coin_b = coin::mint_for_testing<USDT>(1000000, ctx);
            let lp = pool::add_liquidity(&mut p, coin_a, coin_b, 0, ctx);

            assert!(coin::value(&lp) == 2000000, 0);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R + 1000000 && reserve_b == R + 1000000, 1);

            coin::burn_for_testing(lp);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun a_one_sided_deposit_pays_the_imbalance_fee() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            // Same total value as the balanced deposit above, all on one side.
            let coin_a = coin::mint_for_testing<USDC>(2000000, ctx);
            let coin_b = coin::mint_for_testing<USDT>(0, ctx);
            let lp = pool::add_liquidity(&mut p, coin_a, coin_b, 0, ctx);

            assert!(coin::value(&lp) == 1999589, 0);
            // Strictly worse than depositing on ratio. A free one-sided deposit
            // would be a swap that paid no swap fee.
            assert!(coin::value(&lp) < 2000000, 1);

            coin::burn_for_testing(lp);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun removing_liquidity_returns_the_proportional_share() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let mut lp = scenario.take_from_sender<Coin<SLP<USDC, USDT>>>();

            let ctx = scenario.ctx();
            let slice = coin::split(&mut lp, 2000000, ctx);
            let (out_a, out_b) = pool::remove_liquidity(&mut p, slice, 0, 0, ctx);

            // 2e6 of a 2e9 supply, against 1e9 on each side.
            assert!(coin::value(&out_a) == 1000000, 0);
            assert!(coin::value(&out_b) == 1000000, 1);

            coin::burn_for_testing(out_a);
            coin::burn_for_testing(out_b);
            ts::return_to_sender(&scenario, lp);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun the_locked_floor_survives_every_holder_exiting() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let lp = scenario.take_from_sender<Coin<SLP<USDC, USDT>>>();
            let ctx = scenario.ctx();
            let (out_a, out_b) = pool::remove_liquidity(&mut p, lp, 0, 0, ctx);

            let min = stable_math::minimum_liquidity();
            assert!(pool::lp_supply_value(&p) == min, 0);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a > 0 && reserve_b > 0, 1);

            coin::burn_for_testing(out_a);
            coin::burn_for_testing(out_b);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun the_share_price_only_ever_rises() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            assert!(pool::virtual_price(&p) == ONE_Q64, 0);

            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(10000000, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);

            // The fee stayed in the pool and no shares were minted for it.
            assert!(pool::virtual_price(&p) > ONE_Q64, 1);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun swap_fees_accrue_to_liquidity_providers() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000000, ctx);
            let mid = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
            let back = pool::swap_b_for_a(&mut p, mid, 0, ctx);
            coin::burn_for_testing(back);
            ts::return_shared(p);
        };

        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let lp = scenario.take_from_sender<Coin<SLP<USDC, USDT>>>();
            let shares = coin::value(&lp);
            let ctx = scenario.ctx();
            let (out_a, out_b) = pool::remove_liquidity(&mut p, lp, 0, 0, ctx);

            // The creator deposited `shares / 2` of each side (shares are
            // denominated in D, which is the sum). A round trip left more.
            assert!(coin::value(&out_a) + coin::value(&out_b) > shares, 0);

            coin::burn_for_testing(out_a);
            coin::burn_for_testing(out_b);
            ts::return_shared(p);
        };
        scenario.end();
    }

    // ---------------------------------------------------------------- //
    // Exact-out                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_exact_out_quote_is_what_the_swap_actually_costs() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, AMP, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<StablePool<USDC, USDT>>(&scenario);
            let needed = pool::quote_in_for_b(&p, 999590);
            assert!(needed == 1000001, 0);

            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(needed, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 999590, ctx);
            assert!(coin::value(&out) >= 999590, 1);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }
}
