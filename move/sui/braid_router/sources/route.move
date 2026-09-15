/// Atomic execution of one order split across the four venues.
///
/// The router does not decide the split. Finding it means quoting every venue
/// at many sizes and equalising their marginal prices, which is cheap in Rust
/// and ruinous in gas. The chain's job is narrower and is the part that has to
/// be trusted: take the input, spend exactly the amounts the route names at
/// exactly the venues it names, and refuse to finish unless the combined output
/// clears the caller's minimum.
///
/// # A route is a hot potato
///
/// `Route` has no abilities. It cannot be dropped, stored, copied or
/// transferred, so a transaction that calls `begin` does not type-check -- and
/// a PTB does not execute -- unless the same transaction hands the route to
/// `finish`. `finish` is where the slippage bound is enforced. There is no way
/// to run the legs and walk away with their output without passing through it.
///
/// That is the whole reason legs pass `min_out = 0` to the venues underneath.
/// A per-leg minimum would be the wrong check: the optimizer may deliberately
/// send a leg somewhere slightly worse because it moves a price less, and only
/// the total means anything.
///
/// # Shape of a route in a PTB
///
///     begin<TUSD, TETH>(coin, min_out)                    -> route
///     clob_quote_to_base(&mut route, market, 400_000)
///     clmm_a_to_b(&mut route, clmm_pool, 350_000)
///     cpmm_a_to_b(&mut route, cpmm_pool, 150_000)
///     stable_a_to_b(&mut route, stable_pool, 100_000)
///     finish(route)                                       -> (out, unspent)
///
/// Each leg names a direction because each venue fixes its own type order:
/// `Pool<A, B>` sells A for B one way and B for A the other, and a CLOB market
/// is `Market<Base, Quote>`. The route's `<In, Out>` pins which one applies, so
/// a leg pointed the wrong way is a type error rather than a runtime surprise.
///
/// Legs that cannot spend all they are given -- a concentrated pool running out
/// of liquidity, a book running out of depth or rounding to whole lots -- put
/// the remainder back, and `finish` returns it.
module braid_router::route {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;

    use braid_cpmm::pool::{Self as cpmm, Pool as CpmmPool};
    use braid_stable::pool::{Self as stable, StablePool};
    use braid_clmm::pool::{Self as clmm, Pool as ClmmPool};
    use braid_clmm::tick_math;
    use braid_clob::market::{Self as clob, Market};

    /// Combined output below `min_out`.
    const ESlippage: u64 = 0;
    /// A leg asked to spend more input than the route still holds.
    const EInsufficientInput: u64 = 1;

    const VENUE_CPMM: u8 = 0;
    const VENUE_STABLE: u8 = 1;
    const VENUE_CLMM: u8 = 2;
    const VENUE_CLOB: u8 = 3;

    public fun venue_cpmm(): u8 { VENUE_CPMM }
    public fun venue_stable(): u8 { VENUE_STABLE }
    public fun venue_clmm(): u8 { VENUE_CLMM }
    public fun venue_clob(): u8 { VENUE_CLOB }

    /// An order in flight. No abilities: see the module docs.
    public struct Route<phantom In, phantom Out> {
        /// Input not yet spent, including anything a leg handed back.
        input: Balance<In>,
        output: Balance<Out>,
        amount_in: u64,
        min_out: u64,
        legs: u64,
    }

    public struct LegExecuted has copy, drop {
        venue: u8,
        pool_id: ID,
        /// What the venue actually consumed, after any remainder came back.
        amount_in: u64,
        amount_out: u64,
    }

    public struct Routed has copy, drop {
        sender: address,
        amount_in: u64,
        amount_out: u64,
        unspent: u64,
        min_out: u64,
        legs: u64,
    }

    // ------------------------------------------------------------------ //
    // Opening and closing                                                //
    // ------------------------------------------------------------------ //

    public fun begin<In, Out>(coin_in: Coin<In>, min_out: u64): Route<In, Out> {
        let amount_in = coin::value(&coin_in);
        Route {
            input: coin::into_balance(coin_in),
            output: balance::zero(),
            amount_in,
            min_out,
            legs: 0,
        }
    }

    /// Enforce the bound and release the proceeds. Returns `(output, unspent)`.
    public fun finish<In, Out>(route: Route<In, Out>, ctx: &mut TxContext): (Coin<Out>, Coin<In>) {
        let Route { input, output, amount_in, min_out, legs } = route;
        let amount_out = balance::value(&output);
        assert!(amount_out >= min_out, ESlippage);

        event::emit(Routed {
            sender: ctx.sender(),
            amount_in,
            amount_out,
            unspent: balance::value(&input),
            min_out,
            legs,
        });

        (coin::from_balance(output, ctx), coin::from_balance(input, ctx))
    }

    public fun remaining_input<In, Out>(route: &Route<In, Out>): u64 { balance::value(&route.input) }
    public fun output_so_far<In, Out>(route: &Route<In, Out>): u64 { balance::value(&route.output) }
    public fun legs<In, Out>(route: &Route<In, Out>): u64 { route.legs }

    // ------------------------------------------------------------------ //
    // Plumbing shared by every leg                                       //
    // ------------------------------------------------------------------ //

    /// Split `amount` off the route's input as a coin. Legs return early on
    /// zero before calling this, so an empty leg never reaches a venue's zero
    /// check.
    fun take<In, Out>(route: &mut Route<In, Out>, amount: u64, ctx: &mut TxContext): Coin<In> {
        assert!(amount <= balance::value(&route.input), EInsufficientInput);
        coin::from_balance(balance::split(&mut route.input, amount), ctx)
    }

    /// Bank a leg's output and any input it did not use, and record it.
    fun settle<In, Out>(
        route: &mut Route<In, Out>,
        venue: u8,
        pool_id: ID,
        given: u64,
        out: Coin<Out>,
        unspent: Coin<In>,
    ) {
        let amount_out = coin::value(&out);
        let returned = coin::value(&unspent);
        balance::join(&mut route.output, coin::into_balance(out));
        balance::join(&mut route.input, coin::into_balance(unspent));
        route.legs = route.legs + 1;
        event::emit(LegExecuted { venue, pool_id, amount_in: given - returned, amount_out });
    }

    // ------------------------------------------------------------------ //
    // Constant product                                                   //
    // ------------------------------------------------------------------ //

    public fun cpmm_a_to_b<A, B>(
        route: &mut Route<A, B>,
        pool: &mut CpmmPool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let out = cpmm::swap_a_for_b(pool, coin_in, 0, ctx);
        settle(route, VENUE_CPMM, object::id(pool), amount, out, coin::zero(ctx));
    }

    public fun cpmm_b_to_a<A, B>(
        route: &mut Route<B, A>,
        pool: &mut CpmmPool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let out = cpmm::swap_b_for_a(pool, coin_in, 0, ctx);
        settle(route, VENUE_CPMM, object::id(pool), amount, out, coin::zero(ctx));
    }

    // ------------------------------------------------------------------ //
    // StableSwap                                                         //
    // ------------------------------------------------------------------ //

    public fun stable_a_to_b<A, B>(
        route: &mut Route<A, B>,
        pool: &mut StablePool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let out = stable::swap_a_for_b(pool, coin_in, 0, ctx);
        settle(route, VENUE_STABLE, object::id(pool), amount, out, coin::zero(ctx));
    }

    public fun stable_b_to_a<A, B>(
        route: &mut Route<B, A>,
        pool: &mut StablePool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let out = stable::swap_b_for_a(pool, coin_in, 0, ctx);
        settle(route, VENUE_STABLE, object::id(pool), amount, out, coin::zero(ctx));
    }

    // ------------------------------------------------------------------ //
    // Concentrated liquidity                                             //
    // ------------------------------------------------------------------ //
    //
    // No price limit beyond the tick range itself. The route's `min_out` is
    // the bound; a per-leg limit would only duplicate it less precisely.

    public fun clmm_a_to_b<A, B>(
        route: &mut Route<A, B>,
        pool: &mut ClmmPool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let (out, unspent) =
            clmm::swap_a_for_b(pool, coin_in, 0, tick_math::min_sqrt_price(), ctx);
        settle(route, VENUE_CLMM, object::id(pool), amount, out, unspent);
    }

    public fun clmm_b_to_a<A, B>(
        route: &mut Route<B, A>,
        pool: &mut ClmmPool<A, B>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let (out, unspent) =
            clmm::swap_b_for_a(pool, coin_in, 0, tick_math::max_sqrt_price(), ctx);
        settle(route, VENUE_CLMM, object::id(pool), amount, out, unspent);
    }

    // ------------------------------------------------------------------ //
    // Order book                                                         //
    // ------------------------------------------------------------------ //

    /// Sell base into the bids.
    public fun clob_base_to_quote<Base, Quote>(
        route: &mut Route<Base, Quote>,
        market: &mut Market<Base, Quote>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let (out, unspent) = clob::swap_base_for_quote(market, coin_in, 0, ctx);
        settle(route, VENUE_CLOB, object::id(market), amount, out, unspent);
    }

    /// Buy base from the asks.
    public fun clob_quote_to_base<Base, Quote>(
        route: &mut Route<Quote, Base>,
        market: &mut Market<Base, Quote>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount, ctx);
        let (out, unspent) = clob::swap_quote_for_base(market, coin_in, 0, ctx);
        settle(route, VENUE_CLOB, object::id(market), amount, out, unspent);
    }
}
