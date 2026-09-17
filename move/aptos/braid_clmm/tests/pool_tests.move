#[test_only]
/// APTOS PORT of `move/sui/braid_clmm/tests/pool_tests.move`.
///
/// Same 18 tests, same assertions. The scaffolding collapses: Sui's
/// `test_scenario` needs a `next_tx` to hand the shared pool to a second
/// address, whereas here every actor is just a signer and the pool is an
/// address, so a test that spanned three transactions on Sui is a straight line
/// of calls. See the note at the top of `braid_cpmm::pool_tests`.
module braid_clmm::pool_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};

    use braid_clmm::i32::{Self, I32};
    use braid_clmm::pool;
    use braid_clmm::tick_math;

    struct USDC {}
    struct WETH {}

    struct Caps has key {
        usdc_mint: MintCapability<USDC>,
        usdc_burn: BurnCapability<USDC>,
        weth_mint: MintCapability<WETH>,
        weth_burn: BurnCapability<WETH>,
    }

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    /// sqrt_price(0) = 1.0 in Q64.64.
    const P0: u128 = 18446744073709551616;
    const FEE: u64 = 30;
    const SPACING: u32 = 10;

    fun pos(v: u32): I32 { i32::from_u32(v) }
    fun neg(v: u32): I32 { i32::neg_from(v) }

    fun admin(): signer { account::create_signer_for_test(ADMIN) }

    // ---------------------------------------------------------------- //
    // Helpers                                                          //
    // ---------------------------------------------------------------- //

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_clmm);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(TRADER);

        let (usdc_burn, usdc_freeze, usdc_mint) = coin::initialize<USDC>(
            &braid, std::string::utf8(b"USDC"), std::string::utf8(b"USDC"), 6, true,
        );
        let (weth_burn, weth_freeze, weth_mint) = coin::initialize<WETH>(
            &braid, std::string::utf8(b"WETH"), std::string::utf8(b"WETH"), 8, true,
        );
        coin::destroy_freeze_cap(usdc_freeze);
        coin::destroy_freeze_cap(weth_freeze);

        move_to(&braid, Caps { usdc_mint, usdc_burn, weth_mint, weth_burn });
    }

    fun mint_usdc(amount: u64): Coin<USDC> acquires Caps {
        coin::mint<USDC>(amount, &borrow_global<Caps>(@braid_clmm).usdc_mint)
    }

    fun mint_weth(amount: u64): Coin<WETH> acquires Caps {
        coin::mint<WETH>(amount, &borrow_global<Caps>(@braid_clmm).weth_mint)
    }

    fun burn_usdc(c: Coin<USDC>) acquires Caps {
        coin::burn<USDC>(c, &borrow_global<Caps>(@braid_clmm).usdc_burn)
    }

    fun burn_weth(c: Coin<WETH>) acquires Caps {
        coin::burn<WETH>(c, &borrow_global<Caps>(@braid_clmm).weth_burn)
    }

    /// Create the pool and return its address.
    fun start(): address {
        setup();
        pool::create_pool<USDC, WETH>(P0, FEE, SPACING)
    }

    /// Open a position as ADMIN and burn the change.
    fun provide(p: address, lower: I32, upper: I32, amount: u64) acquires Caps {
        let a = mint_usdc(amount);
        let b = mint_weth(amount);
        let (ra, rb) = pool::add_liquidity<USDC, WETH>(&admin(), p, lower, upper, a, b);
        burn_usdc(ra);
        burn_weth(rb);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_new_pool_holds_a_price_and_nothing_else() {
        let p = start();
        assert!(pool::sqrt_price<USDC, WETH>(p) == P0, 0);
        assert!(i32::eq(pool::current_tick<USDC, WETH>(p), i32::zero()), 1);
        // No deposit at creation -- a concentrated pool starts empty.
        assert!(pool::liquidity<USDC, WETH>(p) == 0, 2);
        let (ra, rb) = pool::reserves<USDC, WETH>(p);
        assert!(ra == 0 && rb == 0, 3);
        assert!(pool::fee_bps<USDC, WETH>(p) == FEE, 4);
        assert!(pool::tick_spacing<USDC, WETH>(p) == SPACING, 5);
    }

    #[test]
    #[expected_failure(abort_code = pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() {
        setup();
        pool::create_pool<USDC, USDC>(P0, FEE, SPACING);
    }

    // ---------------------------------------------------------------- //
    // Positions                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_position_spanning_the_price_becomes_active_liquidity() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 1000000);

        assert!(pool::liquidity<USDC, WETH>(p) > 0, 0);
        // Both sides funded, because the price sits inside the range.
        let (ra, rb) = pool::reserves<USDC, WETH>(p);
        assert!(ra > 0 && rb > 0, 1);
        assert!(pool::position_liquidity<USDC, WETH>(p, ADMIN, neg(1000), pos(1000)) > 0, 2);
    }

    #[test]
    fun a_position_entirely_above_the_price_is_not_active() acquires Caps {
        let p = start();
        provide(p, pos(1000), pos(2000), 1000000);

        // Recorded, but contributing nothing until the price reaches it.
        assert!(pool::position_liquidity<USDC, WETH>(p, ADMIN, pos(1000), pos(2000)) > 0, 0);
        assert!(pool::liquidity<USDC, WETH>(p) == 0, 1);

        // Above the range the position is all token0, so only one reserve
        // was funded.
        let (ra, rb) = pool::reserves<USDC, WETH>(p);
        assert!(ra > 0, 2);
        assert!(rb == 0, 3);
    }

    #[test]
    fun a_narrower_range_buys_more_liquidity_for_the_same_deposit() acquires Caps {
        let p = start();
        provide(p, neg(10000), pos(10000), 1000000);
        let wide = pool::liquidity<USDC, WETH>(p);

        provide(p, neg(100), pos(100), 1000000);
        let narrow = pool::liquidity<USDC, WETH>(p) - wide;

        // The point of the venue.
        assert!(narrow > wide * 10, 0);
    }

    #[test]
    #[expected_failure(abort_code = pool::EInvalidRange)]
    fun a_range_misaligned_to_the_spacing_is_rejected() acquires Caps {
        let p = start();
        // 105 is not a multiple of 10, so it would share a bitmap bit.
        provide(p, neg(100), pos(105), 1000000);
    }

    #[test]
    #[expected_failure(abort_code = pool::EInvalidRange)]
    fun an_inverted_range_is_rejected() acquires Caps {
        let p = start();
        provide(p, pos(1000), neg(1000), 1000000);
    }

    #[test]
    fun removing_liquidity_credits_the_position_and_collect_pays_it_out() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 1000000);
        let liq = pool::position_liquidity<USDC, WETH>(p, ADMIN, neg(1000), pos(1000));

        pool::remove_liquidity<USDC, WETH>(&admin(), p, neg(1000), pos(1000), liq);

        // Liquidity is gone from the pool immediately...
        assert!(pool::liquidity<USDC, WETH>(p) == 0, 0);
        assert!(pool::position_liquidity<USDC, WETH>(p, ADMIN, neg(1000), pos(1000)) == 0, 1);
        // ...but the tokens are owed, not yet paid.
        let (owed_0, owed_1) = pool::position_owed<USDC, WETH>(p, ADMIN, neg(1000), pos(1000));
        assert!(owed_0 > 0 && owed_1 > 0, 2);

        let (ca, cb) = pool::collect<USDC, WETH>(&admin(), p, neg(1000), pos(1000));
        assert!(coin::value(&ca) == owed_0, 3);
        assert!(coin::value(&cb) == owed_1, 4);

        burn_usdc(ca);
        burn_weth(cb);
    }

    #[test]
    fun withdrawing_returns_no_more_than_was_deposited() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 1000000);
        let (in_0, in_1) = pool::reserves<USDC, WETH>(p);
        let liq = pool::position_liquidity<USDC, WETH>(p, ADMIN, neg(1000), pos(1000));

        pool::remove_liquidity<USDC, WETH>(&admin(), p, neg(1000), pos(1000), liq);
        let (owed_0, owed_1) = pool::position_owed<USDC, WETH>(p, ADMIN, neg(1000), pos(1000));

        // Minting rounds up and burning rounds down, so the pool keeps the
        // difference. It must never pay out more than it took in.
        assert!(owed_0 <= in_0, 0);
        assert!(owed_1 <= in_1, 1);
    }

    // ---------------------------------------------------------------- //
    // Swapping                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_inside_one_range_moves_the_price_down() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);

        let before = pool::sqrt_price<USDC, WETH>(p);
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(10000), 0, tick_math::min_sqrt_price(),
        );

        assert!(coin::value(&out) > 0, 0);
        // Selling A pushes the price down.
        assert!(pool::sqrt_price<USDC, WETH>(p) < before, 1);
        // The trade fits inside one range, so nothing is left over.
        assert!(coin::value(&refund) == 0, 2);

        burn_weth(out);
        burn_usdc(refund);
    }

    #[test]
    fun the_other_direction_moves_the_price_up() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);

        let before = pool::sqrt_price<USDC, WETH>(p);
        let (out, refund) = pool::swap_b_for_a<USDC, WETH>(
            p, mint_weth(10000), 0, tick_math::max_sqrt_price(),
        );

        assert!(coin::value(&out) > 0, 0);
        assert!(pool::sqrt_price<USDC, WETH>(p) > before, 1);

        burn_usdc(out);
        burn_weth(refund);
    }

    #[test]
    fun a_swap_charges_a_fee_that_shows_up_in_the_global_counter() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);

        let (g0_before, _) = pool::fee_growth_global<USDC, WETH>(p);
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(100000), 0, tick_math::min_sqrt_price(),
        );

        let (g0_after, _) = pool::fee_growth_global<USDC, WETH>(p);
        // Fees on a sell of A accrue to the token0 counter.
        assert!(g0_after > g0_before, 0);

        burn_weth(out);
        burn_usdc(refund);
    }

    #[test]
    fun a_price_limit_stops_the_swap_and_returns_the_rest() acquires Caps {
        let p = start();
        provide(p, neg(10000), pos(10000), 10000000);

        // Stop the price at tick -100 rather than letting it run.
        let limit = tick_math::sqrt_price_at_tick(neg(100));
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(100000000), 0, limit);

        assert!(pool::sqrt_price<USDC, WETH>(p) == limit, 0);
        // The budget was far more than the limit allowed, so most of it
        // comes back rather than being consumed.
        assert!(coin::value(&refund) > 0, 1);
        assert!(coin::value(&out) > 0, 2);

        burn_weth(out);
        burn_usdc(refund);
    }

    #[test]
    fun a_swap_crossing_a_boundary_picks_up_the_liquidity_change() acquires Caps {
        let p = start();
        // A wide range, plus a narrow one that ends at tick -100. Crossing
        // below -100 must drop the narrow range's liquidity.
        provide(p, neg(10000), pos(10000), 1000000);
        provide(p, neg(100), pos(100), 10000000);

        let before = pool::liquidity<USDC, WETH>(p);

        // The narrow range holds ~10M per side, so crossing its lower
        // bound costs more than that. The price limit caps how far this
        // actually goes; the rest comes back as change.
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(100000000), 0, tick_math::sqrt_price_at_tick(neg(500)),
        );

        // Past the narrow range's lower bound, so active liquidity fell.
        assert!(i32::lt(pool::current_tick<USDC, WETH>(p), neg(100)), 0);
        assert!(pool::liquidity<USDC, WETH>(p) < before, 1);
        assert!(pool::liquidity<USDC, WETH>(p) > 0, 2);

        burn_weth(out);
        burn_usdc(refund);
    }

    #[test]
    #[expected_failure(abort_code = pool::ESlippage)]
    fun a_swap_below_min_out_aborts() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(10000), 999999999, tick_math::min_sqrt_price(),
        );
        burn_weth(out);
        burn_usdc(refund);
    }

    #[test]
    #[expected_failure(abort_code = pool::EInvalidPriceLimit)]
    fun a_price_limit_on_the_wrong_side_is_rejected() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);
        // Selling A moves the price down, so a limit above it is nonsense.
        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(10000), 0, tick_math::max_sqrt_price(),
        );
        burn_weth(out);
        burn_usdc(refund);
    }

    // ---------------------------------------------------------------- //
    // Fees reaching the position                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_provider_earns_fees_from_swaps_in_their_range() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);

        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(100000), 0, tick_math::min_sqrt_price(),
        );
        burn_weth(out);
        burn_usdc(refund);

        // Collecting with no liquidity change still settles fees.
        let (ca, cb) = pool::collect<USDC, WETH>(&admin(), p, neg(1000), pos(1000));
        // The swap sold A, so the fee is denominated in A.
        assert!(coin::value(&ca) > 0, 0);
        burn_usdc(ca);
        burn_weth(cb);
    }

    #[test]
    fun a_position_outside_the_traded_range_earns_nothing() acquires Caps {
        let p = start();
        provide(p, neg(1000), pos(1000), 10000000);
        // A second position well above the price, never traded through.
        provide(p, pos(5000), pos(6000), 1000000);

        let (out, refund) = pool::swap_a_for_b<USDC, WETH>(
            p, mint_usdc(100000), 0, tick_math::min_sqrt_price(),
        );
        burn_weth(out);
        burn_usdc(refund);

        let (ca, cb) = pool::collect<USDC, WETH>(&admin(), p, pos(5000), pos(6000));
        // The price never entered this range, so it earned nothing.
        assert!(coin::value(&ca) == 0, 0);
        assert!(coin::value(&cb) == 0, 1);
        burn_usdc(ca);
        burn_weth(cb);
    }
}
