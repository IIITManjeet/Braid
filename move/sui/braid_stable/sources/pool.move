/// The StableSwap pool: two reserves, an amplification coefficient, and the
/// supply of its own LP token.
///
/// Same division of labour as `braid_cpmm::pool` -- all curve math lives in
/// `stable_math`, and this module only moves `Balance`s and asserts what the
/// math cannot assert for itself: slippage bounds, and that `D` never falls.
///
/// One deliberate difference from the CPMM pool. There, `add_liquidity` takes
/// both coins, computes the on-ratio pair, and hands back the change, because
/// depositing off-ratio into a constant-product pool is simply a donation.
/// Here, off-ratio deposits are a supported operation -- you may deposit
/// entirely into one side -- and are priced by the imbalance fee instead. So
/// this `add_liquidity` consumes both coins whole and returns no change.
module braid_stable::pool {
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};
    use sui::event;
    use std::type_name;

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

    // ------------------------------------------------------------------ //
    // Types                                                              //
    // ------------------------------------------------------------------ //

    /// The LP token for the stable `(A, B)` pool. Its own minting witness.
    public struct SLP<phantom A, phantom B> has drop {}

    public struct StablePool<phantom A, phantom B> has key, store {
        id: UID,
        reserve_a: Balance<A>,
        reserve_b: Balance<B>,
        lp_supply: Supply<SLP<A, B>>,
        /// `A * A_PRECISION`. Fixed at creation.
        ///
        /// Curve ramps this over time so a change cannot be sandwiched; that is
        /// a governance feature and this pool has no governance, so it is
        /// immutable instead. Immutable is the safe end of that trade.
        amp: u64,
        /// Swap fee in basis points, charged on the output.
        fee_bps: u64,
        /// Locked forever, so supply never returns to zero.
        locked_lp: Balance<SLP<A, B>>,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    public struct StablePoolCreated has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        amp: u64,
        fee_bps: u64,
    }

    public struct LiquidityAdded has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        lp_minted: u64,
        /// Imbalance fee withheld on each side. Zero for an on-ratio deposit.
        imbalance_fee_a: u64,
        imbalance_fee_b: u64,
    }

    public struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        lp_burned: u64,
    }

    public struct Swapped has copy, drop {
        pool_id: ID,
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

    /// Seed a new stable pool and share it. Returns the creator's LP.
    ///
    /// Unlike the CPMM, the seed deposit should be close to on-ratio: `D` is
    /// computed from whatever is deposited, and seeding a "stable" pool badly
    /// skewed just means the first trader arbitrages it back.
    public fun create_pool<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        amp: u64,
        fee_bps: u64,
        ctx: &mut TxContext,
    ): Coin<SLP<A, B>> {
        stable_math::assert_valid_amp(amp);
        assert!(fee_bps <= stable_math::max_fee_bps(), EInvalidFee);
        assert!(type_name::with_defining_ids<A>() != type_name::with_defining_ids<B>(), ESameCoinType);

        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 && amount_b > 0, EZeroAmount);

        // Shares are denominated in D, so a fresh share is worth exactly 1.0.
        let total_lp = stable_math::initial_lp(amount_a, amount_b, amp);
        let min_lp = stable_math::minimum_liquidity();
        assert!(total_lp > min_lp, EInsufficientLiquidity);

        let mut lp_supply = balance::create_supply(SLP<A, B> {});
        let locked_lp = balance::increase_supply(&mut lp_supply, min_lp);
        let user_lp = balance::increase_supply(&mut lp_supply, total_lp - min_lp);

        let pool = StablePool<A, B> {
            id: object::new(ctx),
            reserve_a: coin::into_balance(coin_a),
            reserve_b: coin::into_balance(coin_b),
            lp_supply,
            amp,
            fee_bps,
            locked_lp,
        };

        event::emit(StablePoolCreated {
            pool_id: object::id(&pool),
            amount_a,
            amount_b,
            amp,
            fee_bps,
        });

        transfer::share_object(pool);
        coin::from_balance(user_lp, ctx)
    }

    /// `create_pool`, with the LP sent to the sender.
    #[allow(lint(self_transfer))]
    public fun create_pool_entry<A, B>(
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        amp: u64,
        fee_bps: u64,
        ctx: &mut TxContext,
    ) {
        let lp = create_pool(coin_a, coin_b, amp, fee_bps, ctx);
        transfer::public_transfer(lp, ctx.sender());
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
        pool: &mut StablePool<A, B>,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        min_lp_out: u64,
        ctx: &mut TxContext,
    ): Coin<SLP<A, B>> {
        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        assert!(amount_a > 0 || amount_b > 0, EZeroAmount);

        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);

        let (minted, fee_a, fee_b) = stable_math::lp_for_deposit(
            amount_a,
            amount_b,
            reserve_a,
            reserve_b,
            balance::supply_value(&pool.lp_supply),
            pool.amp,
            pool.fee_bps,
        );
        assert!(minted >= min_lp_out, ESlippage);

        // The full deposit lands in the reserves; the fee is expressed by
        // minting fewer shares than the deposit would otherwise be worth.
        balance::join(&mut pool.reserve_a, coin::into_balance(coin_a));
        balance::join(&mut pool.reserve_b, coin::into_balance(coin_b));
        let lp = balance::increase_supply(&mut pool.lp_supply, minted);

        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            lp_minted: minted,
            imbalance_fee_a: fee_a,
            imbalance_fee_b: fee_b,
        });

        coin::from_balance(lp, ctx)
    }

    /// Burn LP for a proportional slice of both reserves. No fee: a
    /// proportional exit does not move the pool's balance.
    public fun remove_liquidity<A, B>(
        pool: &mut StablePool<A, B>,
        lp: Coin<SLP<A, B>>,
        min_a: u64,
        min_b: u64,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let lp_amount = coin::value(&lp);
        assert!(lp_amount > 0, EZeroAmount);

        let (out_a, out_b) = stable_math::withdraw_amounts(
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

    public fun swap_a_for_b<A, B>(
        pool: &mut StablePool<A, B>,
        coin_in: Coin<A>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<B> {
        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);
        let d_before = stable_math::get_d(reserve_a, reserve_b, pool.amp);

        let amount_out =
            stable_math::amount_out(amount_in, reserve_a, reserve_b, pool.amp, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        balance::join(&mut pool.reserve_a, coin::into_balance(coin_in));
        let out = balance::split(&mut pool.reserve_b, amount_out);

        let after_a = balance::value(&pool.reserve_a);
        let after_b = balance::value(&pool.reserve_b);
        let d_after = stable_math::get_d(after_a, after_b, pool.amp);
        assert!(d_after >= d_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: true,
            amount_in,
            amount_out,
            reserve_a: after_a,
            reserve_b: after_b,
            invariant_d: d_after,
        });

        coin::from_balance(out, ctx)
    }

    public fun swap_b_for_a<A, B>(
        pool: &mut StablePool<A, B>,
        coin_in: Coin<B>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<A> {
        let amount_in = coin::value(&coin_in);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_a = balance::value(&pool.reserve_a);
        let reserve_b = balance::value(&pool.reserve_b);
        let d_before = stable_math::get_d(reserve_a, reserve_b, pool.amp);

        let amount_out =
            stable_math::amount_out(amount_in, reserve_b, reserve_a, pool.amp, pool.fee_bps);
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out >= min_out, ESlippage);

        balance::join(&mut pool.reserve_b, coin::into_balance(coin_in));
        let out = balance::split(&mut pool.reserve_a, amount_out);

        let after_a = balance::value(&pool.reserve_a);
        let after_b = balance::value(&pool.reserve_b);
        let d_after = stable_math::get_d(after_a, after_b, pool.amp);
        assert!(d_after >= d_before, EInvariantViolated);

        event::emit(Swapped {
            pool_id: object::id(pool),
            a_to_b: false,
            amount_in,
            amount_out,
            reserve_a: after_a,
            reserve_b: after_b,
            invariant_d: d_after,
        });

        coin::from_balance(out, ctx)
    }

    // ------------------------------------------------------------------ //
    // Views                                                              //
    // ------------------------------------------------------------------ //

    public fun reserves<A, B>(pool: &StablePool<A, B>): (u64, u64) {
        (balance::value(&pool.reserve_a), balance::value(&pool.reserve_b))
    }

    public fun amp<A, B>(pool: &StablePool<A, B>): u64 { pool.amp }

    public fun fee_bps<A, B>(pool: &StablePool<A, B>): u64 { pool.fee_bps }

    public fun lp_supply_value<A, B>(pool: &StablePool<A, B>): u64 {
        balance::supply_value(&pool.lp_supply)
    }

    public fun quote_a_for_b<A, B>(pool: &StablePool<A, B>, amount_in: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        stable_math::amount_out(amount_in, reserve_a, reserve_b, pool.amp, pool.fee_bps)
    }

    public fun quote_b_for_a<A, B>(pool: &StablePool<A, B>, amount_in: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        stable_math::amount_out(amount_in, reserve_b, reserve_a, pool.amp, pool.fee_bps)
    }

    public fun quote_in_for_b<A, B>(pool: &StablePool<A, B>, amount_out: u64): u64 {
        let (reserve_a, reserve_b) = reserves(pool);
        stable_math::amount_in(amount_out, reserve_a, reserve_b, pool.amp, pool.fee_bps)
    }

    /// The pool's invariant. The router compares this across venues.
    public fun invariant_d<A, B>(pool: &StablePool<A, B>): u128 {
        let (reserve_a, reserve_b) = reserves(pool);
        stable_math::get_d(reserve_a, reserve_b, pool.amp)
    }

    /// `D / supply` as Q64.64 -- the LP share price. Starts at 1.0, only rises.
    public fun virtual_price<A, B>(pool: &StablePool<A, B>): u128 {
        let (reserve_a, reserve_b) = reserves(pool);
        stable_math::virtual_price(
            reserve_a,
            reserve_b,
            balance::supply_value(&pool.lp_supply),
            pool.amp,
        )
    }
}
