#[test_only]
module braid_clob::market_tests {
    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};

    use braid_clob::book;
    use braid_clob::market::{Self, Market, MarketCap};

    public struct BASE has drop {}
    public struct QUOTE has drop {}

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA;
    const BOB: address = @0xB;
    const CAROL: address = @0xC;

    /// 0.01 quote per base unit, in price units.
    const TICK: u64 = 10_000_000;
    /// 100 base units. TICK * LOT = 1e9, exactly the scale.
    const LOT: u64 = 100;
    /// 10 bps.
    const FEE: u64 = 10;

    /// 1.00, 1.01, ... quote per base unit.
    const P100: u64 = 1_000_000_000;
    const P101: u64 = 1_010_000_000;
    const P102: u64 = 1_020_000_000;
    const P105: u64 = 1_050_000_000;

    fun start(): Scenario {
        let mut sc = ts::begin(ADMIN);
        {
            let cap = market::create_market<BASE, QUOTE>(TICK, LOT, FEE, sc.ctx());
            transfer::public_transfer(cap, ADMIN);
        };
        sc
    }

    /// Place a bid as `who`. Returns `(base_out, quote_change, order_id)`.
    fun bid(sc: &mut Scenario, who: address, price: u64, qty: u64, ty: u8, pay: u64): (u64, u64, u64) {
        sc.next_tx(who);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let payment = coin::mint_for_testing<QUOTE>(pay, sc.ctx());
        let (out, change, id) = market::place_bid(&mut m, price, qty, ty, payment, sc.ctx());
        let (o, c) = (out.value(), change.value());
        coin::burn_for_testing(out);
        coin::burn_for_testing(change);
        ts::return_shared(m);
        (o, c, id)
    }

    /// Place an ask as `who`. Returns `(quote_out, base_change, order_id)`.
    fun ask(sc: &mut Scenario, who: address, price: u64, qty: u64, ty: u8, pay: u64): (u64, u64, u64) {
        sc.next_tx(who);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let payment = coin::mint_for_testing<BASE>(pay, sc.ctx());
        let (out, change, id) = market::place_ask(&mut m, price, qty, ty, payment, sc.ctx());
        let (o, c) = (out.value(), change.value());
        coin::burn_for_testing(out);
        coin::burn_for_testing(change);
        ts::return_shared(m);
        (o, c, id)
    }

    fun cancel(sc: &mut Scenario, who: address, id: u64) {
        sc.next_tx(who);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        market::cancel_order(&mut m, id, sc.ctx());
        ts::return_shared(m);
    }

    /// Withdraw as `who`. Returns `(base, quote)`.
    fun withdraw(sc: &mut Scenario, who: address): (u64, u64) {
        sc.next_tx(who);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (b, q) = market::withdraw(&mut m, sc.ctx());
        let (bv, qv) = (b.value(), q.value());
        coin::burn_for_testing(b);
        coin::burn_for_testing(q);
        ts::return_shared(m);
        (bv, qv)
    }

    fun claimable(sc: &mut Scenario, who: address): (u64, u64) {
        sc.next_tx(ADMIN);
        let m = sc.take_shared<Market<BASE, QUOTE>>();
        let (b, q) = market::claimable(&m, who);
        ts::return_shared(m);
        (b, q)
    }

    /// The vault holds exactly what is locked plus what the listed traders can
    /// claim. Every test that moves money ends by checking this.
    fun assert_vault_balances(sc: &mut Scenario, traders: vector<address>) {
        sc.next_tx(ADMIN);
        let m = sc.take_shared<Market<BASE, QUOTE>>();
        let (vault_base, vault_quote) = market::vault_balances(&m);
        let (locked_base, locked_quote) = market::locked(&m);
        let mut claim_base = 0;
        let mut claim_quote = 0;
        let mut i = 0;
        while (i < traders.length()) {
            let (b, q) = market::claimable(&m, traders[i]);
            claim_base = claim_base + b;
            claim_quote = claim_quote + q;
            i = i + 1;
        };
        assert!(vault_base == locked_base + claim_base, 900);
        assert!(vault_quote == locked_quote + claim_quote, 901);
        ts::return_shared(m);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_new_market_is_empty_and_holds_its_parameters() {
        let mut sc = start();
        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            assert!(market::tick_size(&m) == TICK, 0);
            assert!(market::lot_size(&m) == LOT, 1);
            assert!(market::taker_fee_bps(&m) == FEE, 2);
            assert!(market::best_bid(&m) == book::none_id(), 3);
            assert!(market::best_ask(&m) == book::none_id(), 4);
            let (vb, vq) = market::vault_balances(&m);
            assert!(vb == 0 && vq == 0, 5);

            let cap = sc.take_from_sender<MarketCap>();
            assert!(market::cap_market_id(&cap) == object::id(&m), 6);
            sc.return_to_sender(cap);
            ts::return_shared(m);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EInvalidSizes)]
    fun sizes_whose_product_is_not_a_multiple_of_the_scale_are_refused() {
        let mut sc = ts::begin(ADMIN);
        // 1e7 * 99 is not a multiple of 1e9: some fill values would round.
        let cap = market::create_market<BASE, QUOTE>(TICK, 99, FEE, sc.ctx());
        transfer::public_transfer(cap, ADMIN);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EInvalidFee)]
    fun a_fee_above_the_maximum_is_refused() {
        let mut sc = ts::begin(ADMIN);
        let cap = market::create_market<BASE, QUOTE>(TICK, LOT, 101, sc.ctx());
        transfer::public_transfer(cap, ADMIN);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::ESameCoinType)]
    fun a_market_needs_two_different_coins() {
        let mut sc = ts::begin(ADMIN);
        let cap = market::create_market<BASE, BASE>(TICK, LOT, FEE, sc.ctx());
        transfer::public_transfer(cap, ADMIN);
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Resting orders lock funds                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_resting_bid_locks_its_quote_and_returns_the_rest() {
        let mut sc = start();
        // 1,000 base at 1.01 locks 1,010 quote.
        let (out, change, id) = bid(&mut sc, ALICE, P101, 1000, book::gtc(), 5000);
        assert!(out == 0, 0);
        assert!(change == 3990, 1);
        assert!(id != book::none_id(), 2);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (lb, lq) = market::locked(&m);
            assert!(lb == 0 && lq == 1010, 3);
            assert!(market::best_bid(&m) == P101, 4);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE]);
        sc.end();
    }

    #[test]
    fun a_resting_ask_locks_its_base() {
        let mut sc = start();
        let (out, change, _) = ask(&mut sc, ALICE, P101, 700, book::gtc(), 1000);
        assert!(out == 0 && change == 300, 0);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (lb, lq) = market::locked(&m);
            assert!(lb == 700 && lq == 0, 1);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE]);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EPriceNotOnTick)]
    fun a_price_off_the_tick_is_refused() {
        let mut sc = start();
        bid(&mut sc, ALICE, P101 + 1, 1000, book::gtc(), 5000);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EQuantityNotOnLot)]
    fun a_quantity_off_the_lot_is_refused() {
        let mut sc = start();
        bid(&mut sc, ALICE, P101, 1050, book::gtc(), 5000);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EInsufficientPayment)]
    fun a_payment_that_does_not_cover_the_lock_aborts() {
        let mut sc = start();
        // Needs 1,010.
        bid(&mut sc, ALICE, P101, 1000, book::gtc(), 1009);
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Settlement                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_taker_bid_pays_the_makers_price_less_the_fee_on_what_it_receives() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 1000, book::gtc(), 1000);

        // Bob bids 1.05 for 1,000; the ask is at 1.00, so he pays 1,000.
        let (out, change, id) = bid(&mut sc, BOB, P105, 1000, book::gtc(), 2000);
        assert!(id == book::none_id(), 0);
        // Fee: ceil(1000 * 10 / 10000) = 1 base.
        assert!(out == 999, 1);
        assert!(change == 1000, 2);

        // Alice is owed the quote, and nothing of hers is locked any more.
        let (ab, aq) = claimable(&mut sc, ALICE);
        assert!(ab == 0 && aq == 1000, 3);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (fb, fq) = market::fees(&m);
            assert!(fb == 1 && fq == 0, 4);
            let (lb, lq) = market::locked(&m);
            assert!(lb == 0 && lq == 0, 5);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB]);
        sc.end();
    }

    #[test]
    fun a_taker_ask_receives_the_bids_locked_quote_less_the_fee() {
        let mut sc = start();
        bid(&mut sc, ALICE, P102, 2000, book::gtc(), 2040);

        // Bob sells 2,000 at 1.00 into a bid at 1.02: 2,040 quote, fee 3.
        let (out, change, id) = ask(&mut sc, BOB, P100, 2000, book::ioc(), 2000);
        assert!(id == book::none_id(), 0);
        assert!(out == 2037, 1);
        assert!(change == 0, 2);

        let (ab, aq) = claimable(&mut sc, ALICE);
        assert!(ab == 2000 && aq == 0, 3);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (fb, fq) = market::fees(&m);
            // ceil(2040 * 10 / 10000) = ceil(2.04) = 3.
            assert!(fb == 0 && fq == 3, 4);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB]);
        sc.end();
    }

    #[test]
    fun a_partly_filled_bid_pays_for_the_fills_and_locks_the_rest_at_its_own_price() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);

        // 1,000 at 1.02: 300 fill at 1.00 for 300 quote, 700 rest at 1.02
        // locking 714. Owed 1,014 out of 2,000.
        let (out, change, id) = bid(&mut sc, BOB, P102, 1000, book::gtc(), 2000);
        assert!(id != book::none_id(), 0);
        assert!(out == 300 - 1, 1);
        assert!(change == 2000 - 1014, 2);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (lb, lq) = market::locked(&m);
            assert!(lb == 0 && lq == 714, 3);
            assert!(market::best_bid(&m) == P102, 4);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB]);
        sc.end();
    }

    #[test]
    fun a_partly_filled_maker_bid_refunds_exactly_its_remainder_on_cancel() {
        let mut sc = start();
        let (_, _, maker) = bid(&mut sc, ALICE, P101, 1000, book::gtc(), 1010);

        // Bob takes 400 of it.
        ask(&mut sc, BOB, P101, 400, book::ioc(), 400);
        cancel(&mut sc, ALICE, maker);

        // Alice gets her 400 base and the 606 quote behind the other 600.
        let (ab, aq) = claimable(&mut sc, ALICE);
        assert!(ab == 400 && aq == 606, 0);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (lb, lq) = market::locked(&m);
            assert!(lb == 0 && lq == 0, 1);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB]);
        sc.end();
    }

    #[test]
    fun one_taker_settles_against_many_makers_without_sending_them_coins() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 500, book::gtc(), 500);
        ask(&mut sc, CAROL, P100, 500, book::gtc(), 500);
        ask(&mut sc, ALICE, P101, 500, book::gtc(), 500);

        // 1,200: 500 + 500 at 1.00, 200 at 1.01. Cost 1,000 + 202.
        let (out, change, _) = bid(&mut sc, BOB, P101, 1200, book::ioc(), 1500);
        assert!(out == 1200 - 2, 0);
        assert!(change == 1500 - 1202, 1);

        let (ab, aq) = claimable(&mut sc, ALICE);
        let (cb, cq) = claimable(&mut sc, CAROL);
        assert!(ab == 0 && aq == 500 + 202, 2);
        assert!(cb == 0 && cq == 500, 3);
        assert_vault_balances(&mut sc, vector[ALICE, BOB, CAROL]);
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Order types through custody                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun an_ioc_remainder_neither_rests_nor_locks() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);

        let (out, change, id) = bid(&mut sc, BOB, P100, 1000, book::ioc(), 1000);
        assert!(id == book::none_id(), 0);
        assert!(out == 299, 1);
        assert!(change == 700, 2);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (lb, lq) = market::locked(&m);
            assert!(lb == 0 && lq == 0, 3);
            assert!(market::best_bid(&m) == book::none_id(), 4);
            ts::return_shared(m);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ENotFillable)]
    fun a_fill_or_kill_that_cannot_fill_reverts_the_payment_too() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);
        bid(&mut sc, BOB, P100, 1000, book::fok(), 1000);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::EWouldCross)]
    fun a_post_only_that_would_cross_aborts() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);
        bid(&mut sc, BOB, P101, 300, book::post_only(), 1000);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ESelfTrade)]
    fun trading_against_yourself_aborts() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);
        bid(&mut sc, ALICE, P100, 300, book::gtc(), 1000);
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Cancelling and withdrawing                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun cancelling_credits_the_refund_and_withdrawing_pays_it_once() {
        let mut sc = start();
        let (_, _, id) = ask(&mut sc, ALICE, P105, 800, book::gtc(), 800);
        cancel(&mut sc, ALICE, id);

        let (ab, aq) = claimable(&mut sc, ALICE);
        assert!(ab == 800 && aq == 0, 0);

        let (wb, wq) = withdraw(&mut sc, ALICE);
        assert!(wb == 800 && wq == 0, 1);

        // Nothing left, and a second withdrawal is harmless.
        let (wb2, wq2) = withdraw(&mut sc, ALICE);
        assert!(wb2 == 0 && wq2 == 0, 2);

        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (vb, vq) = market::vault_balances(&m);
            assert!(vb == 0 && vq == 0, 3);
            ts::return_shared(m);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::book::ENotOwner)]
    fun only_the_owner_can_cancel() {
        let mut sc = start();
        let (_, _, id) = ask(&mut sc, ALICE, P105, 800, book::gtc(), 800);
        cancel(&mut sc, BOB, id);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EOrderNotFound)]
    fun cancelling_a_filled_order_aborts() {
        let mut sc = start();
        let (_, _, id) = ask(&mut sc, ALICE, P100, 300, book::gtc(), 300);
        bid(&mut sc, BOB, P100, 300, book::ioc(), 300);
        cancel(&mut sc, ALICE, id);
        sc.end();
    }

    #[test]
    fun fees_go_to_the_cap_holder() {
        let mut sc = start();
        ask(&mut sc, ALICE, P100, 1000, book::gtc(), 1000);
        bid(&mut sc, BOB, P100, 1000, book::ioc(), 1000);   // 1 base fee
        bid(&mut sc, ALICE, P100, 2000, book::gtc(), 2000);
        ask(&mut sc, BOB, P100, 2000, book::ioc(), 2000);   // 2 quote fee

        sc.next_tx(ADMIN);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            let cap = sc.take_from_sender<MarketCap>();
            let (b, q) = market::collect_fees(&mut m, &cap, sc.ctx());
            assert!(b.value() == 1 && q.value() == 2, 0);
            coin::burn_for_testing(b);
            coin::burn_for_testing(q);
            let (fb, fq) = market::fees(&m);
            assert!(fb == 0 && fq == 0, 1);
            sc.return_to_sender(cap);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB]);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::EWrongMarket)]
    fun another_markets_cap_cannot_collect() {
        let mut sc = start();
        sc.next_tx(ADMIN);
        {
            // A second market, over the same coins. Its cap must not work on
            // the first.
            let other = market::create_market<BASE, QUOTE>(TICK, LOT, FEE, sc.ctx());
            let ids = ts::ids_for_sender<MarketCap>(&sc);
            let first_cap = sc.take_from_sender_by_id<MarketCap>(ids[0]);
            let first_market_id = market::cap_market_id(&first_cap);
            sc.return_to_sender(first_cap);
            sc.next_tx(ADMIN);

            let mut m = sc.take_shared_by_id<Market<BASE, QUOTE>>(first_market_id);
            let (b, q) = market::collect_fees(&mut m, &other, sc.ctx());
            coin::burn_for_testing(b);
            coin::burn_for_testing(q);
            ts::return_shared(m);
            transfer::public_transfer(other, ADMIN);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    /// Asks at 1.00 / 1.01 / 1.02, 500 each; bids at 0.99 / 0.98, 500 each.
    fun a_book(sc: &mut Scenario) {
        ask(sc, ALICE, P100, 500, book::gtc(), 500);
        ask(sc, CAROL, P101, 500, book::gtc(), 500);
        ask(sc, ALICE, P102, 500, book::gtc(), 500);
        bid(sc, CAROL, 990_000_000, 500, book::gtc(), 495);
        bid(sc, ALICE, 980_000_000, 500, book::gtc(), 490);
    }

    #[test]
    fun a_quote_budget_buys_whole_lots_across_levels_and_returns_the_rest() {
        let mut sc = start();
        a_book(&mut sc);

        sc.next_tx(BOB);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            // 1,200 quote: 500 at 1.00 (500), 500 at 1.01 (505), leaving 195.
            // At 1.02 a lot costs 102, so one lot: 100 base for 102. Left 93.
            let (quoted_out, quoted_used) = market::quote_quote_for_base(&m, 1200);

            let coin_in = coin::mint_for_testing<QUOTE>(1200, sc.ctx());
            let (out, change) = market::swap_quote_for_base(&mut m, coin_in, 0, sc.ctx());

            // 1,100 base, fee ceil(1.1) = 2.
            assert!(out.value() == 1098, 0);
            assert!(change.value() == 93, 1);
            // The read-only quote and execution agree to the unit.
            assert!(quoted_out == out.value(), 2);
            assert!(quoted_used == 1200 - change.value(), 3);

            coin::burn_for_testing(out);
            coin::burn_for_testing(change);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB, CAROL]);
        sc.end();
    }

    #[test]
    fun selling_base_takes_the_bids_best_first_and_returns_the_dust() {
        let mut sc = start();
        a_book(&mut sc);

        sc.next_tx(BOB);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            // 750 base: 700 whole lots trade -- 500 at 0.99, 200 at 0.98.
            let (quoted_out, quoted_used) = market::quote_base_for_quote(&m, 750);

            let coin_in = coin::mint_for_testing<BASE>(750, sc.ctx());
            let (out, change) = market::swap_base_for_quote(&mut m, coin_in, 0, sc.ctx());

            // 495 + 196 = 691 quote, fee ceil(0.691) = 1.
            assert!(out.value() == 690, 0);
            assert!(change.value() == 50, 1);
            assert!(quoted_out == out.value(), 2);
            assert!(quoted_used == 700, 3);

            coin::burn_for_testing(out);
            coin::burn_for_testing(change);
            ts::return_shared(m);
        };
        assert_vault_balances(&mut sc, vector[ALICE, BOB, CAROL]);
        sc.end();
    }

    #[test]
    fun a_budget_that_outruns_the_book_spends_only_what_is_there() {
        let mut sc = start();
        a_book(&mut sc);

        sc.next_tx(BOB);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            let coin_in = coin::mint_for_testing<QUOTE>(1_000_000, sc.ctx());
            let (out, change) = market::swap_quote_for_base(&mut m, coin_in, 0, sc.ctx());
            // All 1,500 base for 500 + 505 + 510.
            assert!(out.value() == 1500 - 2, 0);
            assert!(change.value() == 1_000_000 - 1515, 1);
            assert!(market::best_ask(&m) == book::none_id(), 2);
            coin::burn_for_testing(out);
            coin::burn_for_testing(change);
            ts::return_shared(m);
        };
        sc.end();
    }

    #[test]
    fun swapping_into_an_empty_side_returns_the_input_untouched() {
        let mut sc = start();
        sc.next_tx(BOB);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            let (q_out, q_used) = market::quote_quote_for_base(&m, 1000);
            assert!(q_out == 0 && q_used == 0, 0);

            let coin_in = coin::mint_for_testing<QUOTE>(1000, sc.ctx());
            let (out, change) = market::swap_quote_for_base(&mut m, coin_in, 0, sc.ctx());
            assert!(out.value() == 0 && change.value() == 1000, 1);
            coin::burn_for_testing(out);
            coin::burn_for_testing(change);

            // Under one lot of base cannot trade either.
            let dust = coin::mint_for_testing<BASE>(LOT - 1, sc.ctx());
            let (out2, change2) = market::swap_base_for_quote(&mut m, dust, 0, sc.ctx());
            assert!(out2.value() == 0 && change2.value() == LOT - 1, 2);
            coin::burn_for_testing(out2);
            coin::burn_for_testing(change2);
            ts::return_shared(m);
        };
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = braid_clob::market::ESlippage)]
    fun a_swap_below_its_minimum_aborts() {
        let mut sc = start();
        a_book(&mut sc);
        sc.next_tx(BOB);
        {
            let mut m = sc.take_shared<Market<BASE, QUOTE>>();
            let coin_in = coin::mint_for_testing<QUOTE>(1200, sc.ctx());
            let (out, change) = market::swap_quote_for_base(&mut m, coin_in, 1099, sc.ctx());
            coin::burn_for_testing(out);
            coin::burn_for_testing(change);
            ts::return_shared(m);
        };
        sc.end();
    }

    // ---------------------------------------------------------------- //
    // The vault, across a long sequence                                //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_vault_balances_to_the_unit_through_a_mixed_session() {
        let mut sc = start();
        let traders = vector[ALICE, BOB, CAROL];

        // A small deterministic generator, so the sequence is varied but
        // reproducible.
        let mut seed: u64 = 7;
        let mut resting = vector<u64>[];
        let mut step: u64 = 0;
        while (step < 60) {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            let who = traders[seed % 3];
            let action = (seed >> 8) % 5;
            // Prices 0.95 .. 1.05, quantities 1..10 lots.
            let price = 950_000_000 + ((seed >> 16) % 11) * TICK;
            let qty = (1 + (seed >> 24) % 10) * LOT;

            if (action == 0 && !resting.is_empty()) {
                let id = resting.pop_back();
                sc.next_tx(ADMIN);
                let m = sc.take_shared<Market<BASE, QUOTE>>();
                let live = book::has_order(market::book(&m), id);
                let owner = if (live) { book::order_owner(market::book(&m), id) } else { ADMIN };
                ts::return_shared(m);
                if (live) cancel(&mut sc, owner, id);
            } else if (action == 1) {
                withdraw(&mut sc, who);
            } else if (action % 2 == 0) {
                let (_, _, id) = bid_safely(&mut sc, who, price, qty);
                if (id != book::none_id()) resting.push_back(id);
            } else {
                let (_, _, id) = ask_safely(&mut sc, who, price, qty);
                if (id != book::none_id()) resting.push_back(id);
            };

            assert_vault_balances(&mut sc, traders);
            step = step + 1;
        };

        // The session must actually have traded in both directions, or the
        // check above proved nothing about settlement. Fees accrue only on
        // fills, so they are the witness.
        sc.next_tx(ADMIN);
        {
            let m = sc.take_shared<Market<BASE, QUOTE>>();
            let (fb, fq) = market::fees(&m);
            assert!(fb > 0 && fq > 0, 0);
            ts::return_shared(m);
        };
        sc.end();
    }

    // Self-trades abort, which would end the session. So when an order would
    // cross a side on which the same trader rests anything, it is moved one
    // tick short of crossing and placed post-only instead.

    fun bid_safely(sc: &mut Scenario, who: address, price: u64, qty: u64): (u64, u64, u64) {
        sc.next_tx(ADMIN);
        let m = sc.take_shared<Market<BASE, QUOTE>>();
        let best = market::best_ask(&m);
        let unsafe = best != book::none_id() && price >= best
            && rests_on_side(market::book(&m), who, false);
        ts::return_shared(m);
        if (unsafe) {
            bid(sc, who, best - TICK, qty, book::post_only(), qty * 2)
        } else {
            bid(sc, who, price, qty, book::gtc(), qty * 2)
        }
    }

    fun ask_safely(sc: &mut Scenario, who: address, price: u64, qty: u64): (u64, u64, u64) {
        sc.next_tx(ADMIN);
        let m = sc.take_shared<Market<BASE, QUOTE>>();
        let best = market::best_bid(&m);
        let unsafe = best != book::none_id() && price <= best
            && rests_on_side(market::book(&m), who, true);
        ts::return_shared(m);
        if (unsafe) {
            ask(sc, who, best + TICK, qty, book::post_only(), qty)
        } else {
            ask(sc, who, price, qty, book::gtc(), qty)
        }
    }

    fun rests_on_side(book: &book::Book, who: address, is_bid: bool): bool {
        let mut id = 1;
        while (id < 200) {
            if (book::has_order(book, id)
                && book::order_owner(book, id) == who
                && book::order_is_bid(book, id) == is_bid) {
                return true
            };
            id = id + 1;
        };
        false
    }
}
