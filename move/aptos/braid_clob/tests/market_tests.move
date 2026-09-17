#[test_only]
module braid_clob::market_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};

    use braid_clob::book;
    use braid_clob::market;

    struct BASE {}
    struct QUOTE {}

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

    /// Mint and burn authority for the two test coins. Sui's
    /// `coin::mint_for_testing` needs no such thing; an Aptos coin is a
    /// registered type with a tracked supply, so the test has to hold the caps.
    struct Caps has key {
        base_mint: MintCapability<BASE>,
        base_burn: BurnCapability<BASE>,
        quote_mint: MintCapability<QUOTE>,
        quote_burn: BurnCapability<QUOTE>,
    }

    fun who_signs(who: address): signer { account::create_signer_for_test(who) }

    fun mint_base(amount: u64): Coin<BASE> acquires Caps {
        coin::mint<BASE>(amount, &borrow_global<Caps>(@braid_clob).base_mint)
    }

    fun mint_quote(amount: u64): Coin<QUOTE> acquires Caps {
        coin::mint<QUOTE>(amount, &borrow_global<Caps>(@braid_clob).quote_mint)
    }

    fun burn_base(c: Coin<BASE>) acquires Caps {
        coin::burn<BASE>(c, &borrow_global<Caps>(@braid_clob).base_burn)
    }

    fun burn_quote(c: Coin<QUOTE>) acquires Caps {
        coin::burn<QUOTE>(c, &borrow_global<Caps>(@braid_clob).quote_burn)
    }

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_clob);
        account::create_account_for_test(ADMIN);
        account::create_account_for_test(ALICE);
        account::create_account_for_test(BOB);
        account::create_account_for_test(CAROL);

        let (base_burn, base_freeze, base_mint) = coin::initialize<BASE>(
            &braid, std::string::utf8(b"BASE"), std::string::utf8(b"BASE"), 8, true,
        );
        let (quote_burn, quote_freeze, quote_mint) = coin::initialize<QUOTE>(
            &braid, std::string::utf8(b"QUOTE"), std::string::utf8(b"QUOTE"), 6, true,
        );
        coin::destroy_freeze_cap(base_freeze);
        coin::destroy_freeze_cap(quote_freeze);

        move_to(&braid, Caps { base_mint, base_burn, quote_mint, quote_burn });
    }

    /// Create the market and park ADMIN's cap, returning the market address.
    fun start(): address {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(TICK, LOT, FEE);
        market::store_cap(&who_signs(ADMIN), cap);
        m
    }

    /// Place a bid as `who`. Returns `(base_out, quote_change, order_id)`.
    fun bid(m: address, who: address, price: u64, qty: u64, ty: u8, pay: u64): (u64, u64, u64) acquires Caps {
        let payment = mint_quote(pay);
        let (out, change, id) =
            market::place_bid<BASE, QUOTE>(&who_signs(who), m, price, qty, ty, payment);
        let (o, c) = (coin::value(&out), coin::value(&change));
        burn_base(out);
        burn_quote(change);
        (o, c, id)
    }

    /// Place an ask as `who`. Returns `(quote_out, base_change, order_id)`.
    fun ask(m: address, who: address, price: u64, qty: u64, ty: u8, pay: u64): (u64, u64, u64) acquires Caps {
        let payment = mint_base(pay);
        let (out, change, id) =
            market::place_ask<BASE, QUOTE>(&who_signs(who), m, price, qty, ty, payment);
        let (o, c) = (coin::value(&out), coin::value(&change));
        burn_quote(out);
        burn_base(change);
        (o, c, id)
    }

    fun cancel(m: address, who: address, id: u64) {
        market::cancel_order<BASE, QUOTE>(&who_signs(who), m, id);
    }

    /// Withdraw as `who`. Returns `(base, quote)`.
    fun withdraw(m: address, who: address): (u64, u64) acquires Caps {
        let (b, q) = market::withdraw<BASE, QUOTE>(&who_signs(who), m);
        let (bv, qv) = (coin::value(&b), coin::value(&q));
        burn_base(b);
        burn_quote(q);
        (bv, qv)
    }

    fun claimable(m: address, who: address): (u64, u64) {
        let (b, q) = market::claimable<BASE, QUOTE>(m, who);
        (b, q)
    }

    /// The vault holds exactly what is locked plus what the listed traders can
    /// claim. Every test that moves money ends by checking this.
    fun assert_vault_balances(m: address, traders: vector<address>) {
        let (vault_base, vault_quote) = market::vault_balances<BASE, QUOTE>(m);
        let (locked_base, locked_quote) = market::locked<BASE, QUOTE>(m);
        let claim_base = 0;
        let claim_quote = 0;
        let i = 0;
        while (i < traders.length()) {
            let (b, q) = market::claimable<BASE, QUOTE>(m, traders[i]);
            claim_base = claim_base + b;
            claim_quote = claim_quote + q;
            i = i + 1;
        };
        assert!(vault_base == locked_base + claim_base, 900);
        assert!(vault_quote == locked_quote + claim_quote, 901);
    }

    // ---------------------------------------------------------------- //
    // Creation                                                         //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_new_market_is_empty_and_holds_its_parameters() {
        let m = start();
        {
            assert!(market::tick_size<BASE, QUOTE>(m) == TICK, 0);
            assert!(market::lot_size<BASE, QUOTE>(m) == LOT, 1);
            assert!(market::taker_fee_bps<BASE, QUOTE>(m) == FEE, 2);
            assert!(market::best_bid<BASE, QUOTE>(m) == book::none_id(), 3);
            assert!(market::best_ask<BASE, QUOTE>(m) == book::none_id(), 4);
            let (vb, vq) = market::vault_balances<BASE, QUOTE>(m);
            assert!(vb == 0 && vq == 0, 5);

            // The cap ADMIN was handed at creation names this market.
            assert!(market::stored_cap_market_id(ADMIN) == m, 6);
        };
    }

    #[test]
    #[expected_failure(abort_code = market::EInvalidSizes)]
    fun sizes_whose_product_is_not_a_multiple_of_the_scale_are_refused() {
        setup();
        // 1e7 * 99 is not a multiple of 1e9: some fill values would round.
        let (_m, cap) = market::create_market<BASE, QUOTE>(TICK, 99, FEE);
        market::store_cap(&who_signs(ADMIN), cap);
    }

    #[test]
    #[expected_failure(abort_code = market::EInvalidFee)]
    fun a_fee_above_the_maximum_is_refused() {
        setup();
        let (_m, cap) = market::create_market<BASE, QUOTE>(TICK, LOT, 101);
        market::store_cap(&who_signs(ADMIN), cap);
    }

    #[test]
    #[expected_failure(abort_code = market::ESameCoinType)]
    fun a_market_needs_two_different_coins() {
        setup();
        let (_m, cap) = market::create_market<BASE, BASE>(TICK, LOT, FEE);
        market::store_cap(&who_signs(ADMIN), cap);
    }

    // ---------------------------------------------------------------- //
    // Resting orders lock funds                                        //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_resting_bid_locks_its_quote_and_returns_the_rest() acquires Caps {
        let m = start();
        // 1,000 base at 1.01 locks 1,010 quote.
        let (out, change, id) = bid(m, ALICE, P101, 1000, book::gtc(), 5000);
        assert!(out == 0, 0);
        assert!(change == 3990, 1);
        assert!(id != book::none_id(), 2);
        {
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 0 && lq == 1010, 3);
            assert!(market::best_bid<BASE, QUOTE>(m) == P101, 4);
        };
        assert_vault_balances(m, vector[ALICE]);
    }

    #[test]
    fun a_resting_ask_locks_its_base() acquires Caps {
        let m = start();
        let (out, change, _) = ask(m, ALICE, P101, 700, book::gtc(), 1000);
        assert!(out == 0 && change == 300, 0);
        {
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 700 && lq == 0, 1);
        };
        assert_vault_balances(m, vector[ALICE]);
    }

    #[test]
    #[expected_failure(abort_code = market::EPriceNotOnTick)]
    fun a_price_off_the_tick_is_refused() acquires Caps {
        let m = start();
        bid(m, ALICE, P101 + 1, 1000, book::gtc(), 5000);
    }

    #[test]
    #[expected_failure(abort_code = market::EQuantityNotOnLot)]
    fun a_quantity_off_the_lot_is_refused() acquires Caps {
        let m = start();
        bid(m, ALICE, P101, 1050, book::gtc(), 5000);
    }

    #[test]
    #[expected_failure(abort_code = market::EInsufficientPayment)]
    fun a_payment_that_does_not_cover_the_lock_aborts() acquires Caps {
        let m = start();
        // Needs 1,010.
        bid(m, ALICE, P101, 1000, book::gtc(), 1009);
    }

    // ---------------------------------------------------------------- //
    // Settlement                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun a_taker_bid_pays_the_makers_price_less_the_fee_on_what_it_receives() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 1000, book::gtc(), 1000);

        // Bob bids 1.05 for 1,000; the ask is at 1.00, so he pays 1,000.
        let (out, change, id) = bid(m, BOB, P105, 1000, book::gtc(), 2000);
        assert!(id == book::none_id(), 0);
        // Fee: ceil(1000 * 10 / 10000) = 1 base.
        assert!(out == 999, 1);
        assert!(change == 1000, 2);

        // Alice is owed the quote, and nothing of hers is locked any more.
        let (ab, aq) = claimable(m, ALICE);
        assert!(ab == 0 && aq == 1000, 3);
        {
            let (fb, fq) = market::fees<BASE, QUOTE>(m);
            assert!(fb == 1 && fq == 0, 4);
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 0 && lq == 0, 5);
        };
        assert_vault_balances(m, vector[ALICE, BOB]);
    }

    #[test]
    fun a_taker_ask_receives_the_bids_locked_quote_less_the_fee() acquires Caps {
        let m = start();
        bid(m, ALICE, P102, 2000, book::gtc(), 2040);

        // Bob sells 2,000 at 1.00 into a bid at 1.02: 2,040 quote, fee 3.
        let (out, change, id) = ask(m, BOB, P100, 2000, book::ioc(), 2000);
        assert!(id == book::none_id(), 0);
        assert!(out == 2037, 1);
        assert!(change == 0, 2);

        let (ab, aq) = claimable(m, ALICE);
        assert!(ab == 2000 && aq == 0, 3);
        {
            let (fb, fq) = market::fees<BASE, QUOTE>(m);
            // ceil(2040 * 10 / 10000) = ceil(2.04) = 3.
            assert!(fb == 0 && fq == 3, 4);
        };
        assert_vault_balances(m, vector[ALICE, BOB]);
    }

    #[test]
    fun a_partly_filled_bid_pays_for_the_fills_and_locks_the_rest_at_its_own_price() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 300, book::gtc(), 300);

        // 1,000 at 1.02: 300 fill at 1.00 for 300 quote, 700 rest at 1.02
        // locking 714. Owed 1,014 out of 2,000.
        let (out, change, id) = bid(m, BOB, P102, 1000, book::gtc(), 2000);
        assert!(id != book::none_id(), 0);
        assert!(out == 300 - 1, 1);
        assert!(change == 2000 - 1014, 2);
        {
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 0 && lq == 714, 3);
            assert!(market::best_bid<BASE, QUOTE>(m) == P102, 4);
        };
        assert_vault_balances(m, vector[ALICE, BOB]);
    }

    #[test]
    fun a_partly_filled_maker_bid_refunds_exactly_its_remainder_on_cancel() acquires Caps {
        let m = start();
        let (_, _, maker) = bid(m, ALICE, P101, 1000, book::gtc(), 1010);

        // Bob takes 400 of it.
        ask(m, BOB, P101, 400, book::ioc(), 400);
        cancel(m, ALICE, maker);

        // Alice gets her 400 base and the 606 quote behind the other 600.
        let (ab, aq) = claimable(m, ALICE);
        assert!(ab == 400 && aq == 606, 0);
        {
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 0 && lq == 0, 1);
        };
        assert_vault_balances(m, vector[ALICE, BOB]);
    }

    #[test]
    fun one_taker_settles_against_many_makers_without_sending_them_coins() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 500, book::gtc(), 500);
        ask(m, CAROL, P100, 500, book::gtc(), 500);
        ask(m, ALICE, P101, 500, book::gtc(), 500);

        // 1,200: 500 + 500 at 1.00, 200 at 1.01. Cost 1,000 + 202.
        let (out, change, _) = bid(m, BOB, P101, 1200, book::ioc(), 1500);
        assert!(out == 1200 - 2, 0);
        assert!(change == 1500 - 1202, 1);

        let (ab, aq) = claimable(m, ALICE);
        let (cb, cq) = claimable(m, CAROL);
        assert!(ab == 0 && aq == 500 + 202, 2);
        assert!(cb == 0 && cq == 500, 3);
        assert_vault_balances(m, vector[ALICE, BOB, CAROL]);
    }

    // ---------------------------------------------------------------- //
    // Order types through custody                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun an_ioc_remainder_neither_rests_nor_locks() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 300, book::gtc(), 300);

        let (out, change, id) = bid(m, BOB, P100, 1000, book::ioc(), 1000);
        assert!(id == book::none_id(), 0);
        assert!(out == 299, 1);
        assert!(change == 700, 2);
        {
            let (lb, lq) = market::locked<BASE, QUOTE>(m);
            assert!(lb == 0 && lq == 0, 3);
            assert!(market::best_bid<BASE, QUOTE>(m) == book::none_id(), 4);
        };
    }

    #[test]
    #[expected_failure(abort_code = book::ENotFillable)]
    fun a_fill_or_kill_that_cannot_fill_reverts_the_payment_too() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 300, book::gtc(), 300);
        bid(m, BOB, P100, 1000, book::fok(), 1000);
    }

    #[test]
    #[expected_failure(abort_code = book::EWouldCross)]
    fun a_post_only_that_would_cross_aborts() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 300, book::gtc(), 300);
        bid(m, BOB, P101, 300, book::post_only(), 1000);
    }

    #[test]
    #[expected_failure(abort_code = book::ESelfTrade)]
    fun trading_against_yourself_aborts() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 300, book::gtc(), 300);
        bid(m, ALICE, P100, 300, book::gtc(), 1000);
    }

    // ---------------------------------------------------------------- //
    // Cancelling and withdrawing                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun cancelling_credits_the_refund_and_withdrawing_pays_it_once() acquires Caps {
        let m = start();
        let (_, _, id) = ask(m, ALICE, P105, 800, book::gtc(), 800);
        cancel(m, ALICE, id);

        let (ab, aq) = claimable(m, ALICE);
        assert!(ab == 800 && aq == 0, 0);

        let (wb, wq) = withdraw(m, ALICE);
        assert!(wb == 800 && wq == 0, 1);

        // Nothing left, and a second withdrawal is harmless.
        let (wb2, wq2) = withdraw(m, ALICE);
        assert!(wb2 == 0 && wq2 == 0, 2);
        {
            let (vb, vq) = market::vault_balances<BASE, QUOTE>(m);
            assert!(vb == 0 && vq == 0, 3);
        };
    }

    #[test]
    #[expected_failure(abort_code = book::ENotOwner)]
    fun only_the_owner_can_cancel() acquires Caps {
        let m = start();
        let (_, _, id) = ask(m, ALICE, P105, 800, book::gtc(), 800);
        cancel(m, BOB, id);
    }

    #[test]
    #[expected_failure(abort_code = market::EOrderNotFound)]
    fun cancelling_a_filled_order_aborts() acquires Caps {
        let m = start();
        let (_, _, id) = ask(m, ALICE, P100, 300, book::gtc(), 300);
        bid(m, BOB, P100, 300, book::ioc(), 300);
        cancel(m, ALICE, id);
    }

    #[test]
    fun fees_go_to_the_cap_holder() acquires Caps {
        let m = start();
        ask(m, ALICE, P100, 1000, book::gtc(), 1000);
        bid(m, BOB, P100, 1000, book::ioc(), 1000);   // 1 base fee
        bid(m, ALICE, P100, 2000, book::gtc(), 2000);
        ask(m, BOB, P100, 2000, book::ioc(), 2000);   // 2 quote fee
        {
            let (b, q) = market::collect_fees_stored<BASE, QUOTE>(&who_signs(ADMIN), m);
            assert!(coin::value(&b) == 1 && coin::value(&q) == 2, 0);
            burn_base(b);
            burn_quote(q);
            let (fb, fq) = market::fees<BASE, QUOTE>(m);
            assert!(fb == 0 && fq == 0, 1);
        };
        assert_vault_balances(m, vector[ALICE, BOB]);
    }

    #[test]
    #[expected_failure(abort_code = market::EWrongMarket)]
    fun another_markets_cap_cannot_collect() acquires Caps {
        let m = start();
        // A second market, over the same coins. Its cap must not work on the
        // first. On Sui this test has to fish both caps out of the sender's
        // inventory by id; here a market is just an address.
        let (_other_m, other) = market::create_market<BASE, QUOTE>(TICK, LOT, FEE);
        let (b, q) = market::collect_fees<BASE, QUOTE>(m, &other);
        burn_base(b);
        burn_quote(q);
        market::store_cap(&who_signs(BOB), other);
    }

    // ---------------------------------------------------------------- //
    // Swaps                                                            //
    // ---------------------------------------------------------------- //

    /// Asks at 1.00 / 1.01 / 1.02, 500 each; bids at 0.99 / 0.98, 500 each.
    fun a_book(m: address) acquires Caps {
        ask(m, ALICE, P100, 500, book::gtc(), 500);
        ask(m, CAROL, P101, 500, book::gtc(), 500);
        ask(m, ALICE, P102, 500, book::gtc(), 500);
        bid(m, CAROL, 990_000_000, 500, book::gtc(), 495);
        bid(m, ALICE, 980_000_000, 500, book::gtc(), 490);
    }

    #[test]
    fun a_quote_budget_buys_whole_lots_across_levels_and_returns_the_rest() acquires Caps {
        let m = start();
        a_book(m);
        {
            // 1,200 quote: 500 at 1.00 (500), 500 at 1.01 (505), leaving 195.
            // At 1.02 a lot costs 102, so one lot: 100 base for 102. Left 93.
            let (quoted_out, quoted_used) = market::quote_quote_for_base<BASE, QUOTE>(m, 1200);

            let coin_in = mint_quote(1200);
            let (out, change) = market::swap_quote_for_base<BASE, QUOTE>(&who_signs(BOB), m, coin_in, 0);

            // 1,100 base, fee ceil(1.1) = 2.
            assert!(coin::value(&out) == 1098, 0);
            assert!(coin::value(&change) == 93, 1);
            // The read-only quote and execution agree to the unit.
            assert!(quoted_out == coin::value(&out), 2);
            assert!(quoted_used == 1200 - coin::value(&change), 3);

            burn_base(out);
            burn_quote(change);
        };
        assert_vault_balances(m, vector[ALICE, BOB, CAROL]);
    }

    #[test]
    fun selling_base_takes_the_bids_best_first_and_returns_the_dust() acquires Caps {
        let m = start();
        a_book(m);
        {
            // 750 base: 700 whole lots trade -- 500 at 0.99, 200 at 0.98.
            let (quoted_out, quoted_used) = market::quote_base_for_quote<BASE, QUOTE>(m, 750);

            let coin_in = mint_base(750);
            let (out, change) = market::swap_base_for_quote<BASE, QUOTE>(&who_signs(BOB), m, coin_in, 0);

            // 495 + 196 = 691 quote, fee ceil(0.691) = 1.
            assert!(coin::value(&out) == 690, 0);
            assert!(coin::value(&change) == 50, 1);
            assert!(quoted_out == coin::value(&out), 2);
            assert!(quoted_used == 700, 3);

            burn_quote(out);
            burn_base(change);
        };
        assert_vault_balances(m, vector[ALICE, BOB, CAROL]);
    }

    #[test]
    fun a_budget_that_outruns_the_book_spends_only_what_is_there() acquires Caps {
        let m = start();
        a_book(m);
        {
            let coin_in = mint_quote(1_000_000);
            let (out, change) = market::swap_quote_for_base<BASE, QUOTE>(&who_signs(BOB), m, coin_in, 0);
            // All 1,500 base for 500 + 505 + 510.
            assert!(coin::value(&out) == 1500 - 2, 0);
            assert!(coin::value(&change) == 1_000_000 - 1515, 1);
            assert!(market::best_ask<BASE, QUOTE>(m) == book::none_id(), 2);
            burn_base(out);
            burn_quote(change);
        };
    }

    #[test]
    fun swapping_into_an_empty_side_returns_the_input_untouched() acquires Caps {
        let m = start();
        {
            let (q_out, q_used) = market::quote_quote_for_base<BASE, QUOTE>(m, 1000);
            assert!(q_out == 0 && q_used == 0, 0);

            let coin_in = mint_quote(1000);
            let (out, change) = market::swap_quote_for_base<BASE, QUOTE>(&who_signs(BOB), m, coin_in, 0);
            assert!(coin::value(&out) == 0 && coin::value(&change) == 1000, 1);
            burn_base(out);
            burn_quote(change);

            // Under one lot of base cannot trade either.
            let dust = mint_base(LOT - 1);
            let (out2, change2) = market::swap_base_for_quote<BASE, QUOTE>(&who_signs(BOB), m, dust, 0);
            assert!(coin::value(&out2) == 0 && coin::value(&change2) == LOT - 1, 2);
            burn_quote(out2);
            burn_base(change2);
        };
    }

    #[test]
    #[expected_failure(abort_code = market::ESlippage)]
    fun a_swap_below_its_minimum_aborts() acquires Caps {
        let m = start();
        a_book(m);
        {
            let coin_in = mint_quote(1200);
            let (out, change) = market::swap_quote_for_base<BASE, QUOTE>(&who_signs(BOB), m, coin_in, 1099);
            burn_base(out);
            burn_quote(change);
        };
    }

    // ---------------------------------------------------------------- //
    // The vault, across a long sequence                                //
    // ---------------------------------------------------------------- //

    #[test]
    fun the_vault_balances_to_the_unit_through_a_mixed_session() acquires Caps {
        let m = start();
        let traders = vector[ALICE, BOB, CAROL];

        // A small deterministic generator, so the sequence is varied but
        // reproducible.
        let seed: u64 = 7;
        let resting = vector<u64>[];
        let step: u64 = 0;
        while (step < 60) {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            let who = traders[seed % 3];
            let action = (seed >> 8) % 5;
            // Prices 0.95 .. 1.05, quantities 1..10 lots.
            let price = 950_000_000 + ((seed >> 16) % 11) * TICK;
            let qty = (1 + (seed >> 24) % 10) * LOT;

            if (action == 0 && !resting.is_empty()) {
                let id = resting.pop_back();
                let live = market::has_order<BASE, QUOTE>(m, id);
                let owner = if (live) { market::order_owner<BASE, QUOTE>(m, id) } else { ADMIN };
                if (live) cancel(m, owner, id);
            } else if (action == 1) {
                withdraw(m, who);
            } else if (action % 2 == 0) {
                let (_, _, id) = bid_safely(m, who, price, qty);
                if (id != book::none_id()) resting.push_back(id);
            } else {
                let (_, _, id) = ask_safely(m, who, price, qty);
                if (id != book::none_id()) resting.push_back(id);
            };

            assert_vault_balances(m, traders);
            step = step + 1;
        };

        // The session must actually have traded in both directions, or the
        // check above proved nothing about settlement. Fees accrue only on
        // fills, so they are the witness.
        {
            let (fb, fq) = market::fees<BASE, QUOTE>(m);
            assert!(fb > 0 && fq > 0, 0);
        };
    }

    // Self-trades abort, which would end the session. So when an order would
    // cross a side on which the same trader rests anything, it is moved one
    // tick short of crossing and placed post-only instead.

    fun bid_safely(m: address, who: address, price: u64, qty: u64): (u64, u64, u64) acquires Caps {
        let best = market::best_ask<BASE, QUOTE>(m);
        let unsafe = best != book::none_id() && price >= best
            && rests_on_side(m, who, false);
        if (unsafe) {
            bid(m, who, best - TICK, qty, book::post_only(), qty * 2)
        } else {
            bid(m, who, price, qty, book::gtc(), qty * 2)
        }
    }

    fun ask_safely(m: address, who: address, price: u64, qty: u64): (u64, u64, u64) acquires Caps {
        let best = market::best_bid<BASE, QUOTE>(m);
        let unsafe = best != book::none_id() && price <= best
            && rests_on_side(m, who, true);
        if (unsafe) {
            ask(m, who, best + TICK, qty, book::post_only(), qty)
        } else {
            ask(m, who, price, qty, book::gtc(), qty)
        }
    }

    /// Sui passes `&Book` here; a reference cannot leave the market module on
    /// Aptos, so this walks the forwarded accessors instead.
    fun rests_on_side(m: address, who: address, is_bid: bool): bool {
        let id = 1;
        while (id < 200) {
            if (market::has_order<BASE, QUOTE>(m, id)
                && market::order_owner<BASE, QUOTE>(m, id) == who
                && market::order_is_bid<BASE, QUOTE>(m, id) == is_bid) {
                return true
            };
            id = id + 1;
        };
        false
    }
}
