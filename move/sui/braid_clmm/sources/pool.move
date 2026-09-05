/// The concentrated-liquidity pool.
///
/// Unlike the other two venues, a pool here holds no reserves of its own until
/// someone opens a position, and it is created with a *price* rather than a
/// deposit. Liquidity lives in ranges, and only the ranges spanning the current
/// price are active.
///
/// The pool owns three tables: tick state, the bitmap words, and positions. It
/// is the only module in the package that touches Sui types -- everything it
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
module braid_clmm::pool {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::table::{Self, Table};
    use std::type_name;

    use braid_clmm::fee_math;
    use braid_clmm::i128::{Self, I128};
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

    const MAX_FEE_BPS: u64 = 1000;
    /// Ticks a single swap may cross. Bounds gas; a swap this large should be
    /// split by the caller rather than allowed to run unbounded.
    const MAX_CROSSINGS: u64 = 200;

    public struct LP<phantom A, phantom B> has drop {}

    public struct PositionKey has copy, drop, store {
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
    }

    public struct PositionInfo has copy, drop, store {
        liquidity: u128,
        fee_growth_inside_0_last: u256,
        fee_growth_inside_1_last: u256,
        tokens_owed_0: u64,
        tokens_owed_1: u64,
    }

    public struct Pool<phantom A, phantom B> has key, store {
        id: UID,
        reserve_a: Balance<A>,
        reserve_b: Balance<B>,
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

    public struct PoolCreated has copy, drop {
        pool_id: ID,
        sqrt_price: u128,
        tick: u32,
        fee_bps: u64,
        tick_spacing: u32,
    }

    public struct LiquidityChanged has copy, drop {
        pool_id: ID,
        owner: address,
        tick_lower: u32,
        tick_upper: u32,
        liquidity_delta: u128,
        is_add: bool,
        amount_0: u64,
        amount_1: u64,
    }

    public struct Swapped has copy, drop {
        pool_id: ID,
        a_to_b: bool,
        amount_in: u64,
        amount_out: u64,
        fee_paid: u64,
        sqrt_price: u128,
        tick: u32,
        liquidity: u128,
    }

    public struct FeesCollected has copy, drop {
        pool_id: ID,
        owner: address,
        amount_0: u64,
        amount_1: u64,
    }

    // ------------------------------------------------------------------ //
    // Creation                                                           //
    // ------------------------------------------------------------------ //

    /// Create an empty pool at a given price and share it.
    ///
    /// No deposit: a concentrated pool has nothing to hold until a position is
    /// opened. The initial price is simply asserted by whoever creates it, the
    /// same way a constant-product pool's seed ratio is.
    public fun create_pool<A, B>(
        initial_sqrt_price: u128,
        fee_bps: u64,
        tick_spacing: u32,
        ctx: &mut TxContext,
    ) {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(tick_spacing > 0, EInvalidTickSpacing);
        assert!(
            type_name::with_defining_ids<A>() != type_name::with_defining_ids<B>(),
            ESameCoinType,
        );

        let tick = tick_math::tick_at_sqrt_price(initial_sqrt_price);

        let pool = Pool<A, B> {
            id: object::new(ctx),
            reserve_a: balance::zero<A>(),
            reserve_b: balance::zero<B>(),
            sqrt_price: initial_sqrt_price,
            current_tick: tick,
            liquidity: 0,
            fee_bps,
            tick_spacing,
            max_liquidity_per_tick: tick::max_liquidity_per_tick(tick_spacing),
            fee_growth_global_0: 0,
            fee_growth_global_1: 0,
            ticks: table::new(ctx),
            bitmap: table::new(ctx),
            positions: table::new(ctx),
        };

        event::emit(PoolCreated {
            pool_id: object::id(&pool),
            sqrt_price: initial_sqrt_price,
            tick: i32::bits(tick),
            fee_bps,
            tick_spacing,
        });

        transfer::share_object(pool);
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
            let mut lo = tick_state(pool, lower);
            let flipped_lo = tick::update(
                &mut lo, i32::lte(lower, current), liquidity_delta, is_add, false,
                global_0, global_1, max_liq,
            );
            put_tick(pool, lower, lo);
            if (flipped_lo) flip_tick_bit(pool, lower);

            let mut hi = tick_state(pool, upper);
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
        pool: &mut Pool<A, B>,
        tick_lower: I32,
        tick_upper: I32,
        mut coin_a: Coin<A>,
        mut coin_b: Coin<B>,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        check_range(pool, tick_lower, tick_upper);

        let sqrt_lower = tick_math::sqrt_price_at_tick(tick_lower);
        let sqrt_upper = tick_math::sqrt_price_at_tick(tick_upper);
        let liquidity = liquidity_math::liquidity_for_amounts(
            pool.sqrt_price, sqrt_lower, sqrt_upper,
            coin::value(&coin_a), coin::value(&coin_b),
        );
        assert!(liquidity > 0, EZeroAmount);

        let owner = ctx.sender();
        let (need_0, need_1) =
            modify_position(pool, owner, tick_lower, tick_upper, liquidity, true);

        if (need_0 > 0) {
            balance::join(&mut pool.reserve_a, balance::split(coin::balance_mut(&mut coin_a), need_0));
        };
        if (need_1 > 0) {
            balance::join(&mut pool.reserve_b, balance::split(coin::balance_mut(&mut coin_b), need_1));
        };

        event::emit(LiquidityChanged {
            pool_id: object::id(pool),
            owner,
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
        pool: &mut Pool<A, B>,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        ctx: &mut TxContext,
    ) {
        assert!(liquidity > 0, EZeroAmount);
        let owner = ctx.sender();
        let key = PositionKey {
            owner,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
        };
        assert!(table::contains(&pool.positions, key), EPositionNotFound);

        let (amount_0, amount_1) =
            modify_position(pool, owner, tick_lower, tick_upper, liquidity, false);

        let position = table::borrow_mut(&mut pool.positions, key);
        position.tokens_owed_0 = position.tokens_owed_0 + amount_0;
        position.tokens_owed_1 = position.tokens_owed_1 + amount_1;

        event::emit(LiquidityChanged {
            pool_id: object::id(pool),
            owner,
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
        pool: &mut Pool<A, B>,
        tick_lower: I32,
        tick_upper: I32,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let owner = ctx.sender();

        // Touch the position with a zero delta so fees earned since the last
        // update are settled before anything is paid out.
        modify_position(pool, owner, tick_lower, tick_upper, 0, true);

        let key = PositionKey {
            owner,
            tick_lower: i32::bits(tick_lower),
            tick_upper: i32::bits(tick_upper),
        };
        let position = table::borrow_mut(&mut pool.positions, key);
        let owed_0 = position.tokens_owed_0;
        let owed_1 = position.tokens_owed_1;
        position.tokens_owed_0 = 0;
        position.tokens_owed_1 = 0;

        event::emit(FeesCollected { pool_id: object::id(pool), owner, amount_0: owed_0, amount_1: owed_1 });

        (
            coin::from_balance(balance::split(&mut pool.reserve_a, owed_0), ctx),
            coin::from_balance(balance::split(&mut pool.reserve_b, owed_1), ctx),
        )
    }

    // ------------------------------------------------------------------ //
    // Swapping                                                           //
    // ------------------------------------------------------------------ //

    /// Sell A for B. The price falls.
    ///
    /// Returns `(output, unspent input)`. A swap can stop early -- at the price
    /// limit, or where liquidity runs out -- so the leftover is handed back
    /// rather than transferred, which keeps the call composable in a PTB.
    public fun swap_a_for_b<A, B>(
        pool: &mut Pool<A, B>,
        coin_in: Coin<A>,
        min_out: u64,
        sqrt_price_limit: u128,
        ctx: &mut TxContext,
    ): (Coin<B>, Coin<A>) {
        assert!(sqrt_price_limit < pool.sqrt_price, EInvalidPriceLimit);
        assert!(sqrt_price_limit >= tick_math::min_sqrt_price(), EInvalidPriceLimit);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let (spent, out, fee) = run_swap(pool, amount_in, sqrt_price_limit, true);
        assert!(out >= min_out, ESlippage);

        // Whatever the walk did not consume stays with the trader.
        let mut input = coin_in;
        let taken = balance::split(coin::balance_mut(&mut input), spent);
        balance::join(&mut pool.reserve_a, taken);
        let out_balance = balance::split(&mut pool.reserve_b, out);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: true,
            amount_in: spent,
            amount_out: out,
            fee_paid: fee,
            sqrt_price: pool.sqrt_price,
            tick: i32::bits(pool.current_tick),
            liquidity: pool.liquidity,
        });

        (coin::from_balance(out_balance, ctx), input)
    }

    /// Sell B for A. The price rises.
    ///
    /// Returns `(output, unspent input)`, same as the other direction.
    public fun swap_b_for_a<A, B>(
        pool: &mut Pool<A, B>,
        coin_in: Coin<B>,
        min_out: u64,
        sqrt_price_limit: u128,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        assert!(sqrt_price_limit > pool.sqrt_price, EInvalidPriceLimit);
        assert!(sqrt_price_limit <= tick_math::max_sqrt_price(), EInvalidPriceLimit);

        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let (spent, out, fee) = run_swap(pool, amount_in, sqrt_price_limit, false);
        assert!(out >= min_out, ESlippage);

        let mut input = coin_in;
        let taken = balance::split(coin::balance_mut(&mut input), spent);
        balance::join(&mut pool.reserve_b, taken);
        let out_balance = balance::split(&mut pool.reserve_a, out);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: false,
            amount_in: spent,
            amount_out: out,
            fee_paid: fee,
            sqrt_price: pool.sqrt_price,
            tick: i32::bits(pool.current_tick),
            liquidity: pool.liquidity,
        });

        (coin::from_balance(out_balance, ctx), input)
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
        let mut remaining = amount_in;
        let mut total_out: u64 = 0;
        let mut total_fee: u64 = 0;
        let mut crossings: u64 = 0;

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
                let mut info = tick_state(pool, clamped);
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

    public fun sqrt_price<A, B>(pool: &Pool<A, B>): u128 { pool.sqrt_price }

    public fun current_tick<A, B>(pool: &Pool<A, B>): I32 { pool.current_tick }

    public fun liquidity<A, B>(pool: &Pool<A, B>): u128 { pool.liquidity }

    public fun fee_bps<A, B>(pool: &Pool<A, B>): u64 { pool.fee_bps }

    public fun tick_spacing<A, B>(pool: &Pool<A, B>): u32 { pool.tick_spacing }

    public fun reserves<A, B>(pool: &Pool<A, B>): (u64, u64) {
        (balance::value(&pool.reserve_a), balance::value(&pool.reserve_b))
    }

    public fun fee_growth_global<A, B>(pool: &Pool<A, B>): (u256, u256) {
        (pool.fee_growth_global_0, pool.fee_growth_global_1)
    }

    public fun position_liquidity<A, B>(
        pool: &Pool<A, B>, owner: address, lower: I32, upper: I32,
    ): u128 {
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
        pool: &Pool<A, B>, owner: address, lower: I32, upper: I32,
    ): (u64, u64) {
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
}
