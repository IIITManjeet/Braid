/// The constant-product pool: an Aptos object holding two reserves and the
/// mint authority for its own LP token.
///
/// All pricing lives in `cpmm_math`. This module is only custody and
/// bookkeeping -- it moves `Coin`s around, mints and burns LP, and asserts
/// the two things the math cannot assert for itself:
///
///   1. the caller got at least the output they asked for (slippage), and
///   2. `k` did not decrease (the invariant).
///
/// The second check is redundant if `cpmm_math` is correct. It is here anyway,
/// because it is the difference between a pricing bug being a failed
/// transaction and a pricing bug being a drained pool.
///
/// APTOS PORT of `move/sui/braid_cpmm/sources/pool.move`. Unlike `cpmm_math`,
/// this module is not a transliteration -- the custody model genuinely differs.
/// The three changes that matter, argued in full in `docs/aptos-port.md`:
///
///   * Sui passes the pool as `&mut Pool<A, B>`, a shared object the runtime
///     resolves from an id. Aptos keeps resources in global storage under an
///     address, so the pool arrives as a plain `address` and every entry point
///     that touches it is marked `acquires Pool`.
///   * Sui's `Supply<LP<A, B>>` is a witness-minted supply: `create_supply`
///     eats one value of a `drop` type and hands back the only minter. Aptos
///     has no such thing for a type parameterised on the pair -- `coin::initialize`
///     demands a signer for the address that *declares* the type. So LP here is
///     a fungible asset whose `MintRef`/`BurnRef` live inside the pool, which
///     needs no publisher signer and keeps pool creation permissionless.
///   * Sui's `Balance<T>` is storable, so reserves are struct fields. Aptos's
///     `FungibleAsset` deliberately is not -- it is a hot potato, the same
///     pattern `braid_router` uses for `Route` -- so the reserves stay legacy
///     `Coin<A>`, which does have `store`, and only the LP is a fungible asset.
module braid_cpmm::pool {
    use std::option;
    use std::signer;
    use std::string;
    use aptos_std::type_info;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, MintRef, BurnRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use braid_cpmm::cpmm_math;

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 0;
    /// Output below `min_out`, or input above `max_in`.
    const ESlippage: u64 = 1;
    /// `k` decreased across a swap. Should be unreachable.
    const EInvariantViolated: u64 = 2;
    /// An amount that must be positive was zero.
    const EZeroAmount: u64 = 3;
    /// The two coin types of a pool must differ.
    const ESameCoinType: u64 = 4;
    /// No pool of that pair lives at the given address.
    ///
    /// Sui has no counterpart: there, a `&mut Pool<A, B>` argument either
    /// resolves to a live object of exactly that type or the transaction never
    /// starts. Addressing global storage by hand puts that check back on us.
    const ENoSuchPool: u64 = 5;

    // ------------------------------------------------------------------ //
    // Types                                                              //
    // ------------------------------------------------------------------ //

    /// The pool, stored at its own object address.
    ///
    /// `key` rather than Sui's `key, store`: on Aptos `key` means "can be a
    /// top-level resource in global storage", which is a different claim from
    /// Sui's "has a UID and can be owned". There is no `id` field because the
    /// address the resource is stored at *is* the identity.
    struct Pool<phantom A, phantom B> has key {
        reserve_a: Coin<A>,
        reserve_b: Coin<B>,
        /// The sole mint and burn authority for this pool's LP asset. Holding
        /// the refs inside the pool is the fungible-asset analogue of Sui
        /// parking the `Supply` in the object: there is no separate capability
        /// object to lose, and no address outside this module can mint.
        lp_mint: MintRef,
        lp_burn: BurnRef,
        /// The LP asset's metadata object. Its address equals the pool's, since
        /// both come from the same `ConstructorRef`.
        lp_metadata: Object<Metadata>,
        /// Swap fee in basis points, fixed at creation.
        fee_bps: u64,
        /// The `MINIMUM_LIQUIDITY` shares minted at creation and never
        /// recoverable, so `lp_supply` can never return to zero while the pool
        /// holds reserves. See `cpmm_math::minimum_liquidity`.
        ///
        /// Sui parks them as a `Balance<LP>` field. A `FungibleAsset` cannot be
        /// a field, so here they are minted into the pool object's own primary
        /// store -- an address with no signer, which is what makes them locked.
        /// The recorded count is for reporting; the lock is the missing signer.
        locked_lp: u64,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //
    //
    // `#[event]` module events, the closest Aptos equivalent of Sui's
    // `event::emit`. `pool_id` is an address here rather than an `ID`.

    #[event]
    struct PoolCreated has drop, store {
        pool_id: address,
        amount_a: u64,
        amount_b: u64,
        fee_bps: u64,
    }

    #[event]
    struct LiquidityAdded has drop, store {
        pool_id: address,
        amount_a: u64,
        amount_b: u64,
        lp_minted: u64,
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
        /// True when A went in and B came out.
        a_to_b: bool,
        amount_in: u64,
        amount_out: u64,
        fee_paid: u64,
        reserve_a: u64,
        reserve_b: u64,
    }

    // ------------------------------------------------------------------ //
    // Creation                                                           //
    // ------------------------------------------------------------------ //

    /// Seed a new pool. Returns its address and the creator's LP.
    ///
    /// The initial deposit sets the price; there is no oracle and no check on
    /// it, which is correct -- a pool seeded at a wrong price is arbitraged to
    /// the right one, at the seeder's expense.
    ///
    /// The LP comes back as a bare `FungibleAsset`, which has no abilities: the
    /// caller cannot drop it or store it and must deposit it somewhere. That is
    /// the same discipline Sui gets from returning a `Coin<LP<A, B>>` by value.
    public fun create_pool<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        fee_bps: u64,
    ): (address, FungibleAsset) {
        assert!(fee_bps <= cpmm_math::max_fee_bps(), EInvalidFee);
        // A Pool<A, A> would let a swap read and write the same reserve.
        assert!(type_info::type_of<A>() != type_info::type_of<B>(), ESameCoinType);

        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 && amount_b > 0, EZeroAmount);

        // Aborts if `sqrt(a * b)` does not clear MINIMUM_LIQUIDITY.
        let user_lp = cpmm_math::initial_lp(amount_a, amount_b);

        // Sui's `transfer::share_object` has no direct Aptos spelling. The
        // nearest thing is an object owned by the package address -- which has
        // no signer after publication -- with ungated transfer switched off, so
        // no one can move it and everyone can reach it by address.
        // `create_sticky_object`, not `create_object`: the latter yields a
        // deletable object, and `add_fungibility` refuses those -- a fungible
        // asset's metadata must outlive anything denominated in it. Sui has no
        // counterpart, because there an object is deleted only by unpacking it,
        // which this module never does.
        let ctor = object::create_sticky_object(@braid_cpmm);
        let pool_signer = object::generate_signer(&ctor);
        let pool_addr = object::address_from_constructor_ref(&ctor);
        object::disable_ungated_transfer(&object::generate_transfer_ref(&ctor));

        // The LP asset shares the pool's address: the pool object *is* the
        // fungible-asset metadata. One address, two roles.
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor,
            option::none(),              // no supply cap
            string::utf8(b"Braid CPMM LP"),
            string::utf8(b"bLP"),
            8,                           // decimals -- display only
            string::utf8(b""),
            string::utf8(b""),
        );
        let lp_mint = fungible_asset::generate_mint_ref(&ctor);
        let lp_burn = fungible_asset::generate_burn_ref(&ctor);
        let lp_metadata = object::object_from_constructor_ref<Metadata>(&ctor);

        let user_lp_asset = fungible_asset::mint(&lp_mint, user_lp);
        // The floor, minted into the pool's own store. Nothing holds a signer
        // for that address, so these shares can never be withdrawn.
        primary_fungible_store::mint(&lp_mint, pool_addr, cpmm_math::minimum_liquidity());

        move_to(&pool_signer, Pool<A, B> {
            reserve_a: coin_a,
            reserve_b: coin_b,
            lp_mint,
            lp_burn,
            lp_metadata,
            fee_bps,
            locked_lp: cpmm_math::minimum_liquidity(),
        });

        event::emit(PoolCreated {
            pool_id: pool_addr,
            amount_a,
            amount_b,
            fee_bps,
        });

        (pool_addr, user_lp_asset)
    }

    /// `create_pool`, funded from the caller's balances and with the LP paid to
    /// them. The form a wallet calls.
    ///
    /// Sui's counterpart exists because a PTB wants `create_pool` to *return*
    /// the LP so a later command can use it. Aptos has no PTBs, so the wrapper
    /// is not a convenience over composition -- it is the only callable form,
    /// and the value-returning version above is what other Move modules use.
    public entry fun create_pool_entry<A, B>(
        creator: &signer,
        amount_a: u64,
        amount_b: u64,
        fee_bps: u64,
    ) {
        let coin_a = coin::withdraw<A>(creator, amount_a);
        let coin_b = coin::withdraw<B>(creator, amount_b);
        let (_pool_addr, lp) = create_pool<A, B>(coin_a, coin_b, fee_bps);
        primary_fungible_store::deposit(signer::address_of(creator), lp);
    }

    // ------------------------------------------------------------------ //
    // Liquidity                                                          //
    // ------------------------------------------------------------------ //

    /// Deposit against the current ratio.
    ///
    /// Takes both coins by value and returns the unused remainder of each,
    /// rather than requiring the caller to compute the ratio first. Returning
    /// the change instead of aborting on a mismatch keeps the entry point
    /// usable when the reserves moved between the client's quote and the
    /// transaction landing.
    public fun add_liquidity<A, B>(
        pool_addr: address,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        min_lp_out: u64,
    ): (FungibleAsset, Coin<A>, Coin<B>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);
        let supply = lp_supply_of(pool);

        // Both returns are bounded by their `_desired` input, so the extracts
        // below always have the funds.
        let (use_a, use_b) = cpmm_math::optimal_deposit(
            coin::value(&coin_a),
            coin::value(&coin_b),
            reserve_a,
            reserve_b,
        );
        let minted = cpmm_math::lp_for_deposit(use_a, use_b, reserve_a, reserve_b, supply);
        assert!(minted >= min_lp_out, ESlippage);

        coin::merge(&mut pool.reserve_a, coin::extract(&mut coin_a, use_a));
        coin::merge(&mut pool.reserve_b, coin::extract(&mut coin_b, use_b));
        let lp = fungible_asset::mint(&pool.lp_mint, minted);

        event::emit(LiquidityAdded {
            pool_id: pool_addr,
            amount_a: use_a,
            amount_b: use_b,
            lp_minted: minted,
        });

        (lp, coin_a, coin_b)
    }

    /// Burn LP and take the proportional share of both reserves.
    public fun remove_liquidity<A, B>(
        pool_addr: address,
        lp: FungibleAsset,
        min_a: u64,
        min_b: u64,
    ): (Coin<A>, Coin<B>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        let lp_amount = fungible_asset::amount(&lp);
        assert!(lp_amount > 0, EZeroAmount);

        let (out_a, out_b) = cpmm_math::withdraw_amounts(
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

    /// Sell `coin_in` of A for B, exact-in.
    public fun swap_a_for_b<A, B>(
        pool_addr: address,
        coin_in: Coin<A>,
        min_out: u64,
    ): Coin<B> acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);
        let k_before = cpmm_math::k(reserve_a, reserve_b);

        let amount_out = cpmm_math::amount_out(amount_in, reserve_a, reserve_b, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        coin::merge(&mut pool.reserve_a, coin_in);
        let out = coin::extract(&mut pool.reserve_b, amount_out);

        let reserve_a_after = coin::value(&pool.reserve_a);
        let reserve_b_after = coin::value(&pool.reserve_b);
        assert!(cpmm_math::k(reserve_a_after, reserve_b_after) >= k_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: true,
            amount_in,
            amount_out,
            fee_paid: cpmm_math::fee_amount(amount_in, pool.fee_bps),
            reserve_a: reserve_a_after,
            reserve_b: reserve_b_after,
        });

        out
    }

    /// Sell `coin_in` of B for A, exact-in.
    public fun swap_b_for_a<A, B>(
        pool_addr: address,
        coin_in: Coin<B>,
        min_out: u64,
    ): Coin<A> acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = coin::value(&pool.reserve_a);
        let reserve_b = coin::value(&pool.reserve_b);
        let k_before = cpmm_math::k(reserve_a, reserve_b);

        let amount_out = cpmm_math::amount_out(amount_in, reserve_b, reserve_a, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        coin::merge(&mut pool.reserve_b, coin_in);
        let out = coin::extract(&mut pool.reserve_a, amount_out);

        let reserve_a_after = coin::value(&pool.reserve_a);
        let reserve_b_after = coin::value(&pool.reserve_b);
        assert!(cpmm_math::k(reserve_a_after, reserve_b_after) >= k_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: false,
            amount_in,
            amount_out,
            fee_paid: cpmm_math::fee_amount(amount_in, pool.fee_bps),
            reserve_a: reserve_a_after,
            reserve_b: reserve_b_after,
        });

        out
    }

    /// `swap_a_for_b` funded from, and paid back into, the caller's balances.
    public entry fun swap_a_for_b_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
    ) acquires Pool {
        let coin_in = coin::withdraw<A>(trader, amount_in);
        let out = swap_a_for_b<A, B>(pool_addr, coin_in, min_out);
        coin::deposit(signer::address_of(trader), out);
    }

    /// `swap_b_for_a` funded from, and paid back into, the caller's balances.
    public entry fun swap_b_for_a_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
    ) acquires Pool {
        let coin_in = coin::withdraw<B>(trader, amount_in);
        let out = swap_b_for_a<A, B>(pool_addr, coin_in, min_out);
        coin::deposit(signer::address_of(trader), out);
    }

    // ------------------------------------------------------------------ //
    // Views -- what the router and the Rust replica read                 //
    // ------------------------------------------------------------------ //
    //
    // `#[view]` is the Aptos answer to what Sui does with `dev-inspect`: the
    // fullnode will evaluate these against live state and return the value,
    // with no transaction and no gas. It is also the piece the Sui side of this
    // repo is still missing -- see the "Not yet wired" note in the README.

    #[view]
    public fun reserves<A, B>(pool_addr: address): (u64, u64) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        (coin::value(&pool.reserve_a), coin::value(&pool.reserve_b))
    }

    #[view]
    public fun fee_bps<A, B>(pool_addr: address): u64 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).fee_bps
    }

    #[view]
    public fun lp_supply_value<A, B>(pool_addr: address): u64 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        lp_supply_of(borrow_global<Pool<A, B>>(pool_addr))
    }

    #[view]
    /// The LP asset's metadata object, so a holder can find their balance.
    public fun lp_metadata<A, B>(pool_addr: address): Object<Metadata> acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).lp_metadata
    }

    #[view]
    /// Exact-in quote against live reserves.
    public fun quote_a_for_b<A, B>(pool_addr: address, amount_in: u64): u64 acquires Pool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        cpmm_math::amount_out(amount_in, reserve_a, reserve_b, fee_bps<A, B>(pool_addr))
    }

    #[view]
    public fun quote_b_for_a<A, B>(pool_addr: address, amount_in: u64): u64 acquires Pool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        cpmm_math::amount_out(amount_in, reserve_b, reserve_a, fee_bps<A, B>(pool_addr))
    }

    #[view]
    /// Exact-out quote: what `amount_out` of B costs in A.
    public fun quote_in_for_b<A, B>(pool_addr: address, amount_out: u64): u64 acquires Pool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        cpmm_math::amount_in(amount_out, reserve_a, reserve_b, fee_bps<A, B>(pool_addr))
    }

    #[view]
    /// Current `k`. The router compares this across venues.
    public fun invariant_k<A, B>(pool_addr: address): u256 acquires Pool {
        let (reserve_a, reserve_b) = reserves<A, B>(pool_addr);
        cpmm_math::k(reserve_a, reserve_b)
    }

    // ------------------------------------------------------------------ //
    // Internals                                                          //
    // ------------------------------------------------------------------ //

    /// Total LP in existence, the locked floor included -- the same quantity
    /// Sui reads with `balance::supply_value`.
    ///
    /// A fungible asset created without a maximum still reports a supply, so
    /// the `none` branch is unreachable; it collapses to 0 rather than aborting
    /// because a pool that somehow lost its supply should fail the liquidity
    /// math loudly, not fail here with a misleading code.
    fun lp_supply_of<A, B>(pool: &Pool<A, B>): u64 {
        let s = fungible_asset::supply(pool.lp_metadata);
        if (option::is_some(&s)) (*option::borrow(&s) as u64) else 0
    }

    fun assert_pool_exists<A, B>(pool_addr: address) {
        assert!(exists<Pool<A, B>>(pool_addr), ENoSuchPool);
    }
}
