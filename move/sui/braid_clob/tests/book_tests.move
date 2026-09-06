#[test_only]
module braid_clob::book_tests {
    use sui::test_scenario::{Self as ts};
    use braid_clob::book::{Self, Book};

    const ALICE: address = @0xA;
    const BOB: address = @0xB;
    const CAROL: address = @0xC;

    /// Rest an order and return its id, asserting nothing matched.
    fun rest(book: &mut Book, who: address, price: u64, qty: u64, is_bid: bool): u64 {
        let (fills, id) = book::place_limit_order(book, who, price, qty, is_bid, book::gtc());
        assert!(fills.is_empty(), 99);
        assert!(id != book::none_id(), 98);
        id
    }

    fun drain(book: &mut Book) {
        // Cancel everything so the book can be destroyed.
        while (book::best_bid(book) != book::none_id()) {
            let p = book::best_bid(book);
            let mut id = 1;
            while (id < 200) {
                if (book::has_order(book, id) && book::order_remaining(book, id) > 0) {
                    let owner = book::order_owner(book, id);
                    book::cancel(book, owner, id);
                    break
                };
                id = id + 1;
            };
            if (book::best_bid(book) == p && book::depth_at(book, p, true) == 0) break;
        };
        while (book::best_ask(book) != book::none_id()) {
            let mut id = 1;
            while (id < 200) {
                if (book::has_order(book, id) && book::order_remaining(book, id) > 0) {
                    let owner = book::order_owner(book, id);
                    book::cancel(book, owner, id);
                    break
                };
                id = id + 1;
            };
        };
    }

    // ---------------------------------------------------------------- //
    // Resting orders                                                   //
    // ---------------------------------------------------------------- //

    #[test]
    fun an_empty_book_has_no_best_price() {
        let mut sc = ts::begin(ALICE);
        {
            let book = book::empty(sc.ctx());
            assert!(book::best_bid(&book) == book::none_id(), 0);
            assert!(book::best_ask(&book) == book::none_id(), 1);
            assert!(book::depth_at(&book, 100, true) == 0, 2);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun resting_orders_set_the_top_of_book() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 10, true);
            rest(&mut book, ALICE, 105, 10, false);

            assert!(book::best_bid(&book) == 100, 0);
            assert!(book::best_ask(&book) == 105, 1);
            assert!(book::depth_at(&book, 100, true) == 10, 2);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun the_best_bid_is_the_highest_and_the_best_ask_the_lowest() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 98, 5, true);
            rest(&mut book, ALICE, 100, 5, true);
            rest(&mut book, ALICE, 99, 5, true);
            assert!(book::best_bid(&book) == 100, 0);

            rest(&mut book, ALICE, 107, 5, false);
            rest(&mut book, ALICE, 105, 5, false);
            rest(&mut book, ALICE, 106, 5, false);
            assert!(book::best_ask(&book) == 105, 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun orders_at_the_same_price_accumulate_into_one_level() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 10, true);
            rest(&mut book, BOB, 100, 25, true);
            rest(&mut book, CAROL, 100, 5, true);

            assert!(book::depth_at(&book, 100, true) == 40, 0);
            assert!(book::level_count(&book, 100, true) == 3, 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Matching                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_crossing_order_matches_and_prints_at_the_makers_price() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 10, false);   // ask at 100

            // Bob bids 105, above the ask. He should pay 100, not 105 --
            // the resting order sets the price.
            let (fills, id) =
                book::place_limit_order(&mut book, BOB, 105, 10, true, book::gtc());

            assert!(fills.length() == 1, 0);
            assert!(book::fill_price(&fills[0]) == 100, 1);
            assert!(book::fill_quantity(&fills[0]) == 10, 2);
            assert!(book::fill_maker(&fills[0]) == ALICE, 3);
            // Fully filled, so nothing rested.
            assert!(id == book::none_id(), 4);
            assert!(book::best_ask(&book) == book::none_id(), 5);

            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun a_partial_take_leaves_the_rest_of_the_maker_resting() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let maker = rest(&mut book, ALICE, 100, 10, false);

            let (fills, _) = book::place_limit_order(&mut book, BOB, 100, 4, true, book::gtc());
            assert!(book::fill_quantity(&fills[0]) == 4, 0);
            assert!(book::order_remaining(&book, maker) == 6, 1);
            assert!(book::depth_at(&book, 100, false) == 6, 2);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun an_oversized_take_rests_the_remainder_on_the_other_side() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 4, false);

            // Wants 10, only 4 available.
            let (fills, id) =
                book::place_limit_order(&mut book, BOB, 100, 10, true, book::gtc());
            assert!(book::fill_quantity(&fills[0]) == 4, 0);
            assert!(id != book::none_id(), 1);
            // The unfilled 6 becomes the new best bid.
            assert!(book::best_bid(&book) == 100, 2);
            assert!(book::depth_at(&book, 100, true) == 6, 3);
            assert!(book::best_ask(&book) == book::none_id(), 4);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun equal_prices_fill_in_arrival_order() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            // Three asks at the same price, in this order.
            let first = rest(&mut book, ALICE, 100, 5, false);
            let second = rest(&mut book, BOB, 100, 5, false);
            let third = rest(&mut book, CAROL, 100, 5, false);

            // Take 7: all of the first, part of the second, none of the third.
            let (fills, _) =
                book::place_limit_order(&mut book, @0xD, 100, 7, true, book::gtc());

            assert!(fills.length() == 2, 0);
            assert!(book::fill_maker(&fills[0]) == ALICE, 1);
            assert!(book::fill_quantity(&fills[0]) == 5, 2);
            assert!(book::fill_maker(&fills[1]) == BOB, 3);
            assert!(book::fill_quantity(&fills[1]) == 2, 4);

            assert!(!book::has_order(&book, first), 5);
            assert!(book::order_remaining(&book, second) == 3, 6);
            assert!(book::order_remaining(&book, third) == 5, 7);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun a_large_order_walks_several_price_levels() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 101, 5, false);
            rest(&mut book, CAROL, 102, 5, false);

            // 12 units, limit 102: takes 5 + 5 + 2, best price first.
            let (fills, id) =
                book::place_limit_order(&mut book, @0xD, 102, 12, true, book::gtc());

            assert!(fills.length() == 3, 0);
            assert!(book::fill_price(&fills[0]) == 100, 1);
            assert!(book::fill_price(&fills[1]) == 101, 2);
            assert!(book::fill_price(&fills[2]) == 102, 3);
            assert!(book::fill_quantity(&fills[2]) == 2, 4);
            assert!(id == book::none_id(), 5);
            assert!(book::best_ask(&book) == 102, 6);
            assert!(book::depth_at(&book, 102, false) == 3, 7);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun the_limit_price_stops_the_walk() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 105, 5, false);

            // Willing to pay 100 only, so the 105 level is untouched and the
            // remainder rests as a bid.
            let (fills, id) =
                book::place_limit_order(&mut book, CAROL, 100, 10, true, book::gtc());
            assert!(fills.length() == 1, 0);
            assert!(id != book::none_id(), 1);
            assert!(book::best_ask(&book) == 105, 2);
            assert!(book::best_bid(&book) == 100, 3);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Quoting without executing                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_quote_walks_the_full_depth_and_changes_nothing() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 101, 5, false);
            rest(&mut book, CAROL, 102, 5, false);

            // 12 units at up to 102: 5@100 + 5@101 + 2@102.
            let (filled, cost) = book::quote(&book, 102, 12, true);
            assert!(filled == 12, 0);
            assert!(cost == 500 + 505 + 204, 1);

            // The book is untouched, which is the whole point.
            assert!(book::depth_at(&book, 100, false) == 5, 2);
            assert!(book::best_ask(&book) == 100, 3);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun a_quote_stops_at_the_limit_price() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 105, 5, false);

            let (filled, cost) = book::quote(&book, 100, 10, true);
            assert!(filled == 5, 0);
            assert!(cost == 500, 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun a_quote_matches_what_the_order_actually_does() {
        // The property the router depends on: quoting and executing agree.
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 101, 4, false);
            rest(&mut book, CAROL, 103, 6, false);

            let (quoted_qty, quoted_cost) = book::quote(&book, 103, 12, true);

            let (fills, _) =
                book::place_limit_order(&mut book, @0xD, 103, 12, true, book::gtc());
            let mut got: u64 = 0;
            let mut paid: u128 = 0;
            let mut i = 0;
            while (i < fills.length()) {
                got = got + book::fill_quantity(&fills[i]);
                paid = paid
                    + (book::fill_price(&fills[i]) as u128)
                        * (book::fill_quantity(&fills[i]) as u128);
                i = i + 1;
            };

            assert!(got == quoted_qty, 0);
            assert!(paid == quoted_cost, 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun quoting_an_empty_or_unreachable_book_yields_nothing() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let (f0, c0) = book::quote(&book, 100, 10, true);
            assert!(f0 == 0 && c0 == 0, 0);

            rest(&mut book, ALICE, 200, 5, false);
            // Nobody is selling as low as 100.
            let (f1, c1) = book::quote(&book, 100, 10, true);
            assert!(f1 == 0 && c1 == 0, 1);

            // Total depth ignores the limit.
            assert!(book::depth_to(&book, 999, true) == 5, 2);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun selling_quotes_against_the_bids() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, true);
            rest(&mut book, BOB, 99, 5, true);
            rest(&mut book, CAROL, 98, 5, true);

            // Selling 12 down to 98 takes the best bids first.
            let (filled, proceeds) = book::quote(&book, 98, 12, false);
            assert!(filled == 12, 0);
            assert!(proceeds == 500 + 495 + 196, 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Order types                                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun immediate_or_cancel_does_not_rest() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 4, false);

            let (fills, id) =
                book::place_limit_order(&mut book, BOB, 100, 10, true, book::ioc());
            assert!(book::fill_quantity(&fills[0]) == 4, 0);
            // The unfilled 6 is discarded rather than posted.
            assert!(id == book::none_id(), 1);
            assert!(book::best_bid(&book) == book::none_id(), 2);

            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun fill_or_kill_succeeds_when_the_book_is_deep_enough() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 6, false);
            rest(&mut book, BOB, 101, 6, false);

            let (fills, id) =
                book::place_limit_order(&mut book, CAROL, 101, 10, true, book::fok());
            assert!(fills.length() == 2, 0);
            assert!(id == book::none_id(), 1);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ENotFillable)]
    fun fill_or_kill_aborts_when_it_cannot_fill_completely() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 4, false);
            // Wants 10, only 4 available. The abort reverts the partial fill.
            book::place_limit_order(&mut book, BOB, 100, 10, true, book::fok());
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun post_only_rests_when_it_does_not_cross() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 105, 5, false);

            let (fills, id) =
                book::place_limit_order(&mut book, BOB, 100, 5, true, book::post_only());
            assert!(fills.is_empty(), 0);
            assert!(id != book::none_id(), 1);
            assert!(book::best_bid(&book) == 100, 2);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::EWouldCross)]
    fun post_only_aborts_rather_than_taking() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            // A bid at 105 would cross the 100 ask, which post-only forbids.
            book::place_limit_order(&mut book, BOB, 105, 5, true, book::post_only());
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ESelfTrade)]
    fun matching_your_own_resting_order_is_rejected() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, false);
            // Alice crossing her own ask would let her manufacture volume.
            book::place_limit_order(&mut book, ALICE, 100, 5, true, book::gtc());
            book::destroy_empty(book);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Cancellation                                                     //
    // ---------------------------------------------------------------- //

    #[test]
    fun cancelling_removes_the_order_and_its_depth() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let id = rest(&mut book, ALICE, 100, 10, true);
            assert!(book::depth_at(&book, 100, true) == 10, 0);

            let returned = book::cancel(&mut book, ALICE, id);
            assert!(returned == 10, 1);
            assert!(!book::has_order(&book, id), 2);
            // The level went with it.
            assert!(book::best_bid(&book) == book::none_id(), 3);

            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun cancelling_from_the_middle_of_a_queue_leaves_the_rest_intact() {
        // The case the linked list exists for.
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let first = rest(&mut book, ALICE, 100, 5, false);
            let middle = rest(&mut book, BOB, 100, 5, false);
            let last = rest(&mut book, CAROL, 100, 5, false);

            book::cancel(&mut book, BOB, middle);
            assert!(book::depth_at(&book, 100, false) == 10, 0);
            assert!(book::level_count(&book, 100, false) == 2, 1);

            // The queue is still in order: first, then last.
            let (fills, _) =
                book::place_limit_order(&mut book, @0xD, 100, 10, true, book::gtc());
            assert!(fills.length() == 2, 2);
            assert!(book::fill_maker(&fills[0]) == ALICE, 3);
            assert!(book::fill_maker(&fills[1]) == CAROL, 4);
            assert!(!book::has_order(&book, first), 5);
            assert!(!book::has_order(&book, last), 6);

            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    fun cancelling_the_head_promotes_the_next_order() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let head = rest(&mut book, ALICE, 100, 5, false);
            rest(&mut book, BOB, 100, 5, false);

            book::cancel(&mut book, ALICE, head);
            let (fills, _) =
                book::place_limit_order(&mut book, CAROL, 100, 5, true, book::gtc());
            assert!(book::fill_maker(&fills[0]) == BOB, 0);

            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ENotOwner)]
    fun only_the_owner_may_cancel() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let id = rest(&mut book, ALICE, 100, 10, true);
            book::cancel(&mut book, BOB, id);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::EOrderNotFound)]
    fun cancelling_a_filled_order_is_rejected() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            let id = rest(&mut book, ALICE, 100, 5, false);
            book::place_limit_order(&mut book, BOB, 100, 5, true, book::gtc());
            // Fully filled orders are gone, not resting at zero.
            book::cancel(&mut book, ALICE, id);
            book::destroy_empty(book);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::EZeroAmount)]
    fun a_zero_quantity_order_is_rejected() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            book::place_limit_order(&mut book, ALICE, 100, 0, true, book::gtc());
            book::destroy_empty(book);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Both directions                                                  //
    // ---------------------------------------------------------------- //

    #[test]
    fun selling_into_bids_works_the_same_way_upside_down() {
        let mut sc = ts::begin(ALICE);
        {
            let mut book = book::empty(sc.ctx());
            rest(&mut book, ALICE, 100, 5, true);
            rest(&mut book, BOB, 99, 5, true);

            // Sell 8 at 99 or better: takes the 100 bid first, then part of 99.
            let (fills, id) =
                book::place_limit_order(&mut book, CAROL, 99, 8, false, book::gtc());
            assert!(fills.length() == 2, 0);
            assert!(book::fill_price(&fills[0]) == 100, 1);
            assert!(book::fill_price(&fills[1]) == 99, 2);
            assert!(book::fill_quantity(&fills[1]) == 3, 3);
            assert!(id == book::none_id(), 4);
            assert!(book::best_bid(&book) == 99, 5);
            assert!(book::depth_at(&book, 99, true) == 2, 6);

            drain(&mut book);
            book::destroy_empty(book);
        };
        sc.end();
    }
}
