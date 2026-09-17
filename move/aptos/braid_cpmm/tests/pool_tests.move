#[test_only]
/// APTOS PORT of `move/sui/braid_cpmm/tests/pool_tests.move`.
///
/// Same assertions, same hand-computed numbers. What changes is the scaffolding:
/// Sui's `test_scenario` replays a sequence of transactions and hands back
/// objects by type, so a test *takes* the shared pool and returns it. Aptos unit
/// tests run in one transaction against global storage, so a test holds an
/// address and calls through it. There is no `next_tx`, and nothing to return.
module braid_cpmm::pool_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::primary_fungible_store;

    use braid_cpmm::pool;
    use braid_cpmm::cpmm_math;

    /// Two coin types that exist only to be distinct.
    ///
    /// Sui needs only `has drop`; a coin type there is a pure witness. Aptos
    /// registers them with `coin::initialize`, which insists the type be
    /// declared at the initializing signer's address -- so these must live in a
    /// module published under `@braid_cpmm`, which is why they are here and not
    /// in a shared fixture package.
    struct USDC {}
    struct WETH {}

    /// Mint and burn authority for the two test coins.
    ///
    /// Sui has `coin::mint_for_testing<T>`, which conjures a coin from nothing
    /// because there is no registry to satisfy. Aptos coins are registered
    /// types with a supply, so the test has to hold real capabilities.
    struct Caps has key {
        usdc_mint: MintCapability<USDC>,
        usdc_burn: BurnCapability<USDC>,
        weth_mint: MintCapability<WETH>,
        weth_burn: BurnCapability<WETH>,
    }

    const ADMIN: address = @0xA;
    const TRADER: address = @0xB;

    const R: u64 = 1000000;
    const FEE: u64 = 30;

    // ---------------------------------------------------------------- //
    // Helpers                                                          //
    // ---------------------------------------------------------------- //

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_cpmm);
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
        coin::mint<USDC>(amount, &borrow_global<Caps>(@braid_cpmm).usdc_mint)
    }

    fun mint_weth(amount: u64): Coin<WETH> acquires Caps {
        coin::mint<WETH>(amount, &borrow_global<Caps>(@braid_cpmm).weth_mint)
    }

    fun burn_usdc(c: Coin<USDC>) acquires Caps {
        coin::burn<USDC>(c, &borrow_global<Caps>(@braid_cpmm).usdc_burn)
    }

    fun burn_weth(c: Coin<WETH>) acquires Caps {
        coin::burn<WETH>(c, &borrow_global<Caps>(@braid_cpmm).weth_burn)
    }

    /// Seed a pool and park the creator's LP in ADMIN's primary store, which is
    /// what `transfer::public_transfer(lp, ADMIN)` does on the Sui side.
    fun seed_pool(amount_a: u64, amount_b: u64, fee_bps: u64): address acquires Caps {
        let coin_a = mint_usdc(amount_a);
        let coin_b = mint_weth(amount_b);
        let (pool_addr, lp) = pool::create_pool<USDC, WETH>(coin_a, coin_b, fee_bps);
        primary_fungible_store::deposit(ADMIN, lp);
        pool_addr
    }

    /// ADMIN's whole LP position, withdrawn as a spendable asset.
    fun take_admin_lp(pool_addr: address): FungibleAsset {
        let metadata = pool::lp_metadata<USDC, WETH>(pool_addr);
        let amount = primary_fungible_store::balance(ADMIN, metadata);
        primary_fungible_store::withdraw(
            &account::create_signer_for_test(ADMIN), metadata, amount,
        )
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun creating_a_pool_locks_the_floor_and_pays_out_the_rest() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == R && reserve_b == R, 0);
        assert!(pool::fee_bps<USDC, WETH>(p) == FEE, 1);
        // sqrt(R * R) = R shares in total, minted in full...
        assert!(pool::lp_supply_value<USDC, WETH>(p) == R, 2);

        // ...but the creator only receives what is left after the lock.
        let metadata = pool::lp_metadata<USDC, WETH>(p);
        assert!(
            primary_fungible_store::balance(ADMIN, metadata)
                == R - cpmm_math::minimum_liquidity(),
            3,
        );
        // And the floor itself sits at an address with no signer.
        assert!(
            primary_fungible_store::balance(p, metadata) == cpmm_math::minimum_liquidity(),
            4,
        );
    }

    #[test]
    #[expected_failure(abort_code = pool::ESameCoinType)]
    fun a_pool_of_one_coin_type_is_rejected() acquires Caps {
        setup();
        let coin_a = mint_usdc(R);
        let coin_b = mint_usdc(R);
        let (_p, lp) = pool::create_pool<USDC, USDC>(coin_a, coin_b, FEE);
        primary_fungible_store::deposit(ADMIN, lp);
    }

    #[test]
    #[expected_failure(abort_code = pool::EInvalidFee)]
    fun a_pool_above_the_fee_cap_is_rejected() acquires Caps {
        setup();
        seed_pool(R, R, cpmm_math::max_fee_bps() + 1);
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_swap_pays_exactly_what_the_quote_promised() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        // The quote a client would read off-chain, before submitting.
        let quoted = pool::quote_a_for_b<USDC, WETH>(p, 1000);
        let k_before = pool::invariant_k<USDC, WETH>(p);

        let out = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(1000), 0);

        assert!(coin::value(&out) == quoted, 0);
        assert!(quoted == 996, 1); // the hand-computed value

        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == R + 1000, 2);
        assert!(reserve_b == R - quoted, 3);
        // The fee stayed in the pool, so k strictly grew.
        assert!(pool::invariant_k<USDC, WETH>(p) > k_before, 4);

        burn_weth(out);
    }

    #[test]
    fun swapping_both_ways_is_symmetric() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        // A balanced pool quotes the same price in either direction.
        let out = pool::swap_b_for_a<USDC, WETH>(p, mint_weth(1000), 0);
        assert!(coin::value(&out) == 996, 0);

        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == R - 996, 1);
        assert!(reserve_b == R + 1000, 2);

        burn_usdc(out);
    }

    #[test]
    fun a_round_trip_loses_the_fee() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        let mid = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(10000), 0);
        let back = pool::swap_b_for_a<USDC, WETH>(p, mid, 0);

        // Two 30bps fees plus slippage, so strictly less than went in.
        assert!(coin::value(&back) < 10000, 0);
        // But not catastrophically less -- roughly 60bps of round-trip cost.
        assert!(coin::value(&back) > 9900, 1);

        burn_usdc(back);
    }

    #[test]
    #[expected_failure(abort_code = pool::ESlippage)]
    fun a_swap_below_min_out_aborts() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);
        // The pool can only pay 996.
        let out = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(1000), 997);
        burn_weth(out);
    }

    #[test]
    fun the_exact_out_quote_is_what_the_swap_actually_costs() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        let needed = pool::quote_in_for_b<USDC, WETH>(p, 996);
        let out = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(needed), 996);
        // Paying the exact-out quote delivers at least the target.
        assert!(coin::value(&out) >= 996, 0);

        burn_weth(out);
    }

    // ---------------------------------------------------------------- //
    // Liquidity                                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun adding_off_ratio_liquidity_refunds_the_surplus() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        // Offering 1000 A and 5000 B into a 1:1 pool.
        let (lp, refund_a, refund_b) =
            pool::add_liquidity<USDC, WETH>(p, mint_usdc(1000), mint_weth(5000), 0);

        assert!(fungible_asset::amount(&lp) == 1000, 0);
        assert!(coin::value(&refund_a) == 0, 1);
        assert!(coin::value(&refund_b) == 4000, 2); // the surplus comes back

        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == R + 1000 && reserve_b == R + 1000, 3);
        assert!(pool::lp_supply_value<USDC, WETH>(p) == R + 1000, 4);

        primary_fungible_store::deposit(TRADER, lp);
        burn_usdc(refund_a);
        burn_weth(refund_b);
    }

    #[test]
    fun removing_liquidity_returns_the_proportional_share() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        let lp = take_admin_lp(p);
        let part = fungible_asset::extract(&mut lp, 1000);
        let (out_a, out_b) = pool::remove_liquidity<USDC, WETH>(p, part, 0, 0);

        // 1000 shares of a 1e6-share pool holding 1e6 of each side.
        assert!(coin::value(&out_a) == 1000, 0);
        assert!(coin::value(&out_b) == 1000, 1);

        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == R - 1000 && reserve_b == R - 1000, 2);
        assert!(pool::lp_supply_value<USDC, WETH>(p) == R - 1000, 3);

        burn_usdc(out_a);
        burn_weth(out_b);
        primary_fungible_store::deposit(ADMIN, lp);
    }

    #[test]
    fun the_locked_floor_survives_every_holder_exiting() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        let lp = take_admin_lp(p);
        let (out_a, out_b) = pool::remove_liquidity<USDC, WETH>(p, lp, 0, 0);

        // Everything the creator held is gone, but the pool is not empty:
        // MINIMUM_LIQUIDITY shares remain, held by the pool itself.
        let min = cpmm_math::minimum_liquidity();
        assert!(pool::lp_supply_value<USDC, WETH>(p) == min, 0);
        let (reserve_a, reserve_b) = pool::reserves<USDC, WETH>(p);
        assert!(reserve_a == min && reserve_b == min, 1);
        assert!(coin::value(&out_a) == R - min, 2);
        assert!(coin::value(&out_b) == R - min, 3);

        burn_usdc(out_a);
        burn_weth(out_b);
    }

    #[test]
    fun swap_fees_accrue_to_the_remaining_liquidity_providers() acquires Caps {
        setup();
        let p = seed_pool(R, R, FEE);

        // A trader churns the pool in both directions, paying fees each way.
        let mid = pool::swap_a_for_b<USDC, WETH>(p, mint_usdc(100000), 0);
        let back = pool::swap_b_for_a<USDC, WETH>(p, mid, 0);
        burn_usdc(back);

        // The creator's shares are now worth more than they deposited.
        let lp = take_admin_lp(p);
        let shares = fungible_asset::amount(&lp);
        let (out_a, out_b) = pool::remove_liquidity<USDC, WETH>(p, lp, 0, 0);

        // Deposited `shares` worth of each side at 1:1; a round trip leaves
        // the pool A-heavy, so A comes back up and B comes back near flat.
        assert!(coin::value(&out_a) > shares, 0);
        // Total value across both sides beat the deposit.
        assert!(coin::value(&out_a) + coin::value(&out_b) > shares * 2, 1);

        burn_usdc(out_a);
        burn_weth(out_b);
    }

    // ---------------------------------------------------------------- //
    // Aptos-only: the check Sui's type system makes unnecessary         //
    // ---------------------------------------------------------------- //

    #[test]
    #[expected_failure(abort_code = pool::ENoSuchPool)]
    fun a_swap_against_an_address_holding_no_pool_aborts() acquires Caps {
        setup();
        seed_pool(R, R, FEE);
        // A live pool exists, but not here. On Sui this transaction could not
        // be formed at all -- the pool argument is an object reference, and the
        // runtime resolves it before any Move code runs.
        let out = pool::swap_a_for_b<USDC, WETH>(@0xDEAD, mint_usdc(1000), 0);
        burn_weth(out);
    }
}
