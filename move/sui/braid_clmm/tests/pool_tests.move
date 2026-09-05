#[test_only]
module braid_clmm::pool_tests {
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self as ts, Scenario};

    use braid_clmm::i32::{Self, I32};
    use braid_clmm::pool::{Self, Pool};
    use braid_clmm::tick_math;

    public struct USDC has drop {}
    public struct WETH has drop {}

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    /// sqrt_price(0) = 1.0 in Q64.64.
    const P0: u128 = 18446744073709551616;
    const FEE: u64 = 30;
    const SPACING: u32 = 10;

    fun pos(v: u32): I32 { i32::from_u32(v) }
    fun neg(v: u32): I32 { i32::neg_from(v) }

    fun start(): Scenario {
        let mut sc = ts::begin(ADMIN);
        {
            let ctx = sc.ctx();
            pool::create_pool<USDC, WETH>(P0, FEE, SPACING, ctx);
        };
        sc.next_tx(ADMIN);
        sc
    }

    /// Open a position and return the change, burning it.
    fun provide(
        sc: &mut Scenario,
        p: &mut Pool<USDC, WETH>,
        lower: I32,
        upper: I32,
        amount: u64,
    ) {
        let ctx = sc.ctx();
        let a = coin::mint_for_testing<USDC>(amount, ctx);
        let b = coin::mint_for_testing<WETH>(amount, ctx);
        let (ra, rb) = pool::add_liquidity(p, lower, upper, a, b, ctx);
        coin::burn_for_testing(ra);
        coin::burn_for_testing(rb);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_new_pool_holds_a_price_and_nothing_else() {
        let sc = start();
        {
            let p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            assert!(pool::sqrt_price(&p) == P0, 0);
            assert!(i32::eq(pool::current_tick(&p), i32::zero()), 1);
            // No deposit at creation -- a concentrated pool starts empty.
            assert!(pool::liquidity(&p) == 0, 2);
            let (ra, rb) = pool::reserves(&p);
            assert!(ra == 0 && rb == 0, 3);
            assert!(pool::fee_bps(&p) == FEE, 4);
            assert!(pool::tick_spacing(&p) == SPACING, 5);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() {
        let mut sc = ts::begin(ADMIN);
        {
            let ctx = sc.ctx();
            pool::create_pool<USDC, USDC>(P0, FEE, SPACING, ctx);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Positions                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_position_spanning_the_price_becomes_active_liquidity() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 1000000);

            assert!(pool::liquidity(&p) > 0, 0);
            // Both sides funded, because the price sits inside the range.
            let (ra, rb) = pool::reserves(&p);
            assert!(ra > 0 && rb > 0, 1);
            assert!(pool::position_liquidity(&p, ADMIN, neg(1000), pos(1000)) > 0, 2);

            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_position_entirely_above_the_price_is_not_active() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, pos(1000), pos(2000), 1000000);

            // Recorded, but contributing nothing until the price reaches it.
            assert!(pool::position_liquidity(&p, ADMIN, pos(1000), pos(2000)) > 0, 0);
            assert!(pool::liquidity(&p) == 0, 1);

            // Above the range the position is all token0, so only one reserve
            // was funded.
            let (ra, rb) = pool::reserves(&p);
            assert!(ra > 0, 2);
            assert!(rb == 0, 3);

            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_narrower_range_buys_more_liquidity_for_the_same_deposit() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(10000), pos(10000), 1000000);
            let wide = pool::liquidity(&p);

            provide(&mut sc, &mut p, neg(100), pos(100), 1000000);
            let narrow = pool::liquidity(&p) - wide;

            // The point of the venue.
            assert!(narrow > wide * 10, 0);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::pool::EInvalidRange)]
    fun a_range_misaligned_to_the_spacing_is_rejected() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            // 105 is not a multiple of 10, so it would share a bitmap bit.
            provide(&mut sc, &mut p, neg(100), pos(105), 1000000);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::pool::EInvalidRange)]
    fun an_inverted_range_is_rejected() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, pos(1000), neg(1000), 1000000);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun removing_liquidity_credits_the_position_and_collect_pays_it_out() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 1000000);
            let liq = pool::position_liquidity(&p, ADMIN, neg(1000), pos(1000));

            let ctx = sc.ctx();
            pool::remove_liquidity(&mut p, neg(1000), pos(1000), liq, ctx);

            // Liquidity is gone from the pool immediately...
            assert!(pool::liquidity(&p) == 0, 0);
            assert!(pool::position_liquidity(&p, ADMIN, neg(1000), pos(1000)) == 0, 1);
            // ...but the tokens are owed, not yet paid.
            let (owed_0, owed_1) = pool::position_owed(&p, ADMIN, neg(1000), pos(1000));
            assert!(owed_0 > 0 && owed_1 > 0, 2);

            let ctx2 = sc.ctx();
            let (ca, cb) = pool::collect(&mut p, neg(1000), pos(1000), ctx2);
            assert!(coin::value(&ca) == owed_0, 3);
            assert!(coin::value(&cb) == owed_1, 4);

            coin::burn_for_testing(ca);
            coin::burn_for_testing(cb);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun withdrawing_returns_no_more_than_was_deposited() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 1000000);
            let (in_0, in_1) = pool::reserves(&p);
            let liq = pool::position_liquidity(&p, ADMIN, neg(1000), pos(1000));

            let ctx = sc.ctx();
            pool::remove_liquidity(&mut p, neg(1000), pos(1000), liq, ctx);
            let (owed_0, owed_1) = pool::position_owed(&p, ADMIN, neg(1000), pos(1000));

            // Minting rounds up and burning rounds down, so the pool keeps the
            // difference. It must never pay out more than it took in.
            assert!(owed_0 <= in_0, 0);
            assert!(owed_1 <= in_1, 1);
            ts::return_shared(p);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Swapping                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_inside_one_range_moves_the_price_down() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let before = pool::sqrt_price(&p);

            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(10000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::min_sqrt_price(), ctx,
            );

            assert!(coin::value(&out) > 0, 0);
            // Selling A pushes the price down.
            assert!(pool::sqrt_price(&p) < before, 1);
            // The trade fits inside one range, so nothing is left over.
            assert!(coin::value(&refund) == 0, 2);

            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun the_other_direction_moves_the_price_up() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let before = pool::sqrt_price(&p);

            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<WETH>(10000, ctx);
            let (out, refund) = pool::swap_b_for_a(
                &mut p, coin_in, 0, tick_math::max_sqrt_price(), ctx,
            );

            assert!(coin::value(&out) > 0, 0);
            assert!(pool::sqrt_price(&p) > before, 1);

            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_swap_charges_a_fee_that_shows_up_in_the_global_counter() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let (g0_before, _) = pool::fee_growth_global(&p);

            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::min_sqrt_price(), ctx,
            );

            let (g0_after, _) = pool::fee_growth_global(&p);
            // Fees on a sell of A accrue to the token0 counter.
            assert!(g0_after > g0_before, 0);

            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_price_limit_stops_the_swap_and_returns_the_rest() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(10000), pos(10000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);

            // Stop the price at tick -100 rather than letting it run.
            let limit = tick_math::sqrt_price_at_tick(neg(100));
            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000000, ctx);
            let (out, refund) = pool::swap_a_for_b(&mut p, coin_in, 0, limit, ctx);

            assert!(pool::sqrt_price(&p) == limit, 0);
            // The budget was far more than the limit allowed, so most of it
            // comes back rather than being consumed.
            assert!(coin::value(&refund) > 0, 1);
            assert!(coin::value(&out) > 0, 2);

            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_swap_crossing_a_boundary_picks_up_the_liquidity_change() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            // A wide range, plus a narrow one that ends at tick -100. Crossing
            // below -100 must drop the narrow range's liquidity.
            provide(&mut sc, &mut p, neg(10000), pos(10000), 1000000);
            provide(&mut sc, &mut p, neg(100), pos(100), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let before = pool::liquidity(&p);

            let ctx = sc.ctx();
            // The narrow range holds ~10M per side, so crossing its lower
            // bound costs more than that. The price limit caps how far this
            // actually goes; the rest comes back as change.
            let coin_in = coin::mint_for_testing<USDC>(100000000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::sqrt_price_at_tick(neg(500)), ctx,
            );

            // Past the narrow range's lower bound, so active liquidity fell.
            assert!(i32::lt(pool::current_tick(&p), neg(100)), 0);
            assert!(pool::liquidity(&p) < before, 1);
            assert!(pool::liquidity(&p) > 0, 2);

            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::pool::ESlippage)]
    fun a_swap_below_min_out_aborts() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(10000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 999999999, tick_math::min_sqrt_price(), ctx,
            );
            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::pool::EInvalidPriceLimit)]
    fun a_price_limit_on_the_wrong_side_is_rejected() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(10000, ctx);
            // Selling A moves the price down, so a limit above it is nonsense.
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::max_sqrt_price(), ctx,
            );
            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Fees reaching the position                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_provider_earns_fees_from_swaps_in_their_range() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::min_sqrt_price(), ctx,
            );
            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            // Collecting with no liquidity change still settles fees.
            let (ca, cb) = pool::collect(&mut p, neg(1000), pos(1000), ctx);
            // The swap sold A, so the fee is denominated in A.
            assert!(coin::value(&ca) > 0, 0);
            coin::burn_for_testing(ca);
            coin::burn_for_testing(cb);
            ts::return_shared(p);
        };
        sc.end();
    }

    #[test]
    fun a_position_outside_the_traded_range_earns_nothing() {
        let mut sc = start();
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            provide(&mut sc, &mut p, neg(1000), pos(1000), 10000000);
            // A second position well above the price, never traded through.
            provide(&mut sc, &mut p, pos(5000), pos(6000), 1000000);
            ts::return_shared(p);
        };
        sc.next_tx(TRADER);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            let coin_in = coin::mint_for_testing<USDC>(100000, ctx);
            let (out, refund) = pool::swap_a_for_b(
                &mut p, coin_in, 0, tick_math::min_sqrt_price(), ctx,
            );
            coin::burn_for_testing(out);
            coin::burn_for_testing(refund);
            ts::return_shared(p);
        };
        sc.next_tx(ADMIN);
        {
            let mut p = ts::take_shared<Pool<USDC, WETH>>(&sc);
            let ctx = sc.ctx();
            let (ca, cb) = pool::collect(&mut p, pos(5000), pos(6000), ctx);
            // The price never entered this range, so it earned nothing.
            assert!(coin::value(&ca) == 0, 0);
            assert!(coin::value(&cb) == 0, 1);
            coin::burn_for_testing(ca);
            coin::burn_for_testing(cb);
            ts::return_shared(p);
        };
        sc.end();
    }
}
