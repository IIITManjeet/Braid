/// The order book: price levels, and matching with price-time priority.
///
/// Two crit-bit trees, one per side. Bids are keyed so the *maximum* is the
/// best price; asks so the minimum is. Each tree holds a level, and a level
/// holds a doubly-linked FIFO queue of order ids.
///
/// # Why a linked list and not a vector
///
/// Orders within a level fill in arrival order, so the queue only ever gets
/// taken from the front -- a vector would serve that fine. Cancellation is the
/// problem: it removes from the middle, and it is the single most common
/// operation a real book sees. Market makers cancel and replace constantly. A
/// vector makes that a shift of everything behind it; a linked list makes it
/// two pointer writes.
///
/// # Price-time priority
///
/// Better price first, and among equal prices, earlier arrival first. The trees
/// give the first half and the FIFO queues give the second. Nothing else is
/// needed -- there is no size priority, no pro-rata. An order that has been
/// resting longer is simply ahead.
///
/// # What this module does not do
///
/// It does not hold funds. Matching produces a list of fills and the caller
/// settles them. Keeping custody out means the matching logic can be tested
/// without constructing balances.
///
/// It also cannot yet quote depth beyond the best level without executing.
/// Doing that read-only needs a successor operation on the crit-bit tree --
/// "the next key after this one" -- which the router will require and which is
/// not built. Fill-or-kill does not need it: an abort reverts the fills.
module braid_clob::book {
    use sui::table::{Self, Table};
    use braid_clob::critbit::{Self, CritbitTree};

    /// Quantity or price was zero.
    const EZeroAmount: u64 = 0;
    /// No such order.
    const EOrderNotFound: u64 = 1;
    /// Only the owner may cancel.
    const ENotOwner: u64 = 2;
    /// A post-only order would have crossed the book.
    const EWouldCross: u64 = 3;
    /// A fill-or-kill order could not be filled in full.
    const ENotFillable: u64 = 4;
    /// An order would have matched its own owner's resting order.
    const ESelfTrade: u64 = 5;
    /// Unrecognised order type.
    const EInvalidOrderType: u64 = 6;

    /// Rest whatever does not fill.
    const GTC: u8 = 0;
    /// Fill what can be filled now, cancel the rest.
    const IOC: u8 = 1;
    /// Fill entirely or not at all.
    const FOK: u8 = 2;
    /// Never take. Abort rather than cross.
    const POST_ONLY: u8 = 3;

    const NONE: u64 = 0xFFFFFFFFFFFFFFFF;

    public fun gtc(): u8 { GTC }
    public fun ioc(): u8 { IOC }
    public fun fok(): u8 { FOK }
    public fun post_only(): u8 { POST_ONLY }
    public fun none_id(): u64 { NONE }

    public struct Order has store, drop, copy {
        id: u64,
        owner: address,
        price: u64,
        /// What the order was placed for. Never changes.
        quantity: u64,
        /// What is left. Zero means it is gone.
        remaining: u64,
        is_bid: bool,
        /// Neighbours in this price level's FIFO queue.
        next: u64,
        prev: u64,
    }

    public struct Level has store {
        /// Sum of `remaining` across the queue, so depth is a read.
        total: u64,
        head: u64,
        tail: u64,
        count: u64,
    }

    /// One side of a trade, for the caller to settle.
    public struct Fill has store, drop, copy {
        maker_order_id: u64,
        maker: address,
        price: u64,
        quantity: u64,
    }

    public struct Book has store {
        bids: CritbitTree<Level>,
        asks: CritbitTree<Level>,
        orders: Table<u64, Order>,
        next_order_id: u64,
    }

    // ------------------------------------------------------------------ //
    // Construction                                                       //
    // ------------------------------------------------------------------ //

    public fun empty(ctx: &mut TxContext): Book {
        Book {
            bids: critbit::empty<Level>(ctx),
            asks: critbit::empty<Level>(ctx),
            orders: table::new(ctx),
            next_order_id: 1,
        }
    }

    // ------------------------------------------------------------------ //
    // Reading the book                                                   //
    // ------------------------------------------------------------------ //

    /// Highest bid, or `NONE` if there are none.
    public fun best_bid(book: &Book): u64 {
        if (critbit::is_empty(&book.bids)) { NONE } else { critbit::max_key(&book.bids) }
    }

    /// Lowest ask, or `NONE` if there are none.
    public fun best_ask(book: &Book): u64 {
        if (critbit::is_empty(&book.asks)) { NONE } else { critbit::min_key(&book.asks) }
    }

    /// Resting quantity at a price, zero if the level does not exist.
    public fun depth_at(book: &Book, price: u64, is_bid: bool): u64 {
        let side = if (is_bid) { &book.bids } else { &book.asks };
        let (found, leaf) = critbit::find(side, price);
        if (found) { critbit::borrow_leaf(side, leaf).total } else { 0 }
    }

    public fun level_count(book: &Book, price: u64, is_bid: bool): u64 {
        let side = if (is_bid) { &book.bids } else { &book.asks };
        let (found, leaf) = critbit::find(side, price);
        if (found) { critbit::borrow_leaf(side, leaf).count } else { 0 }
    }

    public fun has_order(book: &Book, id: u64): bool { table::contains(&book.orders, id) }

    public fun order_remaining(book: &Book, id: u64): u64 {
        if (table::contains(&book.orders, id)) {
            table::borrow(&book.orders, id).remaining
        } else {
            0
        }
    }

    public fun order_owner(book: &Book, id: u64): address {
        table::borrow(&book.orders, id).owner
    }

    public fun fill_price(f: &Fill): u64 { f.price }
    public fun fill_quantity(f: &Fill): u64 { f.quantity }
    public fun fill_maker(f: &Fill): address { f.maker }
    public fun fill_maker_order(f: &Fill): u64 { f.maker_order_id }

    // ------------------------------------------------------------------ //
    // Queue maintenance                                                  //
    // ------------------------------------------------------------------ //

    /// Append an order to the back of its price level, creating the level if
    /// this is the first order at that price.
    fun enqueue(book: &mut Book, order: Order) {
        let id = order.id;
        let price = order.price;
        let quantity = order.remaining;
        let is_bid = order.is_bid;

        table::add(&mut book.orders, id, order);

        let side = if (is_bid) { &mut book.bids } else { &mut book.asks };
        let (found, leaf) = critbit::find(side, price);

        if (!found) {
            critbit::insert(side, price, Level {
                total: quantity, head: id, tail: id, count: 1,
            });
            return
        };

        let level = critbit::borrow_leaf_mut(side, leaf);
        let old_tail = level.tail;
        level.tail = id;
        level.total = level.total + quantity;
        level.count = level.count + 1;

        table::borrow_mut(&mut book.orders, old_tail).next = id;
        table::borrow_mut(&mut book.orders, id).prev = old_tail;
    }

    /// Unlink an order from its level and delete it. Removes the level too if
    /// it was the last order there.
    fun unlink(book: &mut Book, id: u64): Order {
        let order = *table::borrow(&book.orders, id);
        let side = if (order.is_bid) { &mut book.bids } else { &mut book.asks };
        let (found, leaf) = critbit::find(side, order.price);
        assert!(found, EOrderNotFound);

        let level = critbit::borrow_leaf_mut(side, leaf);
        level.total = level.total - order.remaining;
        level.count = level.count - 1;
        if (level.head == id) { level.head = order.next };
        if (level.tail == id) { level.tail = order.prev };
        let now_empty = level.count == 0;

        if (order.prev != NONE) {
            table::borrow_mut(&mut book.orders, order.prev).next = order.next;
        };
        if (order.next != NONE) {
            table::borrow_mut(&mut book.orders, order.next).prev = order.prev;
        };

        if (now_empty) {
            let side2 = if (order.is_bid) { &mut book.bids } else { &mut book.asks };
            let Level { total: _, head: _, tail: _, count: _ } = critbit::remove(side2, order.price);
        };

        table::remove(&mut book.orders, id)
    }

    // ------------------------------------------------------------------ //
    // Matching                                                           //
    // ------------------------------------------------------------------ //

    /// Would an order at this price take from the other side?
    fun crosses(book: &Book, price: u64, is_bid: bool): bool {
        if (is_bid) {
            let ask = best_ask(book);
            ask != NONE && price >= ask
        } else {
            let bid = best_bid(book);
            bid != NONE && price <= bid
        }
    }

    /// Place an order, matching against the book first.
    ///
    /// Returns `(fills, resting_order_id)`. The id is `NONE` when nothing
    /// rested -- because the order filled completely, or because its type
    /// forbids resting.
    public fun place_limit_order(
        book: &mut Book,
        owner: address,
        price: u64,
        quantity: u64,
        is_bid: bool,
        order_type: u8,
    ): (vector<Fill>, u64) {
        assert!(price > 0 && quantity > 0, EZeroAmount);
        assert!(
            order_type == GTC || order_type == IOC
                || order_type == FOK || order_type == POST_ONLY,
            EInvalidOrderType,
        );

        if (order_type == POST_ONLY) {
            assert!(!crosses(book, price, is_bid), EWouldCross);
        };

        let mut fills = vector<Fill>[];
        let mut remaining = quantity;

        if (order_type != POST_ONLY) {
            remaining = match_against(book, owner, price, quantity, is_bid, &mut fills);
        };

        if (order_type == FOK) {
            // A shortfall aborts, and an abort reverts the whole transaction
            // -- including the fills applied just above. That is what makes
            // fill-or-kill correct without a manual rollback, and it is worth
            // being explicit about, because the same code in a language that
            // swallowed the error would leave the book half-eaten.
            assert!(remaining == 0, ENotFillable);
        };

        if (remaining == 0 || order_type == IOC || order_type == FOK) {
            return (fills, NONE)
        };

        let id = book.next_order_id;
        book.next_order_id = id + 1;
        enqueue(book, Order {
            id,
            owner,
            price,
            quantity,
            remaining,
            is_bid,
            next: NONE,
            prev: NONE,
        });
        (fills, id)
    }

    /// Walk the opposite side, taking from the best price outward and in
    /// arrival order within each price. Returns what could not be filled.
    fun match_against(
        book: &mut Book,
        taker: address,
        price: u64,
        quantity: u64,
        is_bid: bool,
        fills: &mut vector<Fill>,
    ): u64 {
        let mut remaining = quantity;

        while (remaining > 0) {
            let side_empty = if (is_bid) {
                critbit::is_empty(&book.asks)
            } else {
                critbit::is_empty(&book.bids)
            };
            if (side_empty) break;

            let level_price = if (is_bid) { best_ask(book) } else { best_bid(book) };
            let acceptable = if (is_bid) { level_price <= price } else { level_price >= price };
            if (!acceptable) break;

            let leaf = if (is_bid) {
                critbit::min_leaf(&book.asks)
            } else {
                critbit::max_leaf(&book.bids)
            };
            let head_id = if (is_bid) {
                critbit::borrow_leaf(&book.asks, leaf).head
            } else {
                critbit::borrow_leaf(&book.bids, leaf).head
            };

            let maker = *table::borrow(&book.orders, head_id);
            // Trading with yourself would let one account manufacture volume
            // and self-cross the spread. Refuse rather than silently skip, so
            // the caller finds out.
            assert!(maker.owner != taker, ESelfTrade);

            let fill_qty = if (maker.remaining < remaining) { maker.remaining } else { remaining };

            fills.push_back(Fill {
                maker_order_id: head_id,
                maker: maker.owner,
                // Trades print at the resting order's price, not the taker's.
                price: maker.price,
                quantity: fill_qty,
            });

            remaining = remaining - fill_qty;

            if (fill_qty == maker.remaining) {
                unlink(book, head_id);
            } else {
                table::borrow_mut(&mut book.orders, head_id).remaining =
                    maker.remaining - fill_qty;
                let side = if (is_bid) { &mut book.asks } else { &mut book.bids };
                let level = critbit::borrow_leaf_mut(side, leaf);
                level.total = level.total - fill_qty;
            };
        };

        remaining
    }

    // ------------------------------------------------------------------ //
    // Cancellation                                                       //
    // ------------------------------------------------------------------ //

    /// Cancel a resting order, returning what was left of it.
    public fun cancel(book: &mut Book, owner: address, id: u64): u64 {
        assert!(table::contains(&book.orders, id), EOrderNotFound);
        assert!(table::borrow(&book.orders, id).owner == owner, ENotOwner);
        let order = unlink(book, id);
        order.remaining
    }

    // ------------------------------------------------------------------ //
    // Teardown                                                           //
    // ------------------------------------------------------------------ //

    /// Destroy a book with nothing resting on it.
    public fun destroy_empty(book: Book) {
        let Book { bids, asks, orders, next_order_id: _ } = book;
        critbit::destroy_empty(bids);
        critbit::destroy_empty(asks);
        table::destroy_empty(orders);
    }
}
