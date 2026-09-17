/// The concentrated-liquidity pool.
///
/// Unlike the other two venues, a pool here holds no reserves of its own until
/// someone opens a position, and it is created with a *price* rather than a
/// deposit. Liquidity lives in ranges, and only the ranges spanning the current
/// price are active.
///
/// The pool owns three tables: tick state, the bitmap words, and positions. It
/// is the only module in the package that touches chain types -- everything it
/// calls is pure arithmetic, which is what keeps that arithmetic testable and
/// reachable by the differential fuzzer.
///
/// # The swap loop
///
/// A swap cannot be one calculation, because liquidity changes at every
/// initialized tick. So the pool walks: find the next boundary, ask
/// `swap_math` how far the price gets before either the input runs out or the
/// boundary is reached, apply it, and if a boundary was reached cross it and
/// pick up the liquidity change. Repeat.
///
/// APTOS PORT of `move/sui/braid_clmm/sources/pool.move`, following the custody
/// model `braid_cpmm::pool` sets out and argues. Three notes specific to this
/// venue:
///
///   * Only the public entry points differ. Each one resolves the pool with a
///     single `borrow_global_mut` and then calls the same private helpers the
///     Sui version does, taking the same `&mut Pool<A, B>` -- so `modify_position`,
///     `run_swap` and the tick/bitmap accessors are character-for-character the
///     Sui source. The swap loop is the part that must not drift, and this way
///     it cannot.
///   * `ctx.sender()` becomes an explicit `&signer`. Sui authenticates the
///     position owner through the transaction context; here the authority has
///     to be passed, and `remove_liquidity` and `collect` would be a theft
///     primitive if it were a bare `address` instead.
///   * The plain `aptos_std::table` is enough here, unlike `braid_clob`'s
///     `table_with_length`: nothing counts these tables or destroys them empty,
///     and the length field would be a write on every tick update for nothing.
///
/// Sui's `LP<phantom A, phantom B>` struct is not carried over. It was declared
/// and never used -- CLMM positions are keyed records, not tokens -- and a port
/// is the wrong moment to copy dead code forward.
module braid_clmm::pool {
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;
    use aptos_framework::object;

    use braid_clmm::fee_math;
    // Sui imports the `I128` type alias here too, but nothing names it -- the
    // one `I128` value in this module is inferred. Aptos warns on the unused
    // alias where Sui does not, so it is dropped.
    use braid_clmm::i128;
    use braid_clmm::i32::{Self, I32};
    use braid_clmm::liquidity_math;
    use braid_clmm::swap_math;
    use braid_clmm::tick::{Self, TickInfo};
    use braid_clmm::tick_bitmap;
    use braid_clmm::tick_math;

    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 0;
    /// Output below `min_out`.
    const ESlippage: u64 = 1;
    /// The two coin types of a pool must differ.
    const ESameCoinType: u64 = 2;
    /// An amount that must be positive was zero.
    const EZeroAmount: u64 = 3;
    /// Range endpoints are out of order, misaligned, or out of bounds.
    const EInvalidRange: u64 = 4;
    /// Tick spacing must be positive and divide the tick range.
    const EInvalidTickSpacing: u64 = 5;
    /// No such position.
    const EPositionNotFound: u64 = 6;
    /// The swap walked more boundaries than the loop allows.
    const ETooManyCrossings: u64 = 7;
    /// A price limit was on the wrong side of the current price.
    const EInvalidPriceLimit: u64 = 8;
    /// No pool of that pair lives at the given address. Aptos-only; see the
    /// note on `braid_cpmm::pool::ENoSuchPool`.
    const ENoSuchPool: u64 = 9;

    const MAX_FEE_BPS: u64 = 1000;
    /// Ticks a single swap may cross. Bounds gas; a swap this large should be
    /// split by the caller rather than allowed to run unbounded.
    const MAX_CROSSINGS: u64 = 200;

    struct PositionKey has copy, drop, store {
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
    }

    struct PositionInfo has copy, drop, store {
        liquidity: u128,
        fee_growth_inside_0_last: u256,
        fee_growth_inside_1_last: u256,
        tokens_owed_0: u64,
        tokens_owed_1: u64,
    }

    struct Pool<phantom A, phantom B> has key {
        reserve_a: Coin<A>,
        reserve_b: Coin<B>,
        /// Q64.64. The pool's entire notion of price.
        sqrt_price: u128,
        current_tick: I32,
        /// Liquidity of the ranges spanning the current price. Not a total --
        /// positions outside the price contribute nothing until it reaches them.
        liquidity: u128,
        fee_bps: u64,
        tick_spacing: u32,
        max_liquidity_per_tick: u128,
        fee_growth_global_0: u256,
        fee_growth_global_1: u256,
        /// Keyed by the tick's raw bits, since `I32` is not a table key.
        ticks: Table<u32, TickInfo>,
        /// Keyed by the bitmap word position's raw bits.
        bitmap: Table<u32, u256>,
        positions: Table<PositionKey, PositionInfo>,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    #[event]
    struct PoolCreated has drop, store {
        pool_id: address,
        sqrt_price: u128,
        tick: u32,
        fee_bps: u64,
        tick_spacing: u32,
    }

    #[event]
    struct LiquidityChanged has drop, store {
        pool_id: address,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        liquidity_delta: u128,
        is_add: bool,
        amount_0: u64,
        amount_1: u64,
    }

    #[event]
    struct Swapped has drop, store {
        pool_id: address,
        a_to_b: bool,
        amount_in: u64,
        amount_out: u64,
        fee_paid: u64,
        sqrt_price: u128,
        tick: u32,
        liquidity: u128,
    }

    #[event]
    struct FeesCollected has drop, store {
        pool_id: address,
        owner: address,
        amount_0: u64,
        amount_1: u64,
    }

    // ------------------------------------------------------------------ //
    // Creation                                                           //
    // ------------------------------------------------------------------ //

    /// Create an empty pool at a given price. Returns its address.
    ///
    /// No deposit: a concentrated pool has nothing to hold until a position is
    /// opened. The initial price is simply asserted by whoever creates it, the
    /// same way a constant-product pool's seed ratio is.
    public fun create_pool<A, B>(
        initial_sqrt_price: u128,
        fee_bps: u64,
        tick_spacing: u32,
    ): address {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(tick_spacing > 0, EInvalidTickSpacing);
        assert!(type_info::type_of<A>() != type_info::type_of<B>(), ESameCoinType);

        let tick = tick_math::tick_at_sqrt_price(initial_sqrt_price);

        // The stand-in for `transfer::share_object`: an object owned by the
        // package address, which has no signer after publication, with ungated
        // transfer switched off so no one can move it.
        let ctor = object::create_sticky_object(@braid_clmm);
        let pool_signer = object::generate_signer(&ctor);
        let pool_addr = object::address_from_constructor_ref(&ctor);
        object::disable_ungated_transfer(&object::generate_transfer_ref(&ctor));

        move_to(&pool_signer, Pool<A, B> {
            reserve_a: coin::zero<A>(),
            reserve_b: coin::zero<B>(),
            sqrt_price: initial_sqrt_price,
            current_tick: tick,
            liquidity: 0,
            fee_bps,
            tick_spacing,
            max_liquidity_per_tick: tick::max_liquidity_per_tick(tick_spacing),
            fee_growth_global_0: 0,
            fee_growth_global_1: 0,
            ticks: table::new(),
            bitmap: table::new(),
            positions: table::new(),
        });

        event::emit(PoolCreated {
            pool_id: pool_addr,
            sqrt_price: initial_sqrt_price,
            tick: i32::bits(tick),
            fee_bps,
            tick_spacing,
        });

        pool_addr
    }

    /// `create_pool` for a transaction. An entry function cannot return, so the
    /// address is only recoverable from the `PoolCreated` event -- which is how
    /// a client finds it on Sui too, just via the object id in the effects.
    public entry fun create_pool_entry<A, B>(
        _creator: &signer,
        initial_sqrt_price: u128,
        fee_bps: u64,
        tick_spacing: u32,
    ) {
        create_pool<A, B>(initial_sqrt_price, fee_bps, tick_spacing);
    }

    // ------------------------------------------------------------------ //
    // Tick and bitmap storage                                            //
    // ------------------------------------------------------------------ //

    fun word_at<A, B>(pool: &Pool<A, B>, word_pos: I32): u256 {
        let key = i32::bits(word_pos);
        if (table::contains(&pool.bitmap, key)) {
            *table::borrow(&pool.bitmap, key)
        } else {
            0
        }
    }

    fun flip_tick_bit<A, B>(pool: &mut Pool<A, B>, t: I32) {
        let (word_pos, bit_pos) = tick_bitmap::tick_position(t, pool.tick_spacing);
        let key = i32::bits(word_pos);
        if (!table::contains(&pool.bitmap, key)) {
            table::add(&mut pool.bitmap, key, 0);
        };
        let word = table::borrow_mut(&mut pool.bitmap, key);
        *word = tick_bitmap::flip(*word, bit_pos);
    }

    /// The next initialized tick in one direction, fetching whichever word
    /// holds it. The upward search starts one tick along, which may already be
    /// in the next word -- hence deriving the word from the search origin
    /// rather than from the current tick.
    fun next_tick<A, B>(pool: &Pool<A, B>, from: I32, lte: bool): (I32, bool) {
        let compressed = tick_bitmap::compress(from, pool.tick_spacing);
        let origin = if (lte) { compressed } else { i32::add(compressed, i32::from_u32(1)) };
        let (word_pos, _) = tick_bitmap::position(origin);
        tick_bitmap::next_initialized_tick_within_word(
            word_at(pool, word_pos),
            from,
            pool.tick_spacing,
            lte,
        )
    }

    fun tick_state<A, B>(pool: &Pool<A, B>, t: I32): TickInfo {
        let key = i32::bits(t);
        if (table::contains(&pool.ticks, key)) {
            *table::borrow(&pool.ticks, key)
        } else {
            tick::empty()
        }
    }

    fun put_tick<A, B>(pool: &mut Pool<A, B>, t: I32, info: TickInfo) {
        let key = i32::bits(t);
        if (table::contains(&pool.ticks, key)) {
            *table::borrow_mut(&mut pool.ticks, key) = info;
        } else {
            table::add(&mut pool.ticks, key, info);
        };
    }

    // ------------------------------------------------------------------ //
    // Positions                                                          //
    // ------------------------------------------------------------------ //

    fun check_range<A, B>(pool: &Pool<A, B>, lower: I32, upper: I32) {
        assert!(i32::lt(lower, upper), EInvalidRange);
        assert!(tick_math::is_valid_tick(lower) && tick_math::is_valid_tick(upper), EInvalidRange);
        // Misaligned ticks would share a bitmap bit with a neighbour.
        assert!(i32::abs_u32(lower) % pool.tick_spacing == 0, EInvalidRange);
        assert!(i32::abs_u32(upper) % pool.tick_spacing == 0, EInvalidRange);
    }

    fun growth_inside<A, B>(pool: &Pool<A, B>, lower: I32, upper: I32): (u256, u256) {
        let lo = tick_state(pool, lower);
        let hi = tick_state(pool, upper);
        let at_or_above_lower = i32::gte(pool.current_tick, lower);
        let below_upper = i32::lt(pool.current_tick, upper);
        (
            fee_math::fee_growth_inside(
                pool.fee_growth_global_0,
                tick::fee_growth_outside_0(&lo),
                tick::fee_growth_outside_0(&hi),
                at_or_above_lower,
                below_upper,
            ),
            fee_math::fee_growth_inside(
                pool.fee_growth_global_1,
                tick::fee_growth_outside_1(&lo),
                tick::fee_growth_outside_1(&hi),
                at_or_above_lower,
                below_upper,
            ),
        )
    }

    /// Apply a liquidity change to a range: update both boundary ticks, the
    /// bitmap, the position record, and the pool's active liquidity if the
    /// range spans the current price.
    ///
    /// Returns the token amounts the change implies. On a deposit these are
    /// rounded up (the caller pays them); on a withdrawal, down.
    fun modify_position<A, B>(
        pool: &mut Pool<A, B>,
        owner: address,
        lower: I32,
        upper: I32,
        liquidity_delta: u128,
        is_add: bool,
    ): (u64, u64) {
        check_range(pool, lower, upper);

        let global_0 = pool.fee_growth_global_0;
        let global_1 = pool.fee_growth_global_1;
        let max_liq = pool.max_liquidity_per_tick;
        let current = pool.current_tick;

        // --- boundary ticks ---
        if (liquidity_delta > 0) {
            let lo = tick_state(pool, lower);
            let flipped_lo = tick::update(
                &mut lo, i32::lte(lower, current), liquidity_delta, is_add, false,
                global_0, global_1, max_liq,
            );
            put_tick(pool, lower, lo);
            if (flipped_lo) flip_tick_bit(pool, lower);

            let hi = tick_state(pool, upper);
            let flipped_hi = tick::update(
                &mut hi, i32::lte(upper, current), liquidity_delta, is_add, true,
                global_0, global_1, max_liq,
            );
            put_tick(pool, upper, hi);
            if (flipped_hi) flip_tick_bit(pool, upper);
        };

        // --- the position itself ---
        let (inside_0, inside_1) = growth_inside(pool, lower, upper);
        let key = PositionKey { owner, tick_lower: i32::bits(lower), tick_upper: i32::bits(upper) };

        if (!table::contains(&pool.positions, key)) {
            table::add(&mut pool.positions, key, PositionInfo {
                liquidity: 0,
                fee_growth_inside_0_last: inside_0,
                fee_growth_inside_1_last: inside_1,
                tokens_owed_0: 0,
                tokens_owed_1: 0,
            });
        };

        let position = table::borrow_mut(&mut pool.positions, key);

        // Settle fees earned since the last touch before changing liquidity --
        // the old liquidity is what earned them.
        let owed_0 = fee_math::fees_owed(position.liquidity, inside_0, position.fee_growth_inside_0_last);
        let owed_1 = fee_math::fees_owed(position.liquidity, inside_1, position.fee_growth_inside_1_last);
        position.tokens_owed_0 = position.tokens_owed_0 + owed_0;
        position.tokens_owed_1 = position.tokens_owed_1 + owed_1;
        position.fee_growth_inside_0_last = inside_0;
        position.fee_growth_inside_1_last = inside_1;
        position.liquidity = liquidity_math::add_delta(position.liquidity, liquidity_delta, is_add);

        // --- amounts, and the pool's active liquidity ---
        let sqrt_lower = tick_math::sqrt_price_at_tick(lower);
        let sqrt_upper = tick_math::sqrt_price_at_tick(upper);
        let (amount_0, amount_1) = liquidity_math::amounts_for_liquidity(
            pool.sqrt_price, sqrt_lower, sqrt_upper, liquidity_delta, is_add,
        );

        if (i32::gte(pool.current_tick, lower) && i32::lt(pool.current_tick, upper)) {
            pool.liquidity = liquidity_math::add_delta(pool.liquidity, liquidity_delta, is_add);
        };

        (amount_0, amount_1)
    }

    /// Open or grow a position. Both coins are consumed and the unused
    /// remainder returned, so a caller need not compute the ratio first.
    public fun add_liquidity<A, B>(
        owner: &signer,
        pool_addr: address,
        tick_lower: I32,
        tick_upper: I32,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
    ): (Coin<A>, Coin<B>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);
        check_range(pool, tick_lower, tick_upper);

        let sqrt_lower = tick_math::sqrt_price_at_tick(tick_lower);
        let sqrt_upper = tick_math::sqrt_price_at_tick(tick_upper);
        let liquidity = liquidity_math::liquidity_for_amounts(
            pool.sqrt_price, sqrt_lower, sqrt_upper,
            coin::value(&coin_a), coin::value(&coin_b),
        );
        assert!(liquidity > 0, EZeroAmount);

        let owner_addr = signer::address_of(owner);
        let (need_0, need_1) =
            modify_position(pool, owner_addr, tick_lower, tick_upper, liquidity, true);

        if (need_0 > 0) {
            coin::merge(&mut pool.reserve_a, coin::extract(&mut coin_a, need_0));
        };
        if (need_1 > 0) {
            coin::merge(&mut pool.reserve_b, coin::extract(&mut coin_b, need_1));
        };

        event::emit(LiquidityChanged {
            pool_id: pool_addr,
            owner: owner_addr,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
            liquidity_delta: liquidity,
            is_add: true,
            amount_0: need_0,
            amount_1: need_1,
        });

        (coin_a, coin_b)
    }

    /// Shrink or close a position. The withdrawn amounts are credited to the
    /// position alongside any fees, and paid out by `collect`.
    public fun remove_liquidity<A, B>(
        owner: &signer,
        pool_addr: address,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
    ) acquires Pool {
        assert!(liquidity > 0, EZeroAmount);
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        let owner_addr = signer::address_of(owner);
        let key = PositionKey {
            owner: owner_addr,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
        };
        assert!(table::contains(&pool.positions, key), EPositionNotFound);

        let (amount_0, amount_1) =
            modify_position(pool, owner_addr, tick_lower, tick_upper, liquidity, false);

        let position = table::borrow_mut(&mut pool.positions, key);
        position.tokens_owed_0 = position.tokens_owed_0 + amount_0;
        position.tokens_owed_1 = position.tokens_owed_1 + amount_1;

        event::emit(LiquidityChanged {
            pool_id: pool_addr,
            owner: owner_addr,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
            liquidity_delta: liquidity,
            is_add: false,
            amount_0,
            amount_1,
        });
    }

    /// Withdraw everything owed to a position -- withdrawn principal and
    /// accrued fees, which are held in the same balance.
    public fun collect<A, B>(
        owner: &signer,
        pool_addr: address,
        tick_lower: I32,
        tick_upper: I32,
    ): (Coin<A>, Coin<B>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);
        let owner_addr = signer::address_of(owner);

        // Touch the position with a zero delta so fees earned since the last
        // update are settled before anything is paid out.
        modify_position(pool, owner_addr, tick_lower, tick_upper, 0, true);

        let key = PositionKey {
            owner: owner_addr,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
        };
        let position = table::borrow_mut(&mut pool.positions, key);
        let owed_0 = position.tokens_owed_0;
        let owed_1 = position.tokens_owed_1;
        position.tokens_owed_0 = 0;
        position.tokens_owed_1 = 0;

        event::emit(FeesCollected {
            pool_id: pool_addr, owner: owner_addr, amount_0: owed_0, amount_1: owed_1,
        });

        (
            coin::extract(&mut pool.reserve_a, owed_0),
            coin::extract(&mut pool.reserve_b, owed_1),
        )
    }

    // ------------------------------------------------------------------ //
    // Transaction-callable wrappers                                      //
    // ------------------------------------------------------------------ //
    //
    // `I32` is a struct, and a struct cannot be a transaction argument -- so
    // every entry point that names a tick is unreachable directly. These take
    // the tick as a magnitude and a sign, which are primitives, and rebuild it
    // inside. The restriction is identical on both chains, which is why this
    // section ports across unchanged apart from the coin plumbing.
    //
    // The `I32` versions above stay for Move callers: the router will hold
    // ticks as values and should not have to decompose them.

    fun tick_from(magnitude: u32, is_negative: bool): I32 {
        if (is_negative) { i32::neg_from(magnitude) } else { i32::from_u32(magnitude) }
    }

    public entry fun add_liquidity_at<A, B>(
        owner: &signer,
        pool_addr: address,
        lower_magnitude: u32,
        lower_is_negative: bool,
        upper_magnitude: u32,
        upper_is_negative: bool,
        amount_a: u64,
        amount_b: u64,
    ) acquires Pool {
        let coin_a = coin::withdraw<A>(owner, amount_a);
        let coin_b = coin::withdraw<B>(owner, amount_b);
        let (rest_a, rest_b) = add_liquidity<A, B>(
            owner,
            pool_addr,
            tick_from(lower_magnitude, lower_is_negative),
            tick_from(upper_magnitude, upper_is_negative),
            coin_a,
            coin_b,
        );
        let who = signer::address_of(owner);
        coin::deposit(who, rest_a);
        coin::deposit(who, rest_b);
    }

    public entry fun remove_liquidity_at<A, B>(
        owner: &signer,
        pool_addr: address,
        lower_magnitude: u32,
        lower_is_negative: bool,
        upper_magnitude: u32,
        upper_is_negative: bool,
        liquidity: u128,
    ) acquires Pool {
        remove_liquidity<A, B>(
            owner,
            pool_addr,
            tick_from(lower_magnitude, lower_is_negative),
            tick_from(upper_magnitude, upper_is_negative),
            liquidity,
        )
    }

    public entry fun collect_at<A, B>(
        owner: &signer,
        pool_addr: address,
        lower_magnitude: u32,
        lower_is_negative: bool,
        upper_magnitude: u32,
        upper_is_negative: bool,
    ) acquires Pool {
        let (coin_a, coin_b) = collect<A, B>(
            owner,
            pool_addr,
            tick_from(lower_magnitude, lower_is_negative),
            tick_from(upper_magnitude, upper_is_negative),
        );
        let who = signer::address_of(owner);
        coin::deposit(who, coin_a);
        coin::deposit(who, coin_b);
    }

    #[view]
    /// The current tick as `(magnitude, is_negative)`, for off-chain readers
    /// that cannot decode `I32`.
    public fun current_tick_parts<A, B>(pool_addr: address): (u32, bool) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        (i32::abs_u32(pool.current_tick), i32::is_neg(pool.current_tick))
    }

    // ------------------------------------------------------------------ //
    // Swapping                                                           //
    // ------------------------------------------------------------------ //

    /// Sell A for B. The price falls.
    ///
    /// Returns `(output, unspent input)`. A swap can stop early -- at the price
    /// limit, or where liquidity runs out -- so the leftover is handed back
    /// rather than deposited, which keeps the call composable for a Move caller.
    public fun swap_a_for_b<A, B>(
        pool_addr: address,
        coin_in: Coin<A>,
        min_out: u64,
        sqrt_price_limit: u128,
    ): (Coin<B>, Coin<A>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        assert!(sqrt_price_limit < pool.sqrt_price, EInvalidPriceLimit);
        assert!(sqrt_price_limit >= tick_math::min_sqrt_price(), EInvalidPriceLimit);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let (spent, out, fee) = run_swap(pool, amount_in, sqrt_price_limit, true);
        assert!(out >= min_out, ESlippage);

        // Whatever the walk did not consume stays with the trader.
        let input = coin_in;
        let taken = coin::extract(&mut input, spent);
        coin::merge(&mut pool.reserve_a, taken);
        let out_coin = coin::extract(&mut pool.reserve_b, out);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: true,
            amount_in: spent,
            amount_out: out,
            fee_paid: fee,
            sqrt_price: pool.sqrt_price,
            tick: i32::bits(pool.current_tick),
            liquidity: pool.liquidity,
        });

        (out_coin, input)
    }

    /// Sell B for A. The price rises.
    ///
    /// Returns `(output, unspent input)`, same as the other direction.
    public fun swap_b_for_a<A, B>(
        pool_addr: address,
        coin_in: Coin<B>,
        min_out: u64,
        sqrt_price_limit: u128,
    ): (Coin<A>, Coin<B>) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global_mut<Pool<A, B>>(pool_addr);

        assert!(sqrt_price_limit > pool.sqrt_price, EInvalidPriceLimit);
        assert!(sqrt_price_limit <= tick_math::max_sqrt_price(), EInvalidPriceLimit);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let (spent, out, fee) = run_swap(pool, amount_in, sqrt_price_limit, false);
        assert!(out >= min_out, ESlippage);

        let input = coin_in;
        let taken = coin::extract(&mut input, spent);
        coin::merge(&mut pool.reserve_b, taken);
        let out_coin = coin::extract(&mut pool.reserve_a, out);

        event::emit(Swapped {
            pool_id: pool_addr,
            a_to_b: false,
            amount_in: spent,
            amount_out: out,
            fee_paid: fee,
            sqrt_price: pool.sqrt_price,
            tick: i32::bits(pool.current_tick),
            liquidity: pool.liquidity,
        });

        (out_coin, input)
    }

    public entry fun swap_a_for_b_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
        sqrt_price_limit: u128,
    ) acquires Pool {
        let coin_in = coin::withdraw<A>(trader, amount_in);
        let (out, rest) = swap_a_for_b<A, B>(pool_addr, coin_in, min_out, sqrt_price_limit);
        let who = signer::address_of(trader);
        coin::deposit(who, out);
        coin::deposit(who, rest);
    }

    public entry fun swap_b_for_a_entry<A, B>(
        trader: &signer,
        pool_addr: address,
        amount_in: u64,
        min_out: u64,
        sqrt_price_limit: u128,
    ) acquires Pool {
        let coin_in = coin::withdraw<B>(trader, amount_in);
        let (out, rest) = swap_b_for_a<A, B>(pool_addr, coin_in, min_out, sqrt_price_limit);
        let who = signer::address_of(trader);
        coin::deposit(who, out);
        coin::deposit(who, rest);
    }

    /// Walk the price toward the limit, crossing ticks as it goes.
    ///
    /// Returns `(input_spent_including_fee, output, fee)`. Stops early when the
    /// input runs out, the limit is reached, or liquidity runs out entirely --
    /// the last of which is a legitimate state, not an error: a range can end
    /// with nothing beyond it.
    fun run_swap<A, B>(
        pool: &mut Pool<A, B>,
        amount_in: u64,
        sqrt_price_limit: u128,
        zero_for_one: bool,
    ): (u64, u64, u64) {
        let remaining = amount_in;
        let total_out: u64 = 0;
        let total_fee: u64 = 0;
        let crossings: u64 = 0;

        while (remaining > 0 && pool.sqrt_price != sqrt_price_limit) {
            assert!(crossings < MAX_CROSSINGS, ETooManyCrossings);
            crossings = crossings + 1;

            if (pool.liquidity == 0) {
                // Nothing to trade against here. A real pool would jump to the
                // next initialized tick; stopping is the conservative choice
                // and leaves the caller their unspent input.
                break
            };

            let (boundary, initialized) = next_tick(pool, pool.current_tick, zero_for_one);

            // Clamp the boundary to the tick range, then to the price limit.
            let clamped = if (i32::lt(boundary, tick_math::min_tick())) {
                tick_math::min_tick()
            } else if (i32::gt(boundary, tick_math::max_tick())) {
                tick_math::max_tick()
            } else {
                boundary
            };
            let boundary_price = tick_math::sqrt_price_at_tick(clamped);
            let target = if (zero_for_one) {
                if (boundary_price < sqrt_price_limit) { sqrt_price_limit } else { boundary_price }
            } else {
                if (boundary_price > sqrt_price_limit) { sqrt_price_limit } else { boundary_price }
            };

            let (next_price, step_in, step_out, step_fee) = swap_math::compute_swap_step(
                pool.sqrt_price, target, pool.liquidity, remaining, pool.fee_bps,
            );

            remaining = remaining - step_in - step_fee;
            total_out = total_out + step_out;
            total_fee = total_fee + step_fee;

            if (step_fee > 0) {
                if (zero_for_one) {
                    pool.fee_growth_global_0 =
                        fee_math::accrue(pool.fee_growth_global_0, step_fee, pool.liquidity);
                } else {
                    pool.fee_growth_global_1 =
                        fee_math::accrue(pool.fee_growth_global_1, step_fee, pool.liquidity);
                };
            };

            pool.sqrt_price = next_price;

            if (next_price == boundary_price && initialized) {
                let global_0 = pool.fee_growth_global_0;
                let global_1 = pool.fee_growth_global_1;
                let info = tick_state(pool, clamped);
                let net = tick::cross(&mut info, global_0, global_1);
                put_tick(pool, clamped, info);

                // The net is oriented for an upward crossing; going down it is
                // the same boundary walked backwards.
                let applied = if (zero_for_one) { i128::neg(net) } else { net };
                let (magnitude, is_add) = i128::to_delta(applied);
                pool.liquidity = liquidity_math::add_delta(pool.liquidity, magnitude, is_add);

                // Below a crossed boundary the current tick is one short of it.
                pool.current_tick = if (zero_for_one) {
                    i32::sub(clamped, i32::from_u32(1))
                } else {
                    clamped
                };
            } else if (next_price != boundary_price) {
                pool.current_tick = tick_math::tick_at_sqrt_price(next_price);
            } else {
                // Reached an uninitialized word boundary; step past it.
                pool.current_tick = if (zero_for_one) {
                    i32::sub(clamped, i32::from_u32(1))
                } else {
                    clamped
                };
            };
        };

        (amount_in - remaining, total_out, total_fee)
    }

    // ------------------------------------------------------------------ //
    // Views                                                              //
    // ------------------------------------------------------------------ //

    #[view]
    public fun sqrt_price<A, B>(pool_addr: address): u128 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).sqrt_price
    }

    /// Not a `#[view]`: `I32` is a struct, so a fullnode cannot render it.
    /// `current_tick_parts` is the readable form.
    public fun current_tick<A, B>(pool_addr: address): I32 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).current_tick
    }

    #[view]
    public fun liquidity<A, B>(pool_addr: address): u128 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).liquidity
    }

    #[view]
    public fun fee_bps<A, B>(pool_addr: address): u64 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).fee_bps
    }

    #[view]
    public fun tick_spacing<A, B>(pool_addr: address): u32 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        borrow_global<Pool<A, B>>(pool_addr).tick_spacing
    }

    #[view]
    public fun reserves<A, B>(pool_addr: address): (u64, u64) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        (coin::value(&pool.reserve_a), coin::value(&pool.reserve_b))
    }

    #[view]
    public fun fee_growth_global<A, B>(pool_addr: address): (u256, u256) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        (pool.fee_growth_global_0, pool.fee_growth_global_1)
    }

    public fun position_liquidity<A, B>(
        pool_addr: address, owner: address, lower: I32, upper: I32,
    ): u128 acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        let key = PositionKey {
            owner, tick_lower: i32::bits(lower), tick_upper: i32::bits(upper),
        };
        if (table::contains(&pool.positions, key)) {
            table::borrow(&pool.positions, key).liquidity
        } else {
            0
        }
    }

    public fun position_owed<A, B>(
        pool_addr: address, owner: address, lower: I32, upper: I32,
    ): (u64, u64) acquires Pool {
        assert_pool_exists<A, B>(pool_addr);
        let pool = borrow_global<Pool<A, B>>(pool_addr);
        let key = PositionKey {
            owner, tick_lower: i32::bits(lower), tick_upper: i32::bits(upper),
        };
        if (table::contains(&pool.positions, key)) {
            let p = table::borrow(&pool.positions, key);
            (p.tokens_owed_0, p.tokens_owed_1)
        } else {
            (0, 0)
        }
    }

    fun assert_pool_exists<A, B>(pool_addr: address) {
        assert!(exists<Pool<A, B>>(pool_addr), ENoSuchPool);
    }
}
