/// The market: an order book with custody.
///
/// `book` matches orders and knows nothing about money. This module wraps it
/// in an object that holds both coins, locks funds behind every resting
/// order, settles every fill, and charges a taker fee.
///
/// # Units, and why nothing here rounds
///
/// A price is quote units per `PRICE_SCALE` base units, so the quote value of a
/// fill is `price * quantity / PRICE_SCALE`. That division is where an order
/// book would normally leak dust: lock a bid's quote rounded one way, release
/// its fills rounded another, and the vault drifts from what it owes.
///
/// It cannot happen here. Every price is a multiple of `tick_size`, every
/// quantity a multiple of `lot_size`, and a market is only created if
/// `tick_size * lot_size` is a multiple of `PRICE_SCALE`. Fills are the minimum
/// of two lot-aligned quantities, so they are lot-aligned too. Every product
/// that reaches the division is therefore exact, and the vault balances to the
/// unit: what a bid locks is precisely the sum of what its fills release.
///
/// The one place rounding remains is the fee, which is taken on the taker's
/// output and rounded up -- against the taker, never against the vault.
///
/// # Settlement
///
/// The taker is paid in the transaction, as coins handed back to the caller.
/// Makers are not: a taker that walks twenty orders would otherwise credit
/// twenty strangers' accounts. Instead each maker's proceeds are credited to a
/// claimable balance, withdrawn whenever they like. Cancelling an order credits
/// its refund the same way, so a market maker cancelling and replacing never
/// moves a coin until they choose to.
///
/// # Swaps
///
/// `swap_base_for_quote` and `swap_quote_for_base` give the book the same
/// exact-in shape as the pools -- coin in, coin out, a minimum, and the unspent
/// input returned -- which is what lets the router treat all four venues alike.
/// `quote_*` answer the same question read-only, and a test holds them to
/// agreeing with execution exactly.
///
/// APTOS PORT of `move/sui/braid_clob/sources/market.move`. The custody model is
/// the one `braid_cpmm::pool` argues; two things are specific to this venue:
///
///   * `MarketCap` is a Sui object held by whoever created the market. Aptos has
///     no free-floating owned values, so the cap is a resource: `create_market`
///     still hands it back by value -- it has no `drop`, so the caller must do
///     something with it -- and the entry wrapper `move_to`s it under the
///     creator. `collect_fees` takes it by reference exactly as Sui does, so the
///     authority is still the value and not an address recorded in the market.
///   * The vaults hold `Coin<Base>`/`Coin<Quote>` rather than `Balance`, for the
///     reason given in `braid_cpmm::pool`: Aptos's `FungibleAsset` has no
///     abilities and cannot be a struct field.
module braid_clob::market {
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;
    use aptos_framework::object;

    use braid_math::full_math;
    use braid_clob::book::{Self, Book};

    /// Taker fee above the permitted maximum.
    const EInvalidFee: u64 = 0;
    /// The two coin types of a market must differ.
    const ESameCoinType: u64 = 1;
    /// Tick or lot size zero, or their product not a multiple of the scale.
    const EInvalidSizes: u64 = 2;
    /// Price zero or not a multiple of the tick size.
    const EPriceNotOnTick: u64 = 3;
    /// Quantity zero or not a multiple of the lot size.
    const EQuantityNotOnLot: u64 = 4;
    /// The payment coin does not cover the fills plus what the order locks.
    const EInsufficientPayment: u64 = 5;
    /// Output below `min_out`.
    const ESlippage: u64 = 6;
    /// No such order.
    const EOrderNotFound: u64 = 7;
    /// The cap belongs to a different market.
    const EWrongMarket: u64 = 8;
    /// A quote value does not fit in a `u64`.
    const EOverflow: u64 = 9;
    /// No market of that pair lives at the given address. Aptos-only; see the
    /// note on `braid_cpmm::pool::ENoSuchPool`.
    const ENoSuchMarket: u64 = 10;

    /// Prices are quote units per this many base units.
    const PRICE_SCALE: u64 = 1_000_000_000;
    const BPS_DENOM: u64 = 10_000;
    /// 1%. A book's fee is a taker charge, not an LP's return, and has no
    /// reason to be large.
    const MAX_FEE_BPS: u64 = 100;
    const MAX_U64: u128 = 18446744073709551615;

    public fun price_scale(): u64 { PRICE_SCALE }
    public fun max_fee_bps(): u64 { MAX_FEE_BPS }

    /// What a maker can withdraw: fill proceeds and cancellation refunds.
    public struct Claim has store, copy, drop {
        base: u64,
        quote: u64,
    }

    public struct Market<phantom Base, phantom Quote> has key {
        book: Book,
        /// Every base unit the market holds for traders: locked behind resting
        /// asks, or claimable. Fees are kept apart, in `base_fees`.
        base_vault: Coin<Base>,
        quote_vault: Coin<Quote>,
        base_fees: Coin<Base>,
        quote_fees: Coin<Quote>,
        /// Held behind resting orders. The rest of each vault is claimable.
        base_locked: u64,
        quote_locked: u64,
        claims: Table<address, Claim>,
        tick_size: u64,
        lot_size: u64,
        taker_fee_bps: u64,
    }

    /// Authority to collect a market's fees.
    ///
    /// `key` so it can be parked under an account, `store` so it can be held
    /// somewhere else instead. No `drop`: losing it must be deliberate.
    public struct MarketCap has key, store {
        market_id: address,
    }

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    #[event]
    public struct MarketCreated has drop, store {
        market_id: address,
        tick_size: u64,
        lot_size: u64,
        taker_fee_bps: u64,
    }

    #[event]
    public struct OrderPlaced has drop, store {
        market_id: address,
        owner: address,
        /// The resting order, or `book::none_id()` if nothing rested.
        order_id: u64,
        is_bid: bool,
        price: u64,
        quantity: u64,
        order_type: u8,
        /// Base filled on placement, and its quote value at the makers' prices.
        filled: u64,
        quote_amount: u64,
        /// Taken from the taker's output: base on a bid, quote on an ask.
        fee: u64,
    }

    #[event]
    public struct OrderFilled has drop, store {
        market_id: address,
        maker_order_id: u64,
        maker: address,
        taker: address,
        taker_is_bid: bool,
        price: u64,
        quantity: u64,
    }

    #[event]
    public struct OrderCanceled has drop, store {
        market_id: address,
        order_id: u64,
        owner: address,
        is_bid: bool,
        price: u64,
        remaining: u64,
    }

    #[event]
    public struct Withdrawn has drop, store {
        market_id: address,
        owner: address,
        base: u64,
        quote: u64,
    }

    // ------------------------------------------------------------------ //
    // Creation                                                           //
    // ------------------------------------------------------------------ //

    /// Create a market. Returns its address and the cap that collects its fees.
    public fun create_market<Base, Quote>(
        tick_size: u64,
        lot_size: u64,
        taker_fee_bps: u64,
    ): (address, MarketCap) {
        assert!(taker_fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(type_info::type_of<Base>() != type_info::type_of<Quote>(), ESameCoinType);
        assert!(tick_size > 0 && lot_size > 0, EInvalidSizes);
        // The condition that makes every quote value exact. See the module docs.
        assert!(
            ((tick_size as u128) * (lot_size as u128)) % (PRICE_SCALE as u128) == 0,
            EInvalidSizes,
        );

        let ctor = object::create_sticky_object(@braid_clob);
        let market_signer = object::generate_signer(&ctor);
        let market_id = object::address_from_constructor_ref(&ctor);
        object::disable_ungated_transfer(&object::generate_transfer_ref(&ctor));

        move_to(&market_signer, Market<Base, Quote> {
            book: book::empty(),
            base_vault: coin::zero(),
            quote_vault: coin::zero(),
            base_fees: coin::zero(),
            quote_fees: coin::zero(),
            base_locked: 0,
            quote_locked: 0,
            claims: table::new(),
            tick_size,
            lot_size,
            taker_fee_bps,
        });

        event::emit(MarketCreated { market_id, tick_size, lot_size, taker_fee_bps });

        (market_id, MarketCap { market_id })
    }

    /// `create_market` for a transaction, parking the cap under the creator.
    ///
    /// Sui's caller transfers the returned cap to themselves; here it is
    /// `move_to`. One cap per account -- a second market from the same address
    /// aborts on the duplicate resource, which is the Aptos storage key showing
    /// through. Use `create_market` from Move if you need more than one.
    public entry fun create_market_entry<Base, Quote>(
        creator: &signer,
        tick_size: u64,
        lot_size: u64,
        taker_fee_bps: u64,
    ) {
        let (_market_id, cap) = create_market<Base, Quote>(tick_size, lot_size, taker_fee_bps);
        move_to(creator, cap);
    }

    // ------------------------------------------------------------------ //
    // Arithmetic                                                         //
    // ------------------------------------------------------------------ //

    /// `price * quantity / PRICE_SCALE`. Exact for aligned inputs; floors
    /// otherwise, which only the read-only budget walk ever relies on.
    fun quote_value(price: u64, quantity: u64): u64 {
        let v = (price as u128) * (quantity as u128) / (PRICE_SCALE as u128);
        assert!(v <= MAX_U64, EOverflow);
        (v as u64)
    }

    /// `ceil(amount * fee_bps / 10000)`. Rounded up so that splitting a trade
    /// into many small ones cannot shrink the fee to nothing.
    fun fee_on<Base, Quote>(market: &Market<Base, Quote>, amount: u64): u64 {
        full_math::mul_div_ceil_u64(amount, market.taker_fee_bps, BPS_DENOM)
    }

    fun check_order<Base, Quote>(market: &Market<Base, Quote>, price: u64, quantity: u64) {
        assert!(price > 0 && price % market.tick_size == 0, EPriceNotOnTick);
        assert!(quantity > 0 && quantity % market.lot_size == 0, EQuantityNotOnLot);
    }

    fun credit<Base, Quote>(market: &mut Market<Base, Quote>, owner: address, base: u64, quote: u64) {
        if (!table::contains(&market.claims, owner)) {
            table::add(&mut market.claims, owner, Claim { base: 0, quote: 0 });
        };
        let claim = table::borrow_mut(&mut market.claims, owner);
        claim.base = claim.base + base;
        claim.quote = claim.quote + quote;
    }

    // ------------------------------------------------------------------ //
    // Placing orders                                                     //
    // ------------------------------------------------------------------ //

    /// Buy base with quote, at `price` or better.
    ///
    /// `payment` must cover what fills, at the makers' prices, plus what a
    /// resting remainder locks at this order's own price. The rest comes back.
    ///
    /// Returns `(base_bought, unspent_quote, resting_order_id)`. The id is
    /// `book::none_id()` when nothing rested.
    public fun place_bid<Base, Quote>(
        taker_signer: &signer,
        market_id: address,
        price: u64,
        quantity: u64,
        order_type: u8,
        payment: Coin<Quote>,
    ): (Coin<Base>, Coin<Quote>, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);
        place_bid_inner(market, market_id, signer::address_of(taker_signer),
            price, quantity, order_type, payment)
    }

    /// The body of `place_bid`, over an already-borrowed market.
    ///
    /// Split out only so the swap entry points below can reach it without a
    /// second `borrow_global_mut` -- Sui needs no equivalent because it already
    /// holds the `&mut Market` its caller passed in.
    fun place_bid_inner<Base, Quote>(
        market: &mut Market<Base, Quote>,
        market_id: address,
        taker: address,
        price: u64,
        quantity: u64,
        order_type: u8,
        payment: Coin<Quote>,
    ): (Coin<Base>, Coin<Quote>, u64) {
        check_order(market, price, quantity);

        let (fills, order_id) =
            book::place_limit_order(&mut market.book, taker, price, quantity, true, order_type);

        let filled = 0;
        let cost = 0;
        let i = 0;
        while (i < fills.length()) {
            let fill = &fills[i];
            let (maker, fill_price, fill_qty) =
                (book::fill_maker(fill), book::fill_price(fill), book::fill_quantity(fill));
            let value = quote_value(fill_price, fill_qty);

            // The ask's locked base goes to the taker; the maker is owed the
            // quote the taker pays for it.
            filled = filled + fill_qty;
            cost = cost + value;
            market.base_locked = market.base_locked - fill_qty;
            credit(market, maker, 0, value);

            event::emit(OrderFilled {
                market_id,
                maker_order_id: book::fill_maker_order(fill),
                maker,
                taker,
                taker_is_bid: true,
                price: fill_price,
                quantity: fill_qty,
            });
            i = i + 1;
        };

        // A remainder rests at the taker's price, not at any fill's.
        let lock = if (order_id == book::none_id()) {
            0
        } else {
            quote_value(price, book::order_remaining(&market.book, order_id))
        };

        let owed = cost + lock;
        assert!(coin::value(&payment) >= owed, EInsufficientPayment);
        let payment = payment;
        coin::merge(&mut market.quote_vault, coin::extract(&mut payment, owed));
        market.quote_locked = market.quote_locked + lock;

        let fee = fee_on(market, filled);
        let out = coin::extract(&mut market.base_vault, filled);
        coin::merge(&mut market.base_fees, coin::extract(&mut out, fee));

        event::emit(OrderPlaced {
            market_id,
            owner: taker,
            order_id,
            is_bid: true,
            price,
            quantity,
            order_type,
            filled,
            quote_amount: cost,
            fee,
        });

        (out, payment, order_id)
    }

    /// Sell base for quote, at `price` or better.
    ///
    /// `payment` must cover the whole quantity if the order can rest, and the
    /// filled part if it cannot. The rest comes back.
    ///
    /// Returns `(quote_received, unspent_base, resting_order_id)`.
    public fun place_ask<Base, Quote>(
        taker_signer: &signer,
        market_id: address,
        price: u64,
        quantity: u64,
        order_type: u8,
        payment: Coin<Base>,
    ): (Coin<Quote>, Coin<Base>, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);
        place_ask_inner(market, market_id, signer::address_of(taker_signer),
            price, quantity, order_type, payment)
    }

    fun place_ask_inner<Base, Quote>(
        market: &mut Market<Base, Quote>,
        market_id: address,
        taker: address,
        price: u64,
        quantity: u64,
        order_type: u8,
        payment: Coin<Base>,
    ): (Coin<Quote>, Coin<Base>, u64) {
        check_order(market, price, quantity);

        let (fills, order_id) =
            book::place_limit_order(&mut market.book, taker, price, quantity, false, order_type);

        let filled = 0;
        let proceeds = 0;
        let i = 0;
        while (i < fills.length()) {
            let fill = &fills[i];
            let (maker, fill_price, fill_qty) =
                (book::fill_maker(fill), book::fill_price(fill), book::fill_quantity(fill));
            let value = quote_value(fill_price, fill_qty);

            // The bid's locked quote goes to the taker; the maker is owed the
            // base the taker sells.
            filled = filled + fill_qty;
            proceeds = proceeds + value;
            market.quote_locked = market.quote_locked - value;
            credit(market, maker, fill_qty, 0);

            event::emit(OrderFilled {
                market_id,
                maker_order_id: book::fill_maker_order(fill),
                maker,
                taker,
                taker_is_bid: false,
                price: fill_price,
                quantity: fill_qty,
            });
            i = i + 1;
        };

        let lock = if (order_id == book::none_id()) {
            0
        } else {
            book::order_remaining(&market.book, order_id)
        };

        let owed = filled + lock;
        assert!(coin::value(&payment) >= owed, EInsufficientPayment);
        let payment = payment;
        coin::merge(&mut market.base_vault, coin::extract(&mut payment, owed));
        market.base_locked = market.base_locked + lock;

        let fee = fee_on(market, proceeds);
        let out = coin::extract(&mut market.quote_vault, proceeds);
        coin::merge(&mut market.quote_fees, coin::extract(&mut out, fee));

        event::emit(OrderPlaced {
            market_id,
            owner: taker,
            order_id,
            is_bid: false,
            price,
            quantity,
            order_type,
            filled,
            quote_amount: proceeds,
            fee,
        });

        (out, payment, order_id)
    }

    // ------------------------------------------------------------------ //
    // Cancelling and withdrawing                                         //
    // ------------------------------------------------------------------ //

    /// Cancel a resting order. What it still had locked is credited to the
    /// owner's claimable balance, not paid out -- see the module docs.
    public fun cancel_order<Base, Quote>(
        owner_signer: &signer,
        market_id: address,
        order_id: u64,
    ) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);

        assert!(book::has_order(&market.book, order_id), EOrderNotFound);
        let owner = signer::address_of(owner_signer);
        let price = book::order_price(&market.book, order_id);
        let is_bid = book::order_is_bid(&market.book, order_id);

        // The book checks ownership.
        let remaining = book::cancel(&mut market.book, owner, order_id);

        if (is_bid) {
            let refund = quote_value(price, remaining);
            market.quote_locked = market.quote_locked - refund;
            credit(market, owner, 0, refund);
        } else {
            market.base_locked = market.base_locked - remaining;
            credit(market, owner, remaining, 0);
        };

        event::emit(OrderCanceled {
            market_id,
            order_id,
            owner,
            is_bid,
            price,
            remaining,
        });
    }

    /// Pay out everything the sender can claim. Zero coins if nothing.
    public fun withdraw<Base, Quote>(
        owner_signer: &signer,
        market_id: address,
    ): (Coin<Base>, Coin<Quote>) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);

        let owner = signer::address_of(owner_signer);
        if (!table::contains(&market.claims, owner)) {
            return (coin::zero(), coin::zero())
        };
        // Removed rather than zeroed, so the table does not grow with every
        // address that ever traded.
        let Claim { base, quote } = table::remove(&mut market.claims, owner);

        event::emit(Withdrawn { market_id, owner, base, quote });

        (
            coin::extract(&mut market.base_vault, base),
            coin::extract(&mut market.quote_vault, quote),
        )
    }

    /// `withdraw`, paid into the caller's own balances.
    public entry fun withdraw_entry<Base, Quote>(
        owner_signer: &signer,
        market_id: address,
    ) acquires Market {
        let (base, quote) = withdraw<Base, Quote>(owner_signer, market_id);
        let who = signer::address_of(owner_signer);
        coin::deposit(who, base);
        coin::deposit(who, quote);
    }

    /// Park a cap under an account.
    ///
    /// This function has to exist, and has no Sui counterpart. Move confines
    /// `move_to` and `borrow_global` on a type to its defining module, so a cap
    /// holder cannot put their own cap into storage -- whereas a Sui `MarketCap`
    /// is an owned object its holder transfers themselves, with no cooperation
    /// from this module. The same rule is why `stored_cap_market_id` below is
    /// needed for anyone to read a parked cap at all.
    public fun store_cap(owner: &signer, cap: MarketCap) {
        move_to(owner, cap);
    }

    #[view]
    /// The market a parked cap authorises.
    public fun stored_cap_market_id(owner: address): address acquires MarketCap {
        borrow_global<MarketCap>(owner).market_id
    }

    /// `collect_fees` using the cap parked under `admin`.
    public fun collect_fees_stored<Base, Quote>(
        admin: &signer,
        market_id: address,
    ): (Coin<Base>, Coin<Quote>) acquires Market, MarketCap {
        let cap = borrow_global<MarketCap>(signer::address_of(admin));
        collect_fees<Base, Quote>(market_id, cap)
    }

    public fun collect_fees<Base, Quote>(
        market_id: address,
        cap: &MarketCap,
    ): (Coin<Base>, Coin<Quote>) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        assert!(cap.market_id == market_id, EWrongMarket);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);
        (
            coin::extract_all(&mut market.base_fees),
            coin::extract_all(&mut market.quote_fees),
        )
    }

    /// `collect_fees` using the cap parked under the caller's account.
    public entry fun collect_fees_entry<Base, Quote>(
        admin: &signer,
        market_id: address,
    ) acquires Market, MarketCap {
        let (base, quote) = collect_fees_stored<Base, Quote>(admin, market_id);
        let who = signer::address_of(admin);
        coin::deposit(who, base);
        coin::deposit(who, quote);
    }

    // ------------------------------------------------------------------ //
    // Swaps: the pool-shaped interface                                   //
    // ------------------------------------------------------------------ //

    /// How much base a quote budget buys, walking the asks best-first.
    ///
    /// Returns `(base, quote_spent, worst_price)`. At each level the budget
    /// buys as many whole lots as it can afford; the first level it cannot
    /// clear is the last, because what is left is under one lot at that price
    /// and so under one lot at any higher price too.
    fun base_for_budget<Base, Quote>(market: &Market<Base, Quote>, budget: u64): (u64, u64, u64) {
        let price = book::best_ask(&market.book);
        let left = budget;
        let base = 0;
        let worst = 0;

        while (price != book::none_id()) {
            let available = book::depth_at(&market.book, price, false);
            let affordable =
                (left as u128) * (PRICE_SCALE as u128) / (price as u128);
            if (affordable > MAX_U64) { affordable = MAX_U64 };
            let affordable = (affordable as u64);
            let affordable = affordable - affordable % market.lot_size;

            let take = if (available < affordable) { available } else { affordable };
            if (take == 0) break;

            base = base + take;
            left = left - quote_value(price, take);
            worst = price;

            if (take < available) break;
            price = book::next_price(&market.book, price, false);
        };

        (base, budget - left, worst)
    }

    /// Sell an exact amount of base into the bids.
    ///
    /// Only whole lots trade; the remainder comes back with anything the bids
    /// could not absorb. Returns `(quote_out, unspent_base)`.
    public fun swap_base_for_quote<Base, Quote>(
        taker_signer: &signer,
        market_id: address,
        coin_in: Coin<Base>,
        min_quote_out: u64,
    ): (Coin<Quote>, Coin<Base>) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);

        let amount = coin::value(&coin_in);
        let quantity = amount - amount % market.lot_size;

        if (quantity == 0 || book::best_bid(&market.book) == book::none_id()) {
            assert!(min_quote_out == 0, ESlippage);
            return (coin::zero(), coin_in)
        };

        // The lowest price there is: take every bid, best first, and let
        // `min_quote_out` be the bound.
        let floor = market.tick_size;
        let (out, change, _) = place_ask_inner(
            market, market_id, signer::address_of(taker_signer),
            floor, quantity, book::ioc(), coin_in,
        );
        assert!(coin::value(&out) >= min_quote_out, ESlippage);
        (out, change)
    }

    /// Spend an exact amount of quote on the asks.
    ///
    /// Buys the most whole lots the coin affords. Returns `(base_out,
    /// unspent_quote)`.
    public fun swap_quote_for_base<Base, Quote>(
        taker_signer: &signer,
        market_id: address,
        coin_in: Coin<Quote>,
        min_base_out: u64,
    ): (Coin<Base>, Coin<Quote>) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global_mut<Market<Base, Quote>>(market_id);

        let (quantity, _, worst) = base_for_budget(market, coin::value(&coin_in));

        if (quantity == 0) {
            assert!(min_base_out == 0, ESlippage);
            return (coin::zero(), coin_in)
        };

        // Limit at the worst level the walk reached. Matching visits the same
        // levels in the same order, so it fills exactly `quantity` for exactly
        // what the walk spent.
        let (out, change, _) = place_bid_inner(
            market, market_id, signer::address_of(taker_signer),
            worst, quantity, book::ioc(), coin_in,
        );
        assert!(coin::value(&out) >= min_base_out, ESlippage);
        (out, change)
    }

    #[view]
    /// What `swap_base_for_quote` would return, without executing:
    /// `(quote_out_after_fee, base_used)`.
    public fun quote_base_for_quote<Base, Quote>(
        market_id: address,
        amount_in: u64,
    ): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        let quantity = amount_in - amount_in % market.lot_size;
        if (quantity == 0) return (0, 0);
        let (filled, notional) =
            book::quote(&market.book, market.tick_size, quantity, false);
        // The book sums raw `price * quantity`; it knows nothing of the scale.
        // Every term is an aligned fill, so dividing the sum is exact. The
        // result is bounded by the quote locked behind the bids, a u64.
        let proceeds = ((notional / (PRICE_SCALE as u128)) as u64);
        (proceeds - fee_on(market, proceeds), filled)
    }

    #[view]
    /// What `swap_quote_for_base` would return, without executing:
    /// `(base_out_after_fee, quote_used)`.
    public fun quote_quote_for_base<Base, Quote>(
        market_id: address,
        amount_in: u64,
    ): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        let (base, spent, _) = base_for_budget(market, amount_in);
        (base - fee_on(market, base), spent)
    }

    // ------------------------------------------------------------------ //
    // Reading                                                            //
    // ------------------------------------------------------------------ //

    #[view]
    public fun best_bid<Base, Quote>(market_id: address): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::best_bid(&borrow_global<Market<Base, Quote>>(market_id).book)
    }

    #[view]
    public fun best_ask<Base, Quote>(market_id: address): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::best_ask(&borrow_global<Market<Base, Quote>>(market_id).book)
    }

    #[view]
    public fun tick_size<Base, Quote>(market_id: address): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        borrow_global<Market<Base, Quote>>(market_id).tick_size
    }

    #[view]
    public fun lot_size<Base, Quote>(market_id: address): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        borrow_global<Market<Base, Quote>>(market_id).lot_size
    }

    #[view]
    public fun taker_fee_bps<Base, Quote>(market_id: address): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        borrow_global<Market<Base, Quote>>(market_id).taker_fee_bps
    }

    #[view]
    /// `(base, quote)` the owner can withdraw.
    public fun claimable<Base, Quote>(market_id: address, owner: address): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        if (!table::contains(&market.claims, owner)) return (0, 0);
        let claim = table::borrow(&market.claims, owner);
        (claim.base, claim.quote)
    }

    #[view]
    /// `(base, quote)` held for traders, locked and claimable together.
    public fun vault_balances<Base, Quote>(market_id: address): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        (coin::value(&market.base_vault), coin::value(&market.quote_vault))
    }

    #[view]
    /// `(base, quote)` locked behind resting orders.
    public fun locked<Base, Quote>(market_id: address): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        (market.base_locked, market.quote_locked)
    }

    #[view]
    /// `(base, quote)` accrued and not yet collected.
    public fun fees<Base, Quote>(market_id: address): (u64, u64) acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        let market = borrow_global<Market<Base, Quote>>(market_id);
        (coin::value(&market.base_fees), coin::value(&market.quote_fees))
    }

    // Sui exposes the book wholesale -- `public fun book(): &Book` -- and lets
    // callers reach through it. That has no Aptos spelling: reference safety
    // refuses to return a reference derived from global storage unless it came
    // from a parameter, so a borrow of `market.book` cannot leave this module.
    // Every accessor a caller needs is forwarded individually instead.

    #[view]
    /// Depth resting at one price.
    public fun depth_at<Base, Quote>(
        market_id: address, price: u64, is_bid: bool,
    ): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::depth_at(&borrow_global<Market<Base, Quote>>(market_id).book, price, is_bid)
    }

    #[view]
    public fun order_remaining<Base, Quote>(market_id: address, order_id: u64): u64 acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::order_remaining(&borrow_global<Market<Base, Quote>>(market_id).book, order_id)
    }

    #[view]
    public fun has_order<Base, Quote>(market_id: address, order_id: u64): bool acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::has_order(&borrow_global<Market<Base, Quote>>(market_id).book, order_id)
    }

    #[view]
    public fun order_owner<Base, Quote>(market_id: address, order_id: u64): address acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::order_owner(&borrow_global<Market<Base, Quote>>(market_id).book, order_id)
    }

    #[view]
    public fun order_is_bid<Base, Quote>(market_id: address, order_id: u64): bool acquires Market {
        assert_market_exists<Base, Quote>(market_id);
        book::order_is_bid(&borrow_global<Market<Base, Quote>>(market_id).book, order_id)
    }

    public fun cap_market_id(cap: &MarketCap): address { cap.market_id }

    fun assert_market_exists<Base, Quote>(market_id: address) {
        assert!(exists<Market<Base, Quote>>(market_id), ENoSuchMarket);
    }
}
