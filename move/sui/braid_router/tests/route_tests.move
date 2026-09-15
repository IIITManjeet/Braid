#[test_only]
module braid_router::route_tests {
    use sui::coin;
    use sui::test_scenario as ts;

    use braid_cpmm::pool::{Self as cpmm, Pool as CpmmPool};
    use braid_stable::pool::{Self as stable, StablePool};
    use braid_clmm::pool::{Self as clmm, Pool as ClmmPool};
    use braid_clmm::tick_math;
    use braid_clob::market::{Self as clob, Market};
    use braid_router::route;
    use braid_router::test_world::{world, buy_eth, USD, ETH};

    // ---------------------------------------------------------------- //
    // Each leg is exactly its venue                                    //
    // ---------------------------------------------------------------- //

    #[test]
    fun each_leg_pays_exactly_what_its_venue_quotes() {
        let mut sc = world(0);
        let mut cp = sc.take_shared<CpmmPool<USD, ETH>>();
        let mut sp = sc.take_shared<StablePool<USD, ETH>>();
        let mut cl = sc.take_shared<ClmmPool<USD, ETH>>();
        let mut mk = sc.take_shared<Market<ETH, USD>>();

        // Venues are independent objects, so quoting all of them up front is
        // exactly what executing them in sequence will produce.
        let q_cpmm = cpmm::quote_a_for_b(&cp, 300_000);
        let q_stable = stable::quote_a_for_b(&sp, 1_000_000);
        let (q_clob, q_clob_used) = clob::quote_quote_for_base(&mk, 2_500_000);

        let coin_in = coin::mint_for_testing<USD>(5_000_000, sc.ctx());
        let mut r = route::begin<USD, ETH>(coin_in, 0);

        route::cpmm_a_to_b(&mut r, &mut cp, 300_000, sc.ctx());
        assert!(route::output_so_far(&r) == q_cpmm, 0);

        route::stable_a_to_b(&mut r, &mut sp, 1_000_000, sc.ctx());
        assert!(route::output_so_far(&r) == q_cpmm + q_stable, 1);

        let before = route::output_so_far(&r);
        route::clmm_a_to_b(&mut r, &mut cl, 1_000_000, sc.ctx());
        let clmm_out = route::output_so_far(&r) - before;
        assert!(clmm_out > 0, 2);

        route::clob_quote_to_base(&mut r, &mut mk, 2_500_000, sc.ctx());
        assert!(route::output_so_far(&r) == q_cpmm + q_stable + clmm_out + q_clob, 3);

        // The book spends only whole lots; the rest is back in the route.
        let clob_unspent = 2_500_000 - q_clob_used;
        assert!(route::remaining_input(&r) == 200_000 + clob_unspent, 4);
        assert!(route::legs(&r) == 4, 5);

        let (out, unspent) = route::finish(r, sc.ctx());
        assert!(out.value() == q_cpmm + q_stable + clmm_out + q_clob, 6);
        assert!(unspent.value() == 200_000 + clob_unspent, 7);

        coin::burn_for_testing(out);
        coin::burn_for_testing(unspent);
        ts::return_shared(cp);
        ts::return_shared(sp);
        ts::return_shared(cl);
        ts::return_shared(mk);
        sc.end();
    }

    #[test]
    fun a_clmm_leg_matches_a_direct_swap_on_an_identical_pool() {
        let (routed, unspent) = buy_eth(10, 1_000_000, vector[0, 0, 1_000_000, 0], 0);
        assert!(unspent == 0, 0);

        let mut sc = world(0);
        let mut cl = sc.take_shared<ClmmPool<USD, ETH>>();
        let coin_in = coin::mint_for_testing<USD>(1_000_000, sc.ctx());
        let (out, change) =
            clmm::swap_a_for_b(&mut cl, coin_in, 0, tick_math::min_sqrt_price(), sc.ctx());
        assert!(out.value() == routed, 1);
        assert!(change.value() == 0, 2);
        coin::burn_for_testing(out);
        coin::burn_for_testing(change);
        ts::return_shared(cl);
        sc.end();
    }

    #[test]
    fun the_reverse_direction_routes_through_every_venue_too() {
        let mut sc = world(0);
        let mut cp = sc.take_shared<CpmmPool<USD, ETH>>();
        let mut sp = sc.take_shared<StablePool<USD, ETH>>();
        let mut cl = sc.take_shared<ClmmPool<USD, ETH>>();
        let mut mk = sc.take_shared<Market<ETH, USD>>();

        let q_cpmm = cpmm::quote_b_for_a(&cp, 200_000);
        let q_stable = stable::quote_b_for_a(&sp, 700_000);
        let (q_clob, q_clob_used) = clob::quote_base_for_quote(&mk, 1_234_567);

        let coin_in = coin::mint_for_testing<ETH>(3_000_000, sc.ctx());
        let mut r = route::begin<ETH, USD>(coin_in, 0);
        route::cpmm_b_to_a(&mut r, &mut cp, 200_000, sc.ctx());
        route::stable_b_to_a(&mut r, &mut sp, 700_000, sc.ctx());
        let before = route::output_so_far(&r);
        route::clmm_b_to_a(&mut r, &mut cl, 800_000, sc.ctx());
        let clmm_out = route::output_so_far(&r) - before;
        route::clob_base_to_quote(&mut r, &mut mk, 1_234_567, sc.ctx());

        let (out, unspent) = route::finish(r, sc.ctx());
        assert!(clmm_out > 0, 0);
        assert!(out.value() == q_cpmm + q_stable + clmm_out + q_clob, 1);
        // 65,433 never left the route, and 4,567 came back from the book
        // because it is less than a lot.
        assert!(q_clob_used == 1_230_000, 2);
        assert!(unspent.value() == 3_000_000 - 200_000 - 700_000 - 800_000 - q_clob_used, 3);

        coin::burn_for_testing(out);
        coin::burn_for_testing(unspent);
        ts::return_shared(cp);
        ts::return_shared(sp);
        ts::return_shared(cl);
        ts::return_shared(mk);
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Why route at all                                                 //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_split_beats_sending_everything_to_any_one_venue() {
        let total = 8_000_000;
        let (all_cpmm, _) = buy_eth(0, total, vector[total, 0, 0, 0], 0);
        let (all_stable, _) = buy_eth(10, total, vector[0, total, 0, 0], 0);
        let (all_clmm, _) = buy_eth(20, total, vector[0, 0, total, 0], 0);
        // The book cannot absorb this at all: 6,000,000 of depth, and the
        // rest of the input comes back unspent.
        let (all_clob, clob_unspent) = buy_eth(30, total, vector[0, 0, 0, total], 0);
        assert!(clob_unspent > 1_000_000, 0);

        // A split by hand, not by the optimizer. It only has to be good enough
        // to beat every single venue while spending essentially all its input.
        let (split, split_unspent) =
            buy_eth(40, total, vector[50_000, 3_900_000, 600_000, 3_450_000], 0);
        assert!(split_unspent < 10_010, 1);   // under one lot, at the book

        assert!(split > all_cpmm, 2);
        assert!(split > all_stable, 3);
        assert!(split > all_clmm, 4);
        assert!(split > all_clob, 5);
    }

    // ---------------------------------------------------------------- //
    // The bound, and the plumbing                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_route_that_clears_its_minimum_exactly_finishes() {
        let (out, _) = buy_eth(0, 1_000_000, vector[0, 1_000_000, 0, 0], 0);
        let (again, _) = buy_eth(10, 1_000_000, vector[0, 1_000_000, 0, 0], out);
        assert!(again == out, 0);
    }

    #[test]
    #[expected_failure(abort_code = braid_router::route::ESlippage)]
    fun a_route_one_unit_short_of_its_minimum_aborts() {
        let (out, _) = buy_eth(0, 1_000_000, vector[0, 1_000_000, 0, 0], 0);
        buy_eth(10, 1_000_000, vector[0, 1_000_000, 0, 0], out + 1);
    }

    #[test]
    #[expected_failure(abort_code = braid_router::route::EInsufficientInput)]
    fun legs_cannot_spend_more_than_the_route_holds() {
        buy_eth(0, 1_000_000, vector[600_000, 600_000, 0, 0], 0);
    }

    #[test]
    fun empty_legs_are_skipped_and_everything_comes_back() {
        let mut sc = world(0);
        let mut cp = sc.take_shared<CpmmPool<USD, ETH>>();
        let coin_in = coin::mint_for_testing<USD>(777, sc.ctx());
        let mut r = route::begin<USD, ETH>(coin_in, 0);
        route::cpmm_a_to_b(&mut r, &mut cp, 0, sc.ctx());
        assert!(route::legs(&r) == 0, 0);
        let (out, unspent) = route::finish(r, sc.ctx());
        assert!(out.value() == 0 && unspent.value() == 777, 1);
        coin::burn_for_testing(out);
        coin::burn_for_testing(unspent);
        ts::return_shared(cp);
        sc.end();
    }

    #[test]
    fun a_leg_past_the_books_depth_returns_what_it_could_not_spend() {
        // The asks hold 6,000,000 ETH for 6,003,200 USD.
        let (out, unspent) = buy_eth(0, 10_000_000, vector[0, 0, 0, 10_000_000], 0);
        assert!(out == 6_000_000 - 6_000, 0);
        assert!(unspent == 10_000_000 - 6_003_200, 1);
    }
}
