#[test_only]
module braid_router::route_tests {
    use aptos_framework::coin;

    use braid_cpmm::pool as cpmm;
    use braid_stable::pool as stable;
    use braid_clmm::pool as clmm;
    use braid_clmm::tick_math;
    use braid_clob::market as clob;
    use braid_router::route;
    use braid_router::test_world::{
        Self, world, buy_eth, trader, mint_usd, mint_eth, burn_usd, burn_eth, USD, ETH,
    };

    // ---------------------------------------------------------------- //
    // Each leg is exactly its venue                                    //
    // ---------------------------------------------------------------- //

    #[test]
    fun each_leg_pays_exactly_what_its_venue_quotes() {
        let w = world();
        let (cp, sp, cl, mk) = (
            test_world::cpmm_pool(&w), test_world::stable_pool(&w),
            test_world::clmm_pool(&w), test_world::market(&w),
        );

        // Venues are independent objects, so quoting all of them up front is
        // exactly what executing them in sequence will produce.
        let q_cpmm = cpmm::quote_a_for_b<USD, ETH>(cp, 300_000);
        let q_stable = stable::quote_a_for_b<USD, ETH>(sp, 1_000_000);
        let (q_clob, q_clob_used) = clob::quote_quote_for_base<ETH, USD>(mk, 2_500_000);

        let r = route::begin<USD, ETH>(mint_usd(5_000_000), 0);

        route::cpmm_a_to_b(&mut r, cp, 300_000);
        assert!(route::output_so_far(&r) == q_cpmm, 0);

        route::stable_a_to_b(&mut r, sp, 1_000_000);
        assert!(route::output_so_far(&r) == q_cpmm + q_stable, 1);

        let before = route::output_so_far(&r);
        route::clmm_a_to_b(&mut r, cl, 1_000_000);
        let clmm_out = route::output_so_far(&r) - before;
        assert!(clmm_out > 0, 2);

        route::clob_quote_to_base<ETH, USD>(&mut r, &trader(), mk, 2_500_000);
        assert!(route::output_so_far(&r) == q_cpmm + q_stable + clmm_out + q_clob, 3);

        // The book spends only whole lots; the rest is back in the route.
        let clob_unspent = 2_500_000 - q_clob_used;
        assert!(route::remaining_input(&r) == 200_000 + clob_unspent, 4);
        assert!(route::legs(&r) == 4, 5);

        let (out, unspent) = route::finish(r);
        assert!(coin::value(&out) == q_cpmm + q_stable + clmm_out + q_clob, 6);
        assert!(coin::value(&unspent) == 200_000 + clob_unspent, 7);

        burn_eth(out);
        burn_usd(unspent);
    }

    #[test]
    fun a_clmm_leg_matches_a_direct_swap_on_an_identical_pool() {
        let (routed, unspent) = buy_eth(10, 1_000_000, vector[0, 0, 1_000_000, 0], 0);
        assert!(unspent == 0, 0);

        let w = world();
        let (out, change) = clmm::swap_a_for_b<USD, ETH>(
            test_world::clmm_pool(&w), mint_usd(1_000_000), 0, tick_math::min_sqrt_price(),
        );
        assert!(coin::value(&out) == routed, 1);
        assert!(coin::value(&change) == 0, 2);
        burn_eth(out);
        burn_usd(change);
    }

    #[test]
    fun the_reverse_direction_routes_through_every_venue_too() {
        let w = world();
        let (cp, sp, cl, mk) = (
            test_world::cpmm_pool(&w), test_world::stable_pool(&w),
            test_world::clmm_pool(&w), test_world::market(&w),
        );

        let q_cpmm = cpmm::quote_b_for_a<USD, ETH>(cp, 200_000);
        let q_stable = stable::quote_b_for_a<USD, ETH>(sp, 700_000);
        let (q_clob, q_clob_used) = clob::quote_base_for_quote<ETH, USD>(mk, 1_234_567);

        let r = route::begin<ETH, USD>(mint_eth(3_000_000), 0);
        route::cpmm_b_to_a<USD, ETH>(&mut r, cp, 200_000);
        route::stable_b_to_a<USD, ETH>(&mut r, sp, 700_000);
        let before = route::output_so_far(&r);
        route::clmm_b_to_a<USD, ETH>(&mut r, cl, 800_000);
        let clmm_out = route::output_so_far(&r) - before;
        route::clob_base_to_quote<ETH, USD>(&mut r, &trader(), mk, 1_234_567);

        let (out, unspent) = route::finish(r);
        assert!(clmm_out > 0, 0);
        assert!(coin::value(&out) == q_cpmm + q_stable + clmm_out + q_clob, 1);
        // 65,433 never left the route, and 4,567 came back from the book
        // because it is less than a lot.
        assert!(q_clob_used == 1_230_000, 2);
        assert!(coin::value(&unspent) == 3_000_000 - 200_000 - 700_000 - 800_000 - q_clob_used, 3);

        burn_usd(out);
        burn_eth(unspent);
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
    #[expected_failure(abort_code = route::ESlippage)]
    fun a_route_one_unit_short_of_its_minimum_aborts() {
        let (out, _) = buy_eth(0, 1_000_000, vector[0, 1_000_000, 0, 0], 0);
        buy_eth(10, 1_000_000, vector[0, 1_000_000, 0, 0], out + 1);
    }

    #[test]
    #[expected_failure(abort_code = route::EInsufficientInput)]
    fun legs_cannot_spend_more_than_the_route_holds() {
        buy_eth(0, 1_000_000, vector[600_000, 600_000, 0, 0], 0);
    }

    #[test]
    fun empty_legs_are_skipped_and_everything_comes_back() {
        let w = world();
        let r = route::begin<USD, ETH>(mint_usd(777), 0);
        route::cpmm_a_to_b(&mut r, test_world::cpmm_pool(&w), 0);
        assert!(route::legs(&r) == 0, 0);
        let (out, unspent) = route::finish(r);
        assert!(coin::value(&out) == 0 && coin::value(&unspent) == 777, 1);
        burn_eth(out);
        burn_usd(unspent);
    }

    #[test]
    fun a_leg_past_the_books_depth_returns_what_it_could_not_spend() {
        // The asks hold 6,000,000 ETH for 6,003,200 USD.
        let (out, unspent) = buy_eth(0, 10_000_000, vector[0, 0, 0, 10_000_000], 0);
        assert!(out == 6_000_000 - 6_000, 0);
        assert!(unspent == 10_000_000 - 6_003_200, 1);
    }

    // ---------------------------------------------------------------- //
    // Venues by address                                                //
    // ---------------------------------------------------------------- //
    //
    // On Sui a leg's venue is a `&mut Pool<A, B>` the runtime resolved before
    // any code ran. Here it is an address, so these two have no Sui twin.

    #[test]
    fun an_empty_leg_never_looks_at_its_address() {
        world();
        let r = route::begin<USD, ETH>(mint_usd(1_000), 0);
        route::cpmm_a_to_b(&mut r, @0xDEAD, 0);
        route::stable_a_to_b(&mut r, @0xDEAD, 0);
        route::clmm_a_to_b(&mut r, @0xDEAD, 0);
        route::clob_quote_to_base<ETH, USD>(&mut r, &trader(), @0xDEAD, 0);
        let (out, unspent) = route::finish(r);
        assert!(coin::value(&out) == 0 && coin::value(&unspent) == 1_000, 0);
        burn_eth(out);
        burn_usd(unspent);
    }

    #[test]
    #[expected_failure(abort_code = cpmm::ENoSuchPool)]
    fun a_leg_pointed_at_the_wrong_venue_aborts() {
        // The stable pool's address, handed to the constant-product leg.
        let w = world();
        let r = route::begin<USD, ETH>(mint_usd(1_000), 0);
        route::cpmm_a_to_b(&mut r, test_world::stable_pool(&w), 1_000);
        let (out, unspent) = route::finish(r);
        burn_eth(out);
        burn_usd(unspent);
    }
}
