/// The StableSwap pool: two reserves, an amplification coefficient, and the
/// mint authority for its own LP token.
///
/// Same division of labour as `braid_cpmm::pool` -- all curve math lives in
/// `stable_math`, and this module only moves `Coin`s and asserts what the
/// math cannot assert for itself: slippage bounds, and that `D` never falls.
///
/// One deliberate difference from the CPMM pool. There, `add_liquidity` takes
/// both coins, computes the on-ratio pair, and hands back the change, because
/// depositing off-ratio into a constant-product pool is simply a donation.
/// Here, off-ratio deposits are a supported operation -- you may deposit
/// entirely into one side -- and are priced by the imbalance fee instead. So
/// this `add_liquidity` consumes both coins whole and returns no change.
///
/// APTOS PORT of `move/sui/braid_stable/sources/pool.move`. The custody model
/// is the one `braid_cpmm::pool` sets out and argues: the pool is a sticky
/// object addressed by `address` rather than passed as `&mut`, LP is a fungible
/// asset whose refs live in the pool, and the reserves stay legacy `Coin`
/// because `FungibleAsset` has no `store`.
module braid_stable::pool {
    use std::option;
    use std::signer;
    use std::string;
    use aptos_std::type_info;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, MintRef, BurnRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use braid_stable::stable_math;

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 0;
    /// Output below `min_out`, or LP below `min_lp_out`.
    const ESlippage: u64 = 1;
    /// `D` fell across an operation that must not lower it.
    const EInvariantViolated: u64 = 2;
    /// An amount that must be positive was zero.
    const EZeroAmount: u64 = 3;
    /// The two coin types of a pool must differ.
    const ESameCoinType: u64 = 4;
    /// The seed deposit could not cover the locked minimum.
    const EInsufficientLiquidity: u64 = 5;
    /// No pool of that pair lives at the given address. Aptos-only; see the
    /// note on `braid_cpmm::pool::ENoSuchPool`.
    const ENoSuchPool: u64 = 6;

    // ------------------------------------------------------------------ //
    // Types                                                              //
    // ------------------------------------------------------------------ //

    struct StablePool<phantom A, phantom B> has key {
        reserve_a: Coin<A>,
        reserve_b: Coin<B>,
        /// The sole mint and burn authority for this pool's LP asset, standing
        /// in for Sui's `Supply<SLP<A, B>>`.
        lp_mint: MintRef,
        lp_burn: BurnRef,
        lp_metadata: Object<Metadata>,
        /// `A * A_PRECISION`. Fixed at creation.
        ///
        /// Curve ramps this over time so a change cannot be sandwiched; that is
        /// a governance feature and this pool has no governance, so it is
        /// immutable instead. Immutable is the safe end of that trade.
        amp: u64,
        /// Swap fee in basis points, charged on the output.
        fee_bps: u64,
        /// Locked forever, so supply never returns to zero. Held in the pool
        /// object's own primary store, which has no signer.
        locked_lp: u64,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    #[event]
    struct StablePoolCreated has drop, store {
        pool_id: address,
        amount_a: u64,
        amount_b: u64,
        amp: u64,
        fee_bps: u64,
    }

    #[event]
    struct LiquidityAdded has drop, store {
        pool_id: address,
        amount_a: u64,
        amount_b: u64,
        lp_minted: u64,
        /// Imbalance fee withheld on each side. Zero for an on-ratio deposit.
        imbalance_fee_a: u64,
        imbalance_fee_b: u64,
    }

    #[event]
    struct LiquidityRemoved has drop, store {
        pool_id: address,
        amount_a: u64,
        amount_b: u64,
        lp_burned: u64,
    }

    #[event]
    struct Swapped has drop, store {
        pool_id: address,
        a_to_b: bool,
        amount_in: u64,
        amount_out: u64,
        reserve_a: u64,
        reserve_b: u64,
        /// `D` after the swap. Monotone non-decreasing across the pool's life.
        invariant_d: u128,
    }

    // ------------------------------------------------------------------ //
    // Creation                                                           //
    // ------------------------------------------------------------------ //

    /// Seed a new stable pool. Returns its address and the creator's LP.
    ///
    /// Unlike the CPMM, the seed deposit should be close to on-ratio: `D` is
    /// computed from whatever is deposited, and seeding a "stable" pool badly
    /// skewed just means the first trader arbitrages it back.
    public fun create_pool<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        amp: u64,
        fee_bps: u64,
    ): (address, FungibleAsset) {
        stable_math::assert_valid_amp(amp);
        assert!(fee_bps <= stable_math::max_fee_bps(), EInvalidFee);
        assert!(type_info::type_of<A>() != type_info::type_of<B>(), ESameCoinType);

        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 && amount_b > 0, EZeroAmount);

        // Shares are denominated in D, so a fresh share is worth exactly 1.0.
        let total_lp = stable_math::initial_lp(amount_a, amount_b, amp);
        let min_lp = stable_math::minimum_liquidity();
        assert!(total_lp > min_lp, EInsufficientLiquidity);

        let ctor = object::create_sticky_object(@braid_stable);
        let pool_signer = object::generate_signer(&ctor);
        let pool_addr = object::address_from_constructor_ref(&ctor);
        object::disable_ungated_transfer(&object::generate_transfer_ref(&ctor));

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor,
            option::none(),
            string::utf8(b"Braid Stable LP"),
            string::utf8(b"bSLP"),
            8,
            string::utf8(b""),
            string::utf8(b""),
        );
        let lp_mint = fungible_asset::generate_mint_ref(&ctor);
        let lp_burn = fungible_asset::generate_burn_ref(&ctor);
        let lp_metadata = object::object_from_constructor_ref<Metadata>(&ctor);

        let user_lp = fungible_asset::mint(&lp_mint, total_lp - min_lp);
        primary_fungible_store::mint(&lp_mint, pool_addr, min_lp);

        move_to(&pool_signer, StablePool<A, B> {
            reserve_a: coin_a,
            reserve_b: coin_b,
            lp_mint,
            lp_burn,
            lp_metadata,
            amp,
            fee_bps,
            locked_lp: min_lp,
        });

        event::emit(StablePoolCreated {
            pool_id: pool_addr,
            amount_a,
            amount_b,
            amp,
            fee_bps,
        });

        (pool_addr, user_lp)
    }

    /// `create_pool`, funded from the caller's balances and with the LP paid to
    /// them.
    public entry fun create_pool_entry<A, B>(
        creator: &signer,
        amount_a: u64,
        amount_b: u64,
        amp: u64,
        fee_bps: u64,
    ) {
        let coin_a = coin::withdraw<A>(creator, amount_a);
        let coin_b = coin::withdraw<B>(creator, amount_b);
        let (_pool_addr, lp) = create_pool<A, B>(coin_a, coin_b, amp, fee_bps);
        primary_fungible_store::deposit(signer::address_of(creator), lp);
    }

    // ------------------------------------------------------------------ //
    // Liquidity                                                          //
    // ------------------------------------------------------------------ //

    /// Deposit any mix of the two coins, including entirely one-sided.
    ///
    /// Both coins are consumed whole. Whatever the deposit does to the pool's
    /// balance is priced by the imbalance fee, which stays in the reserves and
    /// therefore accrues to the existing LPs.
    public fun add_liquidity<A, B>(
        pool_addr: address,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        min_lp_out: u64,
    ): FungibleAsset acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<StablePool<A, B>>(pool_addr);

        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 || amount_b > 0, EZeroAmount);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);

        let (minted, fee_a, fee_b) = stable_math::lp_for_deposit(
            amount_a,
            amount_b,
            reserve_a,
            reserve_b,
            lp_supply_of(pool),
            pool.amp,
            pool.fee_bps,
        );
        assert!(minted >= min_lp_out, ESlippage);

        // The full deposit lands in the reserves; the fee is expressed by
        // minting fewer shares than the deposit would otherwise be worth.
        coin::merge(&mut pool.reserve_a, coin_a);
        coin::merge(&mut pool.reserve_b, coin_b);
        let lp = fungible_asset::mint(&pool.lp_mint, minted);

        event::emit(LiquidityAdded {
            pool_id: pool_addr,
            amount_a,
            amount_b,
            lp_minted: minted,
            imbalance_fee_a: fee_a,
            imbalance_fee_b: fee_b,
        });

        lp
    }

    /// Burn LP for a proportional slice of both reserves. No fee: a
    /// proportional exit does not move the pool's balance.
    public fun remove_liquidity<A, B>(
        pool_addr: address,
        lp: FungibleAsset,
        min_a: u64,
        min_b: u64,
    ): (Coin<A>, Coin<B>) acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<StablePool<A, B>>(pool_addr);

        let lp_amount = fungible_asset::amount(&lp);
        assert!(lp_amount > 0, EZeroAmount);

        let (out_a, out_b) = stable_math::withdraw_amounts(
            lp_amount,
            coin::value(&pool.reserve_a),
            coin::value(&pool.reserve_b),
            lp_supply_of(pool),
        );
        assert!(out_a >= min_a && out_b >= min_b, ESlippage);

        fungible_asset::burn(&pool.lp_burn, lp);

        event::emit(LiquidityRemoved {
            pool_id: pool_addr,
            amount_a: out_a,
            amount_b: out_b,
            lp_burned: lp_amount,
        });

        (
            coin::extract(&mut pool.reserve_a, out_a),
            coin::extract(&mut pool.reserve_b, out_b),
        )
    }

    // ------------------------------------------------------------------ //
    // Swaps                                                              //
    // ------------------------------------------------------------------ //

    public fun swap_a_for_b<A, B>(
        pool_addr: address,
        coin_in: Coin<A>,
        min_out: u64,
    ): Coin<B> acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<StablePool<A, B>>(pool_addr);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);
        let d_before = stable_math::get_d(reserve_a, reserve_b, pool.amp);

        let amount_out =
            stable_math::amount_out(amount_in, reserve_a, reserve_b, pool.amp, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        coin::merge(&mut pool.reserve_a, coin_in);
        let out = coin::extract(&mut pool.reserve_b, amount_out);

        let after_a = coin::value(&pool.reserve_a);
        let after_b = coin::value(&pool.reserve_b);
        let d_after = stable_math::get_d(after_a, after_b, pool.amp);
        assert!(d_after >= d_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: true,
            amount_in,
            amount_out,
            reserve_a: after_a,
            reserve_b: after_b,
            invariant_d: d_after,
        });

        out
    }

    public fun swap_b_for_a<A, B>(
        pool_addr: address,
        coin_in: Coin<B>,
        min_out: u64,
    ): Coin<A> acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<StablePool<A, B>>(pool_addr);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);
        let d_before = stable_math::get_d(reserve_a, reserve_b, pool.amp);

        let amount_out =
            stable_math::amount_out(amount_in, reserve_b, reserve_a, pool.amp, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        coin::merge(&mut pool.reserve_b, coin_in);
        let out = coin::extract(&mut pool.reserve_a, amount_out);

        let after_a = coin::value(&pool.reserve_a);
        let after_b = coin::value(&pool.reserve_b);
        let d_after = stable_math::get_d(after_a, after_b, pool.amp);
        assert!(d_after >= d_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: false,
            amount_in,
            amount_out,
            reserve_a: after_a,
            reserve_b: after_b,
            invariant_d: d_after,
        });

        out
    }

    public entry fun swap_a_for_b_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
    ) acquires StablePool {
        let coin_in = coin::withdraw<A>(trader, amount_in);
        let out = swap_a_for_b<A, B>(pool_addr, coin_in, min_out);
        coin::deposit(signer::address_of(trader), out);
    }

    public entry fun swap_b_for_a_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
    ) acquires StablePool {
        let coin_in = coin::withdraw<B>(trader, amount_in);
        let out = swap_b_for_a<A, B>(pool_addr, coin_in, min_out);
        coin::deposit(signer::address_of(trader), out);
    }

    // ------------------------------------------------------------------ //
    // Views                                                              //
    // ------------------------------------------------------------------ //

    #[view]
    public fun reserves<A, B>(pool_addr: address): (u64, u64) acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<StablePool<A, B>>(pool_addr);
        (coin::value(&pool.reserve_a), coin::value(&pool.reserve_b))
    }

    #[view]
    public fun amp<A, B>(pool_addr: address): u64 acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<StablePool<A, B>>(pool_addr).amp
    }

    #[view]
    public fun fee_bps<A, B>(pool_addr: address): u64 acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<StablePool<A, B>>(pool_addr).fee_bps
    }

    #[view]
    public fun lp_supply_value<A, B>(pool_addr: address): u64 acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        lp_supply_of(borrow_global<StablePool<A, B>>(pool_addr))
    }

    #[view]
    /// The LP asset's metadata object, so a holder can find their balance.
    public fun lp_metadata<A, B>(pool_addr: address): Object<Metadata> acquires StablePool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<StablePool<A, B>>(pool_addr).lp_metadata
    }

    #[view]
    public fun quote_a_for_b<A, B>(pool_addr: address, amount_in: u64): u64 acquires StablePool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        stable_math::amount_out(
            amount_in, reserve_a, reserve_b, amp<A, B>(pool_addr), fee_bps<A, B>(pool_addr),
        )
    }

    #[view]
    public fun quote_b_for_a<A, B>(pool_addr: address, amount_in: u64): u64 acquires StablePool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        stable_math::amount_out(
            amount_in, reserve_b, reserve_a, amp<A, B>(pool_addr), fee_bps<A, B>(pool_addr),
        )
    }

    #[view]
    public fun quote_in_for_b<A, B>(pool_addr: address, amount_out: u64): u64 acquires StablePool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        stable_math::amount_in(
            amount_out, reserve_a, reserve_b, amp<A, B>(pool_addr), fee_bps<A, B>(pool_addr),
        )
    }

    #[view]
    /// The pool's invariant. The router compares this across venues.
    public fun invariant_d<A, B>(pool_addr: address): u128 acquires StablePool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        stable_math::get_d(reserve_a, reserve_b, amp<A, B>(pool_addr))
    }

    #[view]
    /// `D / supply` as Q64.64 -- the LP share price. Starts at 1.0, only rises.
    public fun virtual_price<A, B>(pool_addr: address): u128 acquires StablePool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        stable_math::virtual_price(
            reserve_a,
            reserve_b,
            lp_supply_value<A, B>(pool_addr),
            amp<A, B>(pool_addr),
        )
    }

    // ------------------------------------------------------------------ //
    // Internals                                                          //
    // ------------------------------------------------------------------ //

    /// Total LP in existence, the locked floor included.
    fun lp_supply_of<A, B>(pool: &StablePool<A, B>): u64 {
        let s = fungible_asset::supply(pool.lp_metadata);
        if (option::is_some(&s)) (*option::borrow(&s) as u64) else 0
    }

    fun assert_pool_exists<A, B>(pool_addr: address) {
        assert!(exists<StablePool<A, B>>(pool_addr), ENoSuchPool);
    }
}
