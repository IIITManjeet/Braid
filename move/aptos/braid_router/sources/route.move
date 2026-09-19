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
/// `Route` has no abilities. It cannot be dropped, stored, copied or moved into
/// global storage, so code that calls `begin` does not compile unless it also
/// hands the route to `finish`. `finish` is where the slippage bound is
/// enforced. There is no way to run the legs and walk away with their output
/// without passing through it.
///
/// That is the whole reason legs pass `min_out = 0` to the venues underneath.
/// A per-leg minimum would be the wrong check: the optimizer may deliberately
/// send a leg somewhere slightly worse because it moves a price less, and only
/// the total means anything.
///
/// # Shape of a route in a transaction
///
/// On Sui the caller assembles the route as a programmable transaction block.
/// Aptos has no PTBs, but it has the older thing they generalise: a transaction
/// can carry a compiled Move *script*, whose `main` calls public functions in
/// sequence. A script is checked by the same bytecode verifier as a module, so a
/// `Route` created in `main` must be consumed before `main` returns -- the
/// guarantee is still the type system's, not this module's control flow. See
/// `scripts/route_a_to_b.move`:
///
///     let r = route::begin<TUSD, TETH>(coin, min_out);
///     route::clob_quote_to_base(&mut r, trader, market, 400_000);
///     route::clmm_a_to_b(&mut r, clmm_pool, 350_000);
///     route::cpmm_a_to_b(&mut r, cpmm_pool, 150_000);
///     route::stable_a_to_b(&mut r, stable_pool, 100_000);
///     let (out, unspent) = route::finish(r);
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
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;

    use braid_cpmm::pool as cpmm;
    use braid_stable::pool as stable;
    use braid_clmm::pool as clmm;
    use braid_clmm::tick_math;
    use braid_clob::market as clob;

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
    ///
    /// `Coin` rather than Sui's `Balance`, which is the same structural
    /// analogue the pools use for their reserves.
    struct Route<phantom In, phantom Out> {
        /// Input not yet spent, including anything a leg handed back.
        input: Coin<In>,
        output: Coin<Out>,
        amount_in: u64,
        min_out: u64,
        legs: u64,
    }

    #[event]
    struct LegExecuted has drop, store {
        venue: u8,
        pool_id: address,
        /// What the venue actually consumed, after any remainder came back.
        amount_in: u64,
        amount_out: u64,
    }

    #[event]
    /// Sui's version records `ctx.sender()`. Here the sender is a field of the
    /// transaction the event is emitted in, and `finish` has no signer to ask.
    struct Routed has drop, store {
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
            input: coin_in,
            output: coin::zero(),
            amount_in,
            min_out,
            legs: 0,
        }
    }

    /// Enforce the bound and release the proceeds. Returns `(output, unspent)`.
    public fun finish<In, Out>(route: Route<In, Out>): (Coin<Out>, Coin<In>) {
        let Route { input, output, amount_in, min_out, legs } = route;
        let amount_out = coin::value(&output);
        assert!(amount_out >= min_out, ESlippage);

        event::emit(Routed {
            amount_in,
            amount_out,
            unspent: coin::value(&input),
            min_out,
            legs,
        });

        (output, input)
    }

    public fun remaining_input<In, Out>(route: &Route<In, Out>): u64 { coin::value(&route.input) }
    public fun output_so_far<In, Out>(route: &Route<In, Out>): u64 { coin::value(&route.output) }
    public fun legs<In, Out>(route: &Route<In, Out>): u64 { route.legs }

    // ------------------------------------------------------------------ //
    // Plumbing shared by every leg                                       //
    // ------------------------------------------------------------------ //

    /// Split `amount` off the route's input. Legs return early on zero before
    /// calling this, so an empty leg never reaches a venue's zero check -- or
    /// its existence check, so an unused venue's address can be anything.
    fun take<In, Out>(route: &mut Route<In, Out>, amount: u64): Coin<In> {
        assert!(amount <= coin::value(&route.input), EInsufficientInput);
        coin::extract(&mut route.input, amount)
    }

    /// Bank a leg's output and any input it did not use, and record it.
    fun settle<In, Out>(
        route: &mut Route<In, Out>,
        venue: u8,
        pool_id: address,
        given: u64,
        out: Coin<Out>,
        unspent: Coin<In>,
    ) {
        let amount_out = coin::value(&out);
        let returned = coin::value(&unspent);
        coin::merge(&mut route.output, out);
        coin::merge(&mut route.input, unspent);
        route.legs = route.legs + 1;
        event::emit(LegExecuted { venue, pool_id, amount_in: given - returned, amount_out });
    }

    // ------------------------------------------------------------------ //
    // Constant product                                                   //
    // ------------------------------------------------------------------ //

    public fun cpmm_a_to_b<A, B>(route: &mut Route<A, B>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let out = cpmm::swap_a_for_b<A, B>(pool, coin_in, 0);
        settle(route, VENUE_CPMM, pool, amount, out, coin::zero());
    }

    public fun cpmm_b_to_a<A, B>(route: &mut Route<B, A>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let out = cpmm::swap_b_for_a<A, B>(pool, coin_in, 0);
        settle(route, VENUE_CPMM, pool, amount, out, coin::zero());
    }

    // ------------------------------------------------------------------ //
    // StableSwap                                                         //
    // ------------------------------------------------------------------ //

    public fun stable_a_to_b<A, B>(route: &mut Route<A, B>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let out = stable::swap_a_for_b<A, B>(pool, coin_in, 0);
        settle(route, VENUE_STABLE, pool, amount, out, coin::zero());
    }

    public fun stable_b_to_a<A, B>(route: &mut Route<B, A>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let out = stable::swap_b_for_a<A, B>(pool, coin_in, 0);
        settle(route, VENUE_STABLE, pool, amount, out, coin::zero());
    }

    // ------------------------------------------------------------------ //
    // Concentrated liquidity                                             //
    // ------------------------------------------------------------------ //
    //
    // No price limit beyond the tick range itself. The route's `min_out` is
    // the bound; a per-leg limit would only duplicate it less precisely.

    public fun clmm_a_to_b<A, B>(route: &mut Route<A, B>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let (out, unspent) =
            clmm::swap_a_for_b<A, B>(pool, coin_in, 0, tick_math::min_sqrt_price());
        settle(route, VENUE_CLMM, pool, amount, out, unspent);
    }

    public fun clmm_b_to_a<A, B>(route: &mut Route<B, A>, pool: address, amount: u64) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let (out, unspent) =
            clmm::swap_b_for_a<A, B>(pool, coin_in, 0, tick_math::max_sqrt_price());
        settle(route, VENUE_CLMM, pool, amount, out, unspent);
    }

    // ------------------------------------------------------------------ //
    // Order book                                                         //
    // ------------------------------------------------------------------ //
    //
    // The book legs take the trader's signer because the Aptos market does:
    // a taker's fills are attributed to an address, and on Sui that address
    // came from the transaction context rather than an argument.

    /// Sell base into the bids.
    public fun clob_base_to_quote<Base, Quote>(
        route: &mut Route<Base, Quote>,
        taker: &signer,
        market: address,
        amount: u64,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let (out, unspent) = clob::swap_base_for_quote<Base, Quote>(taker, market, coin_in, 0);
        settle(route, VENUE_CLOB, market, amount, out, unspent);
    }

    /// Buy base from the asks.
    public fun clob_quote_to_base<Base, Quote>(
        route: &mut Route<Quote, Base>,
        taker: &signer,
        market: address,
        amount: u64,
    ) {
        if (amount == 0) return;
        let coin_in = take(route, amount);
        let (out, unspent) = clob::swap_quote_for_base<Base, Quote>(taker, market, coin_in, 0);
        settle(route, VENUE_CLOB, market, amount, out, unspent);
    }
}
