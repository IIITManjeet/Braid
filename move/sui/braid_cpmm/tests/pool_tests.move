#[test_only]
module braid_cpmm::pool_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};

    use braid_cpmm::pool::{Self, Pool, LP};
    use braid_cpmm::cpmm_math;

    /// Two coin types that exist only to be distinct.
    public struct USDC has drop {}
    public struct WETH has drop {}

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    const R: u64 = 1000000;
    const FEE: u64 = 30;

    // ---------------------------------------------------------------- //
    // Helpers                                                          //
    // ---------------------------------------------------------------- //

    fun seed_pool(scenario: &mut Scenario, amount_a: u64, amount_b: u64, fee_bps: u64) {
        let ctx = scenario.ctx();
        let coin_a = coin::mint_for_testing<USDC>(amount_a, ctx);
        let coin_b = coin::mint_for_testing<WETH>(amount_b, ctx);
        let lp = pool::create_pool(coin_a, coin_b, fee_bps, ctx);
        transfer::public_transfer(lp, ADMIN);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun creating_a_pool_locks_the_floor_and_pays_out_the_rest() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(ADMIN);
        {
            let p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R && reserve_b == R, 0);
            assert!(pool::fee_bps(&p) == FEE, 1);
            // sqrt(R * R) = R shares in total, minted in full...
            assert!(pool::lp_supply_value(&p) == R, 2);
            ts::return_shared(p);

            // ...but the creator only receives what is left after the lock.
            let lp = scenario.take_from_sender<Coin<LP<USDC, WETH>>>();
            assert!(coin::value(&lp) == R - cpmm_math::minimum_liquidity(), 3);
            ts::return_to_sender(&scenario, lp);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() {
        let mut scenario = ts::begin(ADMIN);
        {
            let ctx = scenario.ctx();
            let coin_a = coin::mint_for_testing<USDC>(R, ctx);
            let coin_b = coin::mint_for_testing<USDC>(R, ctx);
            let lp = pool::create_pool(coin_a, coin_b, FEE, ctx);
            transfer::public_transfer(lp, ADMIN);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::pool::EInvalidFee)]
    fun a_pool_above_the_fee_cap_is_rejected() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, cpmm_math::max_fee_bps() + 1);
        scenario.end();
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_pays_exactly_what_the_quote_promised() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            // The quote a client would read off-chain, before submitting.
            let quoted = pool::quote_a_for_b(&p, 1000);
            let k_before = pool::invariant_k(&p);

            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(1000, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);

            assert!(coin::value(&out) == quoted, 0);
            assert!(quoted == 996, 1); // the hand-computed value

            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R + 1000, 2);
            assert!(reserve_b == R - quoted, 3);
            // The fee stayed in the pool, so k strictly grew.
            assert!(pool::invariant_k(&p) > k_before, 4);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun swapping_both_ways_is_symmetric() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let ctx = scenario.ctx();
            // A balanced pool quotes the same price in either direction.
            let coin_in = coin::mint_for_testing<WETH>(1000, ctx);
            let out = pool::swap_b_for_a(&mut p, coin_in, 0, ctx);
            assert!(coin::value(&out) == 996, 0);

            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R - 996, 1);
            assert!(reserve_b == R + 1000, 2);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun a_round_trip_loses_the_fee() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let ctx = scenario.ctx();

            let coin_in = coin::mint_for_testing<USDC>(10000, ctx);
            let mid = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
            let back = pool::swap_b_for_a(&mut p, mid, 0, ctx);

            // Two 30bps fees plus slippage, so strictly less than went in.
            assert!(coin::value(&back) < 10000, 0);
            // But not catastrophically less -- roughly 60bps of round-trip cost.
            assert!(coin::value(&back) > 9900, 1);

            coin::burn_for_testing(back);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_cpmm::pool::ESlippage)]
    fun a_swap_below_min_out_aborts() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(1000, ctx);
            // The pool can only pay 996.
            let out = pool::swap_a_for_b(&mut p, coin_in, 997, ctx);
            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun the_exact_out_quote_is_what_the_swap_actually_costs() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let needed = pool::quote_in_for_b(&p, 996);

            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(needed, ctx);
            let out = pool::swap_a_for_b(&mut p, coin_in, 996, ctx);
            // Paying the exact-out quote delivers at least the target.
            assert!(coin::value(&out) >= 996, 0);

            coin::burn_for_testing(out);
            ts::return_shared(p);
        };
        scenario.end();
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun adding_off_ratio_liquidity_refunds_the_surplus() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let ctx = scenario.ctx();

            // Offering 1000 A and 5000 B into a 1:1 pool.
            let coin_a = coin::mint_for_testing<USDC>(1000, ctx);
            let coin_b = coin::mint_for_testing<WETH>(5000, ctx);
            let (lp, refund_a, refund_b) = pool::add_liquidity(&mut p, coin_a, coin_b, 0, ctx);

            assert!(coin::value(&lp) == 1000, 0);
            assert!(coin::value(&refund_a) == 0, 1);
            assert!(coin::value(&refund_b) == 4000, 2); // the surplus comes back

            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R + 1000 && reserve_b == R + 1000, 3);
            assert!(pool::lp_supply_value(&p) == R + 1000, 4);

            coin::burn_for_testing(lp);
            coin::burn_for_testing(refund_a);
            coin::burn_for_testing(refund_b);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun removing_liquidity_returns_the_proportional_share() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let mut lp = scenario.take_from_sender<Coin<LP<USDC, WETH>>>();

            let ctx = scenario.ctx();
            let half = coin::split(&mut lp, 1000, ctx);
            let (out_a, out_b) = pool::remove_liquidity(&mut p, half, 0, 0, ctx);

            // 1000 shares of a 1e6-share pool holding 1e6 of each side.
            assert!(coin::value(&out_a) == 1000, 0);
            assert!(coin::value(&out_b) == 1000, 1);

            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == R - 1000 && reserve_b == R - 1000, 2);
            assert!(pool::lp_supply_value(&p) == R - 1000, 3);

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
        seed_pool(&mut scenario, R, R, FEE);

        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let lp = scenario.take_from_sender<Coin<LP<USDC, WETH>>>();

            let ctx = scenario.ctx();
            let (out_a, out_b) = pool::remove_liquidity(&mut p, lp, 0, 0, ctx);

            // Everything the creator held is gone, but the pool is not empty:
            // MINIMUM_LIQUIDITY shares remain, held by the pool itself.
            let min = cpmm_math::minimum_liquidity();
            assert!(pool::lp_supply_value(&p) == min, 0);
            let (reserve_a, reserve_b) = pool::reserves(&p);
            assert!(reserve_a == min && reserve_b == min, 1);
            assert!(coin::value(&out_a) == R - min, 2);
            assert!(coin::value(&out_b) == R - min, 3);

            coin::burn_for_testing(out_a);
            coin::burn_for_testing(out_b);
            ts::return_shared(p);
        };
        scenario.end();
    }

    #[test]
    fun swap_fees_accrue_to_the_remaining_liquidity_providers() {
        let mut scenario = ts::begin(ADMIN);
        seed_pool(&mut scenario, R, R, FEE);

        // A trader churns the pool in both directions, paying fees each way.
        scenario.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let ctx = scenario.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000, ctx);
            let mid = pool::swap_a_for_b(&mut p, coin_in, 0, ctx);
            let back = pool::swap_b_for_a(&mut p, mid, 0, ctx);
            coin::burn_for_testing(back);
            ts::return_shared(p);
        };

        // The creator's shares are now worth more than they deposited.
        scenario.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&scenario);
            let lp = scenario.take_from_sender<Coin<LP<USDC, WETH>>>();
            let shares = coin::value(&lp);

            let ctx = scenario.ctx();
            let (out_a, out_b) = pool::remove_liquidity(&mut p, lp, 0, 0, ctx);

            // Deposited `shares` worth of each side at 1:1; a round trip leaves
            // the pool A-heavy, so A comes back up and B comes back near flat.
            assert!(coin::value(&out_a) > shares, 0);
            // Total value across both sides beat the deposit.
            assert!(coin::value(&out_a) + coin::value(&out_b) > shares * 2, 1);

            coin::burn_for_testing(out_a);
            coin::burn_for_testing(out_b);
            ts::return_shared(p);
        };
        scenario.end();
    }
}
