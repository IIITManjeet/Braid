#[test_only]
/// APTOS PORT of `move/sui/braid_stable/tests/pool_tests.move`.
///
/// Same assertions and the same hand-computed numbers -- 999,590 out for
/// 1,000,000 in is the figure the live Sui testnet swap returned, so it is also
/// the number the Aptos pool has to produce. See the note at the top of
/// `braid_cpmm::pool_tests` for why the scaffolding differs.
module braid_stable::pool_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::primary_fungible_store;

    use braid_stable::pool;
    use braid_stable::stable_math;

    /// A pegged pair.
    struct USDC {}
    struct USDT {}

    struct Caps has key {
        usdc_mint: MintCapability<USDC>,
        usdc_burn: BurnCapability<USDC>,
        usdt_mint: MintCapability<USDT>,
        usdt_burn: BurnCapability<USDT>,
    }

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    const R: u64 = 1000000000;
    const AMP: u64 = 10000; // A = 100
    const FEE: u64 = 4;     // 4 bps

    const ONE_Q64: u128 = 18446744073709551616;

    // ---------------------------------------------------------------- //
    // Helpers                                                          //
    // ---------------------------------------------------------------- //

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_stable);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(TRADER);

        let (usdc_burn, usdc_freeze, usdc_mint) = coin::initialize<USDC>(
            &braid, std::string::utf8(b"USDC"), std::string::utf8(b"USDC"), 6, true,
        );
        let (usdt_burn, usdt_freeze, usdt_mint) = coin::initialize<USDT>(
            &braid, std::string::utf8(b"USDT"), std::string::utf8(b"USDT"), 6, true,
        );
        coin::destroy_freeze_cap(usdc_freeze);
        coin::destroy_freeze_cap(usdt_freeze);

        move_to(&braid, Caps { usdc_mint, usdc_burn, usdt_mint, usdt_burn });
    }

    fun mint_usdc(amount: u64): Coin<USDC> acquires Caps {
        coin::mint<USDC>(amount, &borrow_global<Caps>(@braid_stable).usdc_mint)
    }

    fun mint_usdt(amount: u64): Coin<USDT> acquires Caps {
        coin::mint<USDT>(amount, &borrow_global<Caps>(@braid_stable).usdt_mint)
    }

    fun burn_usdc(c: Coin<USDC>) acquires Caps {
        coin::burn<USDC>(c, &borrow_global<Caps>(@braid_stable).usdc_burn)
    }

    fun burn_usdt(c: Coin<USDT>) acquires Caps {
        coin::burn<USDT>(c, &borrow_global<Caps>(@braid_stable).usdt_burn)
    }

    fun seed_pool(a: u64, b: u64, amp: u64, fee_bps: u64): address acquires Caps {
        let coin_a = mint_usdc(a);
        let coin_b = mint_usdt(b);
        let (pool_addr, lp) = pool::create_pool<USDC, USDT>(coin_a, coin_b, amp, fee_bps);
        primary_fungible_store::deposit(ADMIN, lp);
        pool_addr
    }

    fun admin_lp_balance(pool_addr: address): u64 {
        primary_fungible_store::balance(ADMIN, pool::lp_metadata<USDC, USDT>(pool_addr))
    }

    fun take_admin_lp(pool_addr: address): FungibleAsset {
        let metadata = pool::lp_metadata<USDC, USDT>(pool_addr);
        let amount = primary_fungible_store::balance(ADMIN, metadata);
        primary_fungible_store::withdraw(
            &account::create_signer_for_test(ADMIN), metadata, amount,
        )
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_fresh_pool_has_shares_worth_exactly_one() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let (reserve_a, reserve_b) = pool::reserves<USDC, USDT>(p);
        assert!(reserve_a == R && reserve_b == R, 0);
        assert!(pool::amp<USDC, USDT>(p) == AMP, 1);
        assert!(pool::fee_bps<USDC, USDT>(p) == FEE, 2);

        // Shares are denominated in D, and D == the sum at balance.
        assert!(pool::invariant_d<USDC, USDT>(p) == 2000000000, 3);
        assert!(pool::lp_supply_value<USDC, USDT>(p) == 2000000000, 4);
        assert!(pool::virtual_price<USDC, USDT>(p) == ONE_Q64, 5);

        assert!(admin_lp_balance(p) == 2000000000 - stable_math::minimum_liquidity(), 6);
    }

    #[test]
    #[expected_failure(abort_code = pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() acquires Caps {
        setup();
        let (_p, lp) = pool::create_pool<USDC, USDC>(mint_usdc(R), mint_usdc(R), AMP, FEE);
        primary_fungible_store::deposit(ADMIN, lp);
    }

    #[test]
    #[expected_failure(abort_code = stable_math::EInvalidAmp)]
    fun an_out_of_range_amplification_is_rejected() acquires Caps {
        setup();
        seed_pool(R, R, stable_math::max_amp() + 1, FEE);
    }

    #[test]
    #[expected_failure(abort_code = pool::EInvalidFee)]
    fun a_fee_above_the_cap_is_rejected() acquires Caps {
        setup();
        seed_pool(R, R, AMP, stable_math::max_fee_bps() + 1);
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_pays_exactly_what_the_quote_promised() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let quoted = pool::quote_a_for_b<USDC, USDT>(p, 1000000);
        let d_before = pool::invariant_d<USDC, USDT>(p);

        let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(1000000), 0);

        assert!(coin::value(&out) == quoted, 0);
        assert!(quoted == 999590, 1);
        // 0.1% of the pool traded for a total cost of ~4bps -- the fee.
        assert!(1000000 - quoted == 410, 2);

        let (reserve_a, reserve_b) = pool::reserves<USDC, USDT>(p);
        assert!(reserve_a == R + 1000000, 3);
        assert!(reserve_b == R - quoted, 4);
        assert!(pool::invariant_d<USDC, USDT>(p) > d_before, 5);

        burn_usdt(out);
    }

    #[test]
    fun the_pool_stays_flat_under_a_large_trade() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        // 10% of the pool in one trade.
        let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(100000000), 0);
        assert!(coin::value(&out) == 99860149, 0);
        // Under 15bps all-in, on a trade that would cost >900bps on a
        // constant-product pool of the same depth.
        assert!((100000000 - coin::value(&out)) * 10000 / 100000000 <= 15, 1);

        burn_usdt(out);
    }

    #[test]
    #[expected_failure(abort_code = pool::ESlippage)]
    fun a_swap_below_min_out_aborts() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);
        let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(1000000), 999591);
        burn_usdt(out);
    }

    #[test]
    fun a_round_trip_loses_only_the_two_fees() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let mid = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(10000000), 0);
        let back = pool::swap_b_for_a<USDC, USDT>(p, mid, 0);

        let returned = coin::value(&back);
        assert!(returned < 10000000, 0);
        // Two 4bps fees plus a little curvature: well under 20bps total.
        assert!((10000000 - returned) * 10000 / 10000000 <= 20, 1);

        burn_usdc(back);
    }

    #[test]
    fun swapping_the_pool_far_off_peg_still_holds_the_invariant() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        // Five large same-direction trades, driving the pool badly off balance.
        let n = 0;
        while (n < 5) {
            let d_before = pool::invariant_d<USDC, USDT>(p);
            let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(150000000), 0);
            assert!(pool::invariant_d<USDC, USDT>(p) >= d_before, 0);
            burn_usdt(out);
            n = n + 1;
        };

        let (reserve_a, reserve_b) = pool::reserves<USDC, USDT>(p);
        // Deeply skewed -- and still solvent and still quoting.
        assert!(reserve_a > reserve_b * 2, 1);
        assert!(pool::quote_a_for_b<USDC, USDT>(p, 1000000) > 0, 2);
        // Pushing further into the shallow side now costs real money,
        // which is exactly the constant-product floor doing its job.
        assert!(pool::quote_a_for_b<USDC, USDT>(p, 1000000) < 999590, 3);
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_balanced_deposit_mints_proportionally_and_free() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let lp = pool::add_liquidity<USDC, USDT>(p, mint_usdc(1000000), mint_usdt(1000000), 0);

        assert!(fungible_asset::amount(&lp) == 2000000, 0);
        let (reserve_a, reserve_b) = pool::reserves<USDC, USDT>(p);
        assert!(reserve_a == R + 1000000 && reserve_b == R + 1000000, 1);

        primary_fungible_store::deposit(TRADER, lp);
    }

    #[test]
    fun a_one_sided_deposit_pays_the_imbalance_fee() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        // Same total value as the balanced deposit above, all on one side.
        let lp = pool::add_liquidity<USDC, USDT>(p, mint_usdc(2000000), mint_usdt(0), 0);

        assert!(fungible_asset::amount(&lp) == 1999589, 0);
        // Strictly worse than depositing on ratio. A free one-sided deposit
        // would be a swap that paid no swap fee.
        assert!(fungible_asset::amount(&lp) < 2000000, 1);

        primary_fungible_store::deposit(TRADER, lp);
    }

    #[test]
    fun removing_liquidity_returns_the_proportional_share() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let lp = take_admin_lp(p);
        let slice = fungible_asset::extract(&mut lp, 2000000);
        let (out_a, out_b) = pool::remove_liquidity<USDC, USDT>(p, slice, 0, 0);

        // 2e6 of a 2e9 supply, against 1e9 on each side.
        assert!(coin::value(&out_a) == 1000000, 0);
        assert!(coin::value(&out_b) == 1000000, 1);

        burn_usdc(out_a);
        burn_usdt(out_b);
        primary_fungible_store::deposit(ADMIN, lp);
    }

    #[test]
    fun the_locked_floor_survives_every_holder_exiting() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let lp = take_admin_lp(p);
        let (out_a, out_b) = pool::remove_liquidity<USDC, USDT>(p, lp, 0, 0);

        let min = stable_math::minimum_liquidity();
        assert!(pool::lp_supply_value<USDC, USDT>(p) == min, 0);
        let (reserve_a, reserve_b) = pool::reserves<USDC, USDT>(p);
        assert!(reserve_a > 0 && reserve_b > 0, 1);

        burn_usdc(out_a);
        burn_usdt(out_b);
    }

    #[test]
    fun the_share_price_only_ever_rises() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);
        assert!(pool::virtual_price<USDC, USDT>(p) == ONE_Q64, 0);

        let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(10000000), 0);

        // The fee stayed in the pool and no shares were minted for it.
        assert!(pool::virtual_price<USDC, USDT>(p) > ONE_Q64, 1);

        burn_usdt(out);
    }

    #[test]
    fun swap_fees_accrue_to_liquidity_providers() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let mid = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(100000000), 0);
        let back = pool::swap_b_for_a<USDC, USDT>(p, mid, 0);
        burn_usdc(back);

        let lp = take_admin_lp(p);
        let shares = fungible_asset::amount(&lp);
        let (out_a, out_b) = pool::remove_liquidity<USDC, USDT>(p, lp, 0, 0);

        // The creator deposited `shares / 2` of each side (shares are
        // denominated in D, which is the sum). A round trip left more.
        assert!(coin::value(&out_a) + coin::value(&out_b) > shares, 0);

        burn_usdc(out_a);
        burn_usdt(out_b);
    }

    // ---------------------------------------------------------------- //
    // Exact-out                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_exact_out_quote_is_what_the_swap_actually_costs() acquires Caps {
        setup();
        let p = seed_pool(R, R, AMP, FEE);

        let needed = pool::quote_in_for_b<USDC, USDT>(p, 999590);
        assert!(needed == 1000001, 0);

        let out = pool::swap_a_for_b<USDC, USDT>(p, mint_usdc(needed), 999590);
        assert!(coin::value(&out) >= 999590, 1);

        burn_usdt(out);
    }
}
