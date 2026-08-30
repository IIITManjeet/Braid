/// The constant-product pool: a shared object holding two reserves and the
/// supply of its own LP token.
///
/// All pricing lives in `cpmm_math`. This module is only custody and
/// bookkeeping -- it moves `Balance`s around, mints and burns LP, and asserts
/// the two things the math cannot assert for itself:
///
///   1. the caller got at least the output they asked for (slippage), and
///   2. `k` did not decrease (the invariant).
///
/// The second check is redundant if `cpmm_math` is correct. It is here anyway,
/// because it is the difference between a pricing bug being a failed
/// transaction and a pricing bug being a drained pool.
module braid_cpmm::pool {
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};
    use sui::event;
    use std::type_name;

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

    // ------------------------------------------------------------------ //
    // Types                                                              //
    // ------------------------------------------------------------------ //

    /// The LP token for the `(A, B)` pool.
    ///
    /// It is its own witness: `balance::create_supply` consumes one value of a
    /// `drop` type and hands back the sole `Supply` for it, so only this module
    /// can ever mint. There is no `TreasuryCap` to lose.
    public struct LP<phantom A, phantom B> has drop {}

    public struct Pool<phantom A, phantom B> has key, store {
        id: UID,
        reserve_a: Balance<A>,
        reserve_b: Balance<B>,
        lp_supply: Supply<LP<A, B>>,
        /// Swap fee in basis points, fixed at creation.
        fee_bps: u64,
        /// The `MINIMUM_LIQUIDITY` shares minted at creation and held here
        /// forever, so `lp_supply` can never return to zero while the pool
        /// holds reserves. See `cpmm_math::minimum_liquidity`.
        locked_lp: Balance<LP<A, B>>,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    public struct PoolCreated has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        fee_bps: u64,
    }

    public struct LiquidityAdded has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        lp_minted: u64,
    }

    public struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        lp_burned: u64,
    }

    public struct Swapped has copy, drop {
        pool_id: ID,
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

    /// Seed a new pool and share it. Returns the creator's LP.
    ///
    /// The initial deposit sets the price; there is no oracle and no check on
    /// it, which is correct -- a pool seeded at a wrong price is arbitraged to
    /// the right one, at the seeder's expense.
    public fun create_pool<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        fee_bps: u64,
        ctx: &mut TxContext,
    ): Coin<LP<A, B>> {
        assert!(fee_bps <= cpmm_math::max_fee_bps(), EInvalidFee);
        // A Pool<A, A> would let a swap read and write the same reserve.
        assert!(type_name::with_defining_ids<A>() != type_name::with_defining_ids<B>(), ESameCoinType);

        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 && amount_b > 0, EZeroAmount);

        // Aborts if `sqrt(a * b)` does not clear MINIMUM_LIQUIDITY.
        let user_lp = cpmm_math::initial_lp(amount_a, amount_b);

        let mut lp_supply = balance::create_supply(LP<A, B> {});
        let locked_lp = balance::increase_supply(
            &mut lp_supply,
            cpmm_math::minimum_liquidity(),
        );
        let user_lp_balance = balance::increase_supply(&mut lp_supply, user_lp);

        let pool = Pool<A, B> {
            id: object::new(ctx),
            reserve_a: coin::into_balance(coin_a),
            reserve_b: coin::into_balance(coin_b),
            lp_supply,
            fee_bps,
            locked_lp,
        };

        event::emit(PoolCreated {
            pool_id: object::id(&pool),
            amount_a,
            amount_b,
            fee_bps,
        });

        transfer::share_object(pool);
        coin::from_balance(user_lp_balance, ctx)
    }

    /// `create_pool`, with the LP sent to the sender. The form a wallet calls.
    ///
    /// The self-transfer lint is the whole point of this wrapper: `create_pool`
    /// returns the LP for a PTB to compose with, and this is the non-composable
    /// convenience form for a plain `sui client call`.
    #[allow(lint(self_transfer))]
    public fun create_pool_entry<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        fee_bps: u64,
        ctx: &mut TxContext,
    ) {
        let lp = create_pool(coin_a, coin_b, fee_bps, ctx);
        transfer::public_transfer(lp, ctx.sender());
    }

    // ------------------------------------------------------------------ //
    // Liquidity                                                          //
    // ------------------------------------------------------------------ //

    /// Deposit against the current ratio.
    ///
    /// Takes both coins by value and returns the unused remainder of each,
    /// rather than requiring the caller to compute the ratio first. Returning
    /// the change instead of aborting on a mismatch is what makes this usable
    /// in a PTB where the reserves may have moved since the client quoted.
    public fun add_liquidity<A, B>(
        pool: &mut Pool<A, B>,
        mut coin_a: Coin<A>,
        mut coin_b: Coin<B>,
        min_lp_out: u64,
        ctx: &mut TxContext,
    ): (Coin<LP<A, B>>, Coin<A>, Coin<B>) {
        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);
        let supply = balance::supply_value(&pool.lp_supply);

        // Both returns are bounded by their `_desired` input, so the splits
        // below always have the funds.
        let (use_a, use_b) = cpmm_math::optimal_deposit(
            coin::value(&coin_a),
            coin::value(&coin_b),
            reserve_a,
            reserve_b,
        );
        let minted = cpmm_math::lp_for_deposit(use_a, use_b, reserve_a, reserve_b, supply);
        assert!(minted >= min_lp_out, ESlippage);

        balance::join(
            &mut pool.reserve_a,
            balance::split(coin::balance_mut(&mut coin_a), use_a),
        );
        balance::join(
            &mut pool.reserve_b,
            balance::split(coin::balance_mut(&mut coin_b), use_b),
        );
        let lp = balance::increase_supply(&mut pool.lp_supply, minted);

        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            amount_a: use_a,
            amount_b: use_b,
            lp_minted: minted,
        });

        (coin::from_balance(lp, ctx), coin_a, coin_b)
    }

    /// Burn LP and take the proportional share of both reserves.
    public fun remove_liquidity<A, B>(
        pool: &mut Pool<A, B>,
        lp: Coin<LP<A, B>>,
        min_a: u64,
        min_b: u64,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let lp_amount = coin::value(&lp);
        assert!(lp_amount > 0, EZeroAmount);

        let (out_a, out_b) = cpmm_math::withdraw_amounts(
            lp_amount,
            balance::value(&pool.reserve_a),
            balance::value(&pool.reserve_b),
            balance::supply_value(&pool.lp_supply),
        );
        assert!(out_a >= min_a && out_b >= min_b, ESlippage);

        balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp));

        event::emit(LiquidityRemoved {
            pool_id: object::id(pool),
            amount_a: out_a,
            amount_b: out_b,
            lp_burned: lp_amount,
        });

        (
            coin::from_balance(balance::split(&mut pool.reserve_a, out_a), ctx),
            coin::from_balance(balance::split(&mut pool.reserve_b, out_b), ctx),
        )
    }

    // ------------------------------------------------------------------ //
    // Swaps                                                              //
    // ------------------------------------------------------------------ //

    /// Sell `coin_in` of A for B, exact-in.
    public fun swap_a_for_b<A, B>(
        pool: &mut Pool<A, B>,
        coin_in: Coin<A>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<B> {
        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);
        let k_before = cpmm_math::k(reserve_a, reserve_b);

        let amount_out = cpmm_math::amount_out(amount_in, reserve_a, reserve_b, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        balance::join(&mut pool.reserve_a, coin::into_balance(coin_in));
        let out = balance::split(&mut pool.reserve_b, amount_out);

        let reserve_a_after = balance::value(&pool.reserve_a);
        let reserve_b_after = balance::value(&pool.reserve_b);
        assert!(cpmm_math::k(reserve_a_after, reserve_b_after) >= k_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: true,
            amount_in,
            amount_out,
            fee_paid: cpmm_math::fee_amount(amount_in, pool.fee_bps),
            reserve_a: reserve_a_after,
            reserve_b: reserve_b_after,
        });

        coin::from_balance(out, ctx)
    }

    /// Sell `coin_in` of B for A, exact-in.
    public fun swap_b_for_a<A, B>(
        pool: &mut Pool<A, B>,
        coin_in: Coin<B>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<A> {
        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);
        let k_before = cpmm_math::k(reserve_a, reserve_b);

        let amount_out = cpmm_math::amount_out(amount_in, reserve_b, reserve_a, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        balance::join(&mut pool.reserve_b, coin::into_balance(coin_in));
        let out = balance::split(&mut pool.reserve_a, amount_out);

        let reserve_a_after = balance::value(&pool.reserve_a);
        let reserve_b_after = balance::value(&pool.reserve_b);
        assert!(cpmm_math::k(reserve_a_after, reserve_b_after) >= k_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: false,
            amount_in,
            amount_out,
            fee_paid: cpmm_math::fee_amount(amount_in, pool.fee_bps),
            reserve_a: reserve_a_after,
            reserve_b: reserve_b_after,
        });

        coin::from_balance(out, ctx)
    }

    // ------------------------------------------------------------------ //
    // Views -- what the router and the Rust replica read                 //
    // ------------------------------------------------------------------ //

    public fun reserves<A, B>(pool: &Pool<A, B>): (u64, u64) {
        (balance::value(&pool.reserve_a), balance::value(&pool.reserve_b))
    }

    public fun fee_bps<A, B>(pool: &Pool<A, B>): u64 { pool.fee_bps }

    public fun lp_supply_value<A, B>(pool: &Pool<A, B>): u64 {
        balance::supply_value(&pool.lp_supply)
    }

    /// Exact-in quote against live reserves. Read-only, for `dev-inspect`.
    public fun quote_a_for_b<A, B>(pool: &Pool<A, B>, amount_in: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        cpmm_math::amount_out(amount_in, reserve_a, reserve_b, pool.fee_bps)
    }

    public fun quote_b_for_a<A, B>(pool: &Pool<A, B>, amount_in: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        cpmm_math::amount_out(amount_in, reserve_b, reserve_a, pool.fee_bps)
    }

    /// Exact-out quote: what `amount_out` of B costs in A.
    public fun quote_in_for_b<A, B>(pool: &Pool<A, B>, amount_out: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        cpmm_math::amount_in(amount_out, reserve_a, reserve_b, pool.fee_bps)
    }

    /// Current `k`. The router compares this across venues.
    public fun invariant_k<A, B>(pool: &Pool<A, B>): u256 {
        let (reserve_a, reserve_b) = reserves(pool);
        cpmm_math::k(reserve_a, reserve_b)
    }
}
