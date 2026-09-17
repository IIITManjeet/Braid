#[test_only]
/// GENERATED FILE -- do not edit by hand.
///
/// Every expected value here was produced by the Rust replica in
/// `node/crates/braid-quote`, then checked against this Move code by the
/// Move VM. A failure means the two implementations disagree, which is
/// exactly what this file exists to detect.
///
/// Regenerate with:  cargo run -p braid-difftest
/// The RNG is seeded, so an unchanged implementation regenerates an
/// identical file.
module braid_clob::generated_market_diff_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use braid_clob::book;
    use braid_clob::market;

    struct BASE {}
    struct QUOTE {}

    const MAKER: address = @0xA;
    const TAKER: address = @0xB;

    struct Caps has key {
        base_mint: MintCapability<BASE>,
        base_burn: BurnCapability<BASE>,
        quote_mint: MintCapability<QUOTE>,
        quote_burn: BurnCapability<QUOTE>,
    }

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_clob);
        account::create_account_for_test(MAKER);
        account::create_account_for_test(TAKER);
        let (bb, bf, bm) = coin::initialize<BASE>(
            &braid, std::string::utf8(b"BASE"), std::string::utf8(b"BASE"), 8, false);
        let (qb, qf, qm) = coin::initialize<QUOTE>(
            &braid, std::string::utf8(b"QUOTE"), std::string::utf8(b"QUOTE"), 8, false);
        coin::destroy_freeze_cap(bf);
        coin::destroy_freeze_cap(qf);
        move_to(&braid, Caps { base_mint: bm, base_burn: bb, quote_mint: qm, quote_burn: qb });
    }

    fun signs(who: address): signer { account::create_signer_for_test(who) }

    fun mint_base(v: u64): Coin<BASE> acquires Caps {
        coin::mint<BASE>(v, &borrow_global<Caps>(@braid_clob).base_mint)
    }

    fun mint_quote(v: u64): Coin<QUOTE> acquires Caps {
        coin::mint<QUOTE>(v, &borrow_global<Caps>(@braid_clob).quote_mint)
    }

    fun burn_base(c: Coin<BASE>) acquires Caps {
        coin::burn<BASE>(c, &borrow_global<Caps>(@braid_clob).base_burn)
    }

    fun burn_quote(c: Coin<QUOTE>) acquires Caps {
        coin::burn<QUOTE>(c, &borrow_global<Caps>(@braid_clob).quote_burn)
    }

    fun rest(m: address, price: u64, qty: u64, is_bid: bool) acquires Caps {
        if (is_bid) {
            let pay = mint_quote(18446744073709551615);
            let (o, ch, _) = market::place_bid<BASE, QUOTE>(&signs(MAKER), m, price, qty, book::gtc(), pay);
            burn_base(o);
            burn_quote(ch);
        } else {
            let pay = mint_base(qty);
            let (o, ch, _) = market::place_ask<BASE, QUOTE>(&signs(MAKER), m, price, qty, book::gtc(), pay);
            burn_quote(o);
            burn_base(ch);
        }
    }


    #[test]
    fun market_case_0() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1400, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 4018000, true);
        rest(m, 10000000, 3864000, true);
        rest(m, 10000000, 488600, true);
        rest(m, 10000000, 784000, true);
        rest(m, 3770000000, 6637400, false);
        rest(m, 10000000, 5271000, true);
        rest(m, 10000000, 3603600, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 8161303);
        assert!(q == 2164183 && u == 8159788, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 51503);
        assert!(q == 503 && u == 50400, 1);
        let c = mint_quote(8161303);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 2164183 && coin::value(&ch) == 1515, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(51503);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 503 && coin::value(&ch) == 1103, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 3770000000, 4);
    }

    #[test]
    fun market_case_1() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 15000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 2061000000, 69255000, false);
        rest(m, 2075000000, 25875000, false);
        rest(m, 1617000000, 52395000, true);
        rest(m, 1978000000, 66540000, false);
        rest(m, 1779000000, 36930000, true);
        rest(m, 1746000000, 15570000, true);
        rest(m, 2262000000, 66060000, false);
        rest(m, 2101000000, 13575000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 4862);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 9986460248004);
        assert!(q == 177588644 && u == 104895000, 1);
        let c = mint_quote(4862);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 4862, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(9986460248004);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 177588644 && coin::value(&ch) == 9986355353004, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1978000000, 4);
    }

    #[test]
    fun market_case_2() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1200, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 3093600, true);
        rest(m, 5910000000, 2503200, false);
        rest(m, 1480000000, 3814800, true);
        rest(m, 1310000000, 4046400, true);
        rest(m, 10000000, 3429600, true);
        rest(m, 4340000000, 2060400, false);
        rest(m, 10000000, 1197600, true);
        rest(m, 690000000, 5120400, true);
        rest(m, 570000000, 4263600, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 9308);
        assert!(q == 1199 && u == 5208, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 7216320517188);
        assert!(q == 16985525 && u == 24966000, 1);
        let c = mint_quote(9308);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1199 && coin::value(&ch) == 4100, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(7216320517188);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 16985525 && coin::value(&ch) == 7216295551188, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 4340000000, 4);
    }

    #[test]
    fun market_case_3() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 900, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 4990000000, 3344400, false);
        rest(m, 10000000, 2992500, true);
        rest(m, 4300000000, 1208700, false);
        rest(m, 10000000, 3518100, true);
        rest(m, 10000000, 1001700, true);
        rest(m, 10000000, 1986300, true);
        rest(m, 4900000000, 793800, false);
        rest(m, 3120000000, 2270700, false);
        rest(m, 2160000000, 98100, false);
        rest(m, 10000000, 305100, true);
        rest(m, 210000000, 325800, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 96786149);
        assert!(q == 7715700 && u == 33072066, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 73041408115795);
        assert!(q == 166455 && u == 10129500, 1);
        let c = mint_quote(96786149);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 7715700 && coin::value(&ch) == 63714083, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(73041408115795);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 166455 && coin::value(&ch) == 73041397986295, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_4() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 20000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 570100000, 62080000, true);
        rest(m, 581300000, 68880000, true);
        rest(m, 605900000, 34420000, false);
        rest(m, 605500000, 22780000, false);
        rest(m, 586000000, 55100000, true);
        rest(m, 561900000, 61720000, true);
        rest(m, 629200000, 86040000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 753);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 8796);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(753);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 753, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(8796);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 8796, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 605500000, 4);
    }

    #[test]
    fun market_case_5() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1300, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1840000000, 392600, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 674507058);
        assert!(q == 392600 && u == 722384, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 55738512524);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(674507058);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 392600 && coin::value(&ch) == 673784674, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(55738512524);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 55738512524, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_6() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 50000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1805200000, 212200000, false);
        rest(m, 1757100000, 30450000, true);
        rest(m, 1780200000, 172850000, false);
        rest(m, 1788200000, 120600000, false);
        rest(m, 1776300000, 48150000, true);
        rest(m, 1776100000, 9650000, true);
        rest(m, 1782000000, 129750000, false);
        rest(m, 1743300000, 21750000, true);
        rest(m, 1757500000, 31600000, true);
        rest(m, 1768400000, 92300000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 94688);
        assert!(q == 49500 && u == 89010, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 93744371158747);
        assert!(q == 408720510 && u == 233900000, 1);
        let c = mint_quote(94688);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 49500 && coin::value(&ch) == 5678, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(93744371158747);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 408720510 && coin::value(&ch) == 93744137258747, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1780200000, 4);
    }

    #[test]
    fun market_case_7() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1700, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 2490000000, 7315100, false);
        rest(m, 5010000000, 5990800, false);
        rest(m, 10000000, 7668700, true);
        rest(m, 5370000000, 1322600, false);
        rest(m, 5590000000, 7542900, false);
        rest(m, 2400000000, 7073700, false);
        rest(m, 10000000, 5846300, true);
        rest(m, 1580000000, 4510100, true);
        rest(m, 3140000000, 2405500, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 120860726);
        assert!(q == 31127085 && u == 120856961, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 45417);
        assert!(q == 69137 && u == 44200, 1);
        let c = mint_quote(120860726);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 31127085 && coin::value(&ch) == 3765, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(45417);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 69137 && coin::value(&ch) == 1217, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 5590000000, 4);
    }

    #[test]
    fun market_case_8() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 700, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 3220000000, 2850400, false);
        rest(m, 3970000000, 1167600, false);
        rest(m, 3470000000, 2533300, false);
        rest(m, 2540000000, 2107700, false);
        rest(m, 2840000000, 3182200, false);
        rest(m, 450000000, 2153200, true);
        rest(m, 10000000, 1004500, true);
        rest(m, 10000000, 821800, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 13889338);
        assert!(q == 5112800 && u == 13888042, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 3447621);
        assert!(q == 981883 && u == 3447500, 1);
        let c = mint_quote(13889338);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 5112800 && coin::value(&ch) == 1296, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(3447621);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 981883 && coin::value(&ch) == 121, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 2840000000, 4);
    }

    #[test]
    fun market_case_9() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 150000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 802000000, 1200000, true);
        rest(m, 796700000, 526650000, true);
        rest(m, 798700000, 625500000, true);
        rest(m, 781300000, 36300000, true);
        rest(m, 772700000, 588750000, true);
        rest(m, 796300000, 72000000, true);
        rest(m, 786100000, 524700000, true);
        rest(m, 849600000, 462150000, false);
        rest(m, 843700000, 150600000, false);
        rest(m, 835200000, 56700000, false);
        rest(m, 807800000, 435450000, true);
        rest(m, 832700000, 221700000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 3216);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 863);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(3216);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 3216, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(863);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 863, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 832700000, 4);
    }

    #[test]
    fun market_case_10() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 1000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1766000000, 492000, true);
        rest(m, 1582000000, 1024000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 2652408280);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 46507224616);
        assert!(q == 2488840 && u == 1516000, 1);
        let c = mint_quote(2652408280);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 2652408280, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(46507224616);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 2488840 && coin::value(&ch) == 46505708616, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_11() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 1000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 802000000, 4287000, false);
        rest(m, 780000000, 934000, false);
        rest(m, 560000000, 424000, true);
        rest(m, 441000000, 1867000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 360697474724);
        assert!(q == 5220477 && u == 4166694, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 24479707392);
        assert!(q == 1060680 && u == 2291000, 1);
        let c = mint_quote(360697474724);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 5220477 && coin::value(&ch) == 360693308030, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(24479707392);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1060680 && coin::value(&ch) == 24477416392, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_12() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 400, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 420000000, 11200, true);
        rest(m, 3360000000, 1025600, false);
        rest(m, 4530000000, 114400, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 87865);
        assert!(q == 25974 && u == 87360, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 3879100163);
        assert!(q == 4699 && u == 11200, 1);
        let c = mint_quote(87865);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 25974 && coin::value(&ch) == 505, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(3879100163);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 4699 && coin::value(&ch) == 3879088963, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 3360000000, 4);
    }

    #[test]
    fun market_case_13() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 20000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1588000000, 18040000, true);
        rest(m, 1848000000, 6440000, true);
        rest(m, 1547000000, 42380000, true);
        rest(m, 1869000000, 93780000, false);
        rest(m, 1835000000, 90280000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 78171158793);
        assert!(q == 93780000 && u == 175274820, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 59772785810);
        assert!(q == 271774300 && u == 157140000, 1);
        let c = mint_quote(78171158793);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 93780000 && coin::value(&ch) == 77995883973, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(59772785810);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 271774300 && coin::value(&ch) == 59615645810, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_14() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 4000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1092000000, 9284000, false);
        rest(m, 994000000, 8568000, true);
        rest(m, 1222000000, 8344000, false);
        rest(m, 1120000000, 1596000, false);
        rest(m, 1328000000, 8176000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 53898373);
        assert!(q == 27397260 && u == 32979744, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 51952216805233);
        assert!(q == 8515740 && u == 8568000, 1);
        let c = mint_quote(53898373);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 27397260 && coin::value(&ch) == 20918629, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(51952216805233);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 8515740 && coin::value(&ch) == 51952208237233, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_15() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 90000, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1101000000, 136350000, true);
        rest(m, 1114700000, 197100000, true);
        rest(m, 1138200000, 40770000, false);
        rest(m, 1127800000, 27810000, true);
        rest(m, 1157900000, 225270000, false);
        rest(m, 1119000000, 324810000, true);
        rest(m, 1125200000, 128970000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 760782787);
        assert!(q == 265773960 && u == 307244547, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 198853765578);
        assert!(q == 908862499 && u == 815040000, 1);
        let c = mint_quote(760782787);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 265773960 && coin::value(&ch) == 453538240, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(198853765578);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 908862499 && coin::value(&ch) == 198038725578, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_16() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 50000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1326400000, 117550000, true);
        rest(m, 1320800000, 12000000, true);
        rest(m, 1334800000, 89550000, false);
        rest(m, 1292800000, 58500000, true);
        rest(m, 1354300000, 216600000, false);
        rest(m, 1369500000, 46150000, false);
        rest(m, 1345600000, 54250000, false);
        rest(m, 1343600000, 600000, false);
        rest(m, 1305700000, 129350000, true);
        rest(m, 1339600000, 240550000, false);
        rest(m, 1294600000, 75400000, true);
        rest(m, 1318100000, 154450000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 24454);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 458955181);
        assert!(q == 603274520 && u == 458950000, 1);
        let c = mint_quote(24454);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 24454, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(458955181);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 603274520 && coin::value(&ch) == 5181, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1334800000, 4);
    }

    #[test]
    fun market_case_17() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 110000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1528400000, 379280000, true);
        rest(m, 1508500000, 496210000, true);
        rest(m, 1527000000, 208010000, true);
        rest(m, 1514600000, 203280000, true);
        rest(m, 1576000000, 143770000, false);
        rest(m, 1533600000, 484440000, true);
        rest(m, 1573900000, 307780000, false);
        rest(m, 1506700000, 142010000, true);
        rest(m, 1560200000, 31790000, false);
        rest(m, 1510900000, 191290000, true);
        rest(m, 1527900000, 343750000, true);
        rest(m, 1527800000, 194920000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 65919913998);
        assert!(q == 483340000 && u == 760595220, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 8133);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(65919913998);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 483340000 && coin::value(&ch) == 65159318778, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(8133);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 8133, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_18() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1600, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 3190400, true);
        rest(m, 670000000, 1212800, true);
        rest(m, 1390000000, 7196800, false);
        rest(m, 2130000000, 1302400, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 87527940104);
        assert!(q == 8498350 && u == 12777664, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 2393);
        assert!(q == 1071 && u == 1600, 1);
        let c = mint_quote(87527940104);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 8498350 && coin::value(&ch) == 87515162440, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(2393);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1071 && coin::value(&ch) == 793, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_19() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 700, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 1900500, true);
        rest(m, 10000000, 3052000, true);
        rest(m, 10000000, 2463300, true);
        rest(m, 10000000, 3012100, true);
        rest(m, 200000000, 3189200, true);
        rest(m, 1700000000, 2898700, false);
        rest(m, 10000000, 3457300, true);
        rest(m, 4520000000, 3334100, false);
        rest(m, 380000000, 2886800, true);
        rest(m, 730000000, 996800, false);
        rest(m, 2930000000, 2957500, false);
        rest(m, 4270000000, 2132900, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 63426142429);
        assert!(q == 12307680 && u == 38498544, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 364524085675);
        assert!(q == 1871802 && u == 19961200, 1);
        let c = mint_quote(63426142429);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 12307680 && coin::value(&ch) == 63387643885, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(364524085675);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1871802 && coin::value(&ch) == 364504124475, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_20() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 90000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1753500000, 227610000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 1700);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 5664);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(1700);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 1700, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(5664);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 5664, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_21() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 130000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1743000000, 64220000, true);
        rest(m, 1785000000, 292370000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 93766018158391);
        assert!(q == 289446300 && u == 521880450, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 95617);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(93766018158391);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 289446300 && coin::value(&ch) == 93765496277941, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(95617);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 95617, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_22() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 19000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1513000000, 38038000, false);
        rest(m, 1810000000, 15732000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 26426846712131);
        assert!(q == 53232300 && u == 86026414, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 82833);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(26426846712131);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 53232300 && coin::value(&ch) == 26426760685717, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(82833);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 82833, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_23() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 800, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 1910400, true);
        rest(m, 3920000000, 2108800, false);
        rest(m, 10000000, 3124800, true);
        rest(m, 120000000, 830400, true);
        rest(m, 10000000, 192000, true);
        rest(m, 10000000, 3189600, true);
        rest(m, 3290000000, 872800, false);
        rest(m, 4040000000, 3430400, false);
        rest(m, 4060000000, 3840800, false);
        rest(m, 10000000, 1544000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 62965);
        assert!(q == 18398 && u == 60536, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 5734628874890);
        assert!(q == 199236 && u == 10791200, 1);
        let c = mint_quote(62965);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 18398 && coin::value(&ch) == 2429, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(5734628874890);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 199236 && coin::value(&ch) == 5734618083690, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 3290000000, 4);
    }

    #[test]
    fun market_case_24() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 14000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 2166000000, 44212000, false);
        rest(m, 1508000000, 23954000, true);
        rest(m, 1874000000, 12530000, false);
        rest(m, 2028000000, 6720000, false);
        rest(m, 1652000000, 62776000, true);
        rest(m, 1865000000, 68278000, false);
        rest(m, 2228000000, 13748000, false);
        rest(m, 1930000000, 2744000, false);
        rest(m, 1725000000, 3416000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 71628777993);
        assert!(q == 148217176 && u == 296137506, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 89910157);
        assert!(q == 145347743 && u == 89908000, 1);
        let c = mint_quote(71628777993);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 148217176 && coin::value(&ch) == 71332640487, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(89910157);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 145347743 && coin::value(&ch) == 2157, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_25() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 16000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1397000000, 14928000, true);
        rest(m, 1869000000, 49232000, false);
        rest(m, 1993000000, 67824000, false);
        rest(m, 1549000000, 60720000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 77517462922);
        assert!(q == 115885440 && u == 227187840, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 6986066359149);
        assert!(q == 113760599 && u == 75648000, 1);
        let c = mint_quote(77517462922);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 115885440 && coin::value(&ch) == 77290275082, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(6986066359149);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 113760599 && coin::value(&ch) == 6985990711149, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_26() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1100, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 4200000000, 2680700, false);
        rest(m, 10000000, 3031600, true);
        rest(m, 10000000, 4128300, true);
        rest(m, 2220000000, 2374900, false);
        rest(m, 3790000000, 3345100, false);
        rest(m, 3980000000, 1006500, false);
        rest(m, 1540000000, 1914000, false);
        rest(m, 4380000000, 5480200, false);
        rest(m, 10000000, 2696100, true);
        rest(m, 1640000000, 4288900, false);
        rest(m, 1630000000, 3414400, false);
        rest(m, 1450000000, 4296600, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 9923157204);
        assert!(q == 28798419 && u == 78995191, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 531);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(9923157204);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 28798419 && coin::value(&ch) == 9844162013, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(531);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 531, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_27() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1200, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 410400, true);
        rest(m, 10000000, 5912400, true);
        rest(m, 10000000, 3159600, true);
        rest(m, 10000000, 3806400, true);
        rest(m, 10000000, 861600, true);
        rest(m, 2660000000, 5539200, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 2758355522);
        assert!(q == 5483808 && u == 14734272, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 51476313413);
        assert!(q == 140088 && u == 14150400, 1);
        let c = mint_quote(2758355522);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 5483808 && coin::value(&ch) == 2743621250, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(51476313413);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 140088 && coin::value(&ch) == 51462163013, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_28() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1500, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 5676000, true);
        rest(m, 10000000, 648000, true);
        rest(m, 3660000000, 2848500, false);
        rest(m, 10000000, 1558500, true);
        rest(m, 10000000, 5316000, true);
        rest(m, 800000000, 5730000, true);
        rest(m, 620000000, 3912000, true);
        rest(m, 2360000000, 5824500, false);
        rest(m, 3130000000, 2052000, false);
        rest(m, 10000000, 4594500, true);
        rest(m, 2200000000, 1863000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 599484351524);
        assert!(q == 12575412 && u == 34692690, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 864);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(599484351524);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 12575412 && coin::value(&ch) == 599449658834, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(864);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 864, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_29() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 3000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1456000000, 12771000, false);
        rest(m, 1211000000, 7560000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 4640809);
        assert!(q == 3831000 && u == 4639341, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 3831337443438);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(4640809);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 3831000 && coin::value(&ch) == 1468, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(3831337443438);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 3831337443438, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1211000000, 4);
    }

    #[test]
    fun market_case_30() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 4000, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1113000000, 17876000, false);
        rest(m, 1083000000, 236000, false);
        rest(m, 1295000000, 9792000, false);
        rest(m, 716000000, 3360000, true);
        rest(m, 1155000000, 4804000, false);
        rest(m, 1117000000, 19880000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 4037);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 148095767579);
        assert!(q == 2403354 && u == 3360000, 1);
        let c = mint_quote(4037);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 4037, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(148095767579);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 2403354 && coin::value(&ch) == 148092407579, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1083000000, 4);
    }

    #[test]
    fun market_case_31() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 50000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1232600000, 126300000, false);
        rest(m, 1161200000, 152450000, true);
        rest(m, 1170500000, 116700000, true);
        rest(m, 1202800000, 197850000, false);
        rest(m, 1216200000, 166900000, false);
        rest(m, 1183000000, 142600000, true);
        rest(m, 1229500000, 50400000, false);
        rest(m, 1196000000, 18050000, true);
        rest(m, 1198800000, 145150000, true);
        rest(m, 1226300000, 169300000, false);
        rest(m, 1179900000, 194000000, true);
        rest(m, 1223400000, 232900000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 9543208041);
        assert!(q == 943650000 && u == 1151144390, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 77692);
        assert!(q == 59940 && u == 50000, 1);
        let c = mint_quote(9543208041);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 943650000 && coin::value(&ch) == 8392063651, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(77692);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 59940 && coin::value(&ch) == 27692, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_32() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 500, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 38000, true);
        rest(m, 3320000000, 928500, false);
        rest(m, 10000000, 727500, true);
        rest(m, 1300000000, 87500, true);
        rest(m, 4880000000, 1666500, false);
        rest(m, 10000000, 394500, true);
        rest(m, 410000000, 233000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 6101746275);
        assert!(q == 2595000 && u == 11215140, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 79579605179039);
        assert!(q == 220880 && u == 1480500, 1);
        let c = mint_quote(6101746275);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 2595000 && coin::value(&ch) == 6090531135, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(79579605179039);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 220880 && coin::value(&ch) == 79579603698539, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_33() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1900, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 3620000000, 3402900, false);
        rest(m, 10000000, 3355400, true);
        rest(m, 4040000000, 7533500, false);
        rest(m, 10000000, 2641000, true);
        rest(m, 2620000000, 6610100, false);
        rest(m, 3990000000, 8021800, false);
        rest(m, 10000000, 5342800, true);
        rest(m, 20000000, 5914700, true);
        rest(m, 10000000, 7525900, true);
        rest(m, 10000000, 279300, true);
        rest(m, 10000000, 7841300, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 99807275103495);
        assert!(q == 25565743 && u == 92079282, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 1581428061208);
        assert!(q == 388112 && u == 32900400, 1);
        let c = mint_quote(99807275103495);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 25565743 && coin::value(&ch) == 99807183024213, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(1581428061208);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 388112 && coin::value(&ch) == 1581395160808, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_34() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1700, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 7308300, true);
        rest(m, 10000000, 1009800, true);
        rest(m, 10000000, 2403800, true);
        rest(m, 840000000, 6800, true);
        rest(m, 10000000, 1827500, true);
        rest(m, 10000000, 5995900, true);
        rest(m, 4840000000, 8355500, false);
        rest(m, 10000000, 1264800, true);
        rest(m, 10000000, 948600, true);
        rest(m, 2390000000, 8265400, false);
        rest(m, 1950000000, 2703000, false);
        rest(m, 1680000000, 1917600, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 6531800240752);
        assert!(q == 21241500 && u == 68687344, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 879365556655);
        assert!(q == 213299 && u == 20765500, 1);
        let c = mint_quote(6531800240752);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 21241500 && coin::value(&ch) == 6531731553408, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(879365556655);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 213299 && coin::value(&ch) == 879344791155, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_35() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 120000, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1574600000, 273240000, false);
        rest(m, 1513500000, 419880000, true);
        rest(m, 1548100000, 266040000, false);
        rest(m, 1530100000, 568920000, true);
        rest(m, 1541600000, 589200000, false);
        rest(m, 1559700000, 466920000, false);
        rest(m, 1509900000, 162600000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 11613092921);
        assert!(q == 1593804600 && u == 2478666072, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 53858864359);
        assert!(q == 1749751109 && u == 1151400000, 1);
        let c = mint_quote(11613092921);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1593804600 && coin::value(&ch) == 9134426849, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(53858864359);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 1749751109 && coin::value(&ch) == 52707464359, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_36() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 200000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1261200000, 217600000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 30373);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 850539);
        assert!(q == 998870 && u == 800000, 1);
        let c = mint_quote(30373);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 30373, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(850539);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 998870 && coin::value(&ch) == 50539, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_37() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1600, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1280000000, 5964800, true);
        rest(m, 540000000, 4840000, true);
        rest(m, 10000000, 6548800, true);
        rest(m, 3230000000, 704000, false);
        rest(m, 870000000, 4972800, true);
        rest(m, 10000000, 5256000, true);
        rest(m, 1730000000, 2616000, false);
        rest(m, 640000000, 564800, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 8900);
        assert!(q == 4752 && u == 8304, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 74850);
        assert!(q == 93265 && u == 73600, 1);
        let c = mint_quote(8900);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 4752 && coin::value(&ch) == 596, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(74850);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 93265 && coin::value(&ch) == 1250, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1730000000, 4);
    }

    #[test]
    fun market_case_38() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 40000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1996900000, 129760000, true);
        rest(m, 1962800000, 43680000, true);
        rest(m, 1972200000, 141360000, true);
        rest(m, 1972700000, 64960000, true);
        rest(m, 2006900000, 144520000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 6117799);
        assert!(q == 3039696 && u == 6100976, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 52665562133388);
        assert!(q == 751714453 && u == 379760000, 1);
        let c = mint_quote(6117799);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 3039696 && coin::value(&ch) == 16823, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(52665562133388);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 751714453 && coin::value(&ch) == 52665182373388, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 2006900000, 4);
    }

    #[test]
    fun market_case_39() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 13000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1852000000, 53131000, false);
        rest(m, 1866000000, 34060000, false);
        rest(m, 1325000000, 38506000, true);
        rest(m, 1678000000, 23465000, false);
        rest(m, 1934000000, 57291000, false);
        rest(m, 1546000000, 14339000, false);
        rest(m, 1511000000, 20332000, true);
        rest(m, 1202000000, 30758000, true);
        rest(m, 1726000000, 9542000, false);
        rest(m, 1672000000, 48113000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 21148755);
        assert!(q == 13676000 && u == 21143096, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 2749819127543);
        assert!(q == 118713218 && u == 89596000, 1);
        let c = mint_quote(21148755);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 13676000 && coin::value(&ch) == 5659, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(2749819127543);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 118713218 && coin::value(&ch) == 2749729531543, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1546000000, 4);
    }

    #[test]
    fun market_case_40() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1700, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 4450600, true);
        rest(m, 3770000000, 5633800, false);
        rest(m, 10000000, 8437100, true);
        rest(m, 2420000000, 3530900, false);
        rest(m, 2680000000, 5268300, false);
        rest(m, 1950000000, 511700, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 1095);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 13131806740564);
        assert!(q == 128748 && u == 12887700, 1);
        let c = mint_quote(1095);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 1095, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(13131806740564);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 128748 && coin::value(&ch) == 13131793852864, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 1950000000, 4);
    }

    #[test]
    fun market_case_41() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 140000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1505900000, 518280000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 9518879924489);
        assert!(q == 513097200 && u == 780477852, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 82662);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(9518879924489);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 513097200 && coin::value(&ch) == 9518099446637, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(82662);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 82662, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_42() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 2000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 110000000, 4550000, true);
        rest(m, 3890000000, 8156000, false);
        rest(m, 2710000000, 3146000, false);
        rest(m, 10000000, 9692000, true);
        rest(m, 10000000, 8338000, true);
        rest(m, 10000000, 5816000, true);
        rest(m, 10000000, 5102000, true);
        rest(m, 1190000000, 3642000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 2983050380);
        assert!(q == 14942505 && u == 44586480, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 1115);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(2983050380);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 14942505 && coin::value(&ch) == 2938463900, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(1115);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 1115, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_43() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 7000, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1623000000, 30975000, true);
        rest(m, 2144000000, 13020000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 77862354308);
        assert!(q == 12889800 && u == 27914880, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 887);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(77862354308);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 12889800 && coin::value(&ch) == 77834439428, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(887);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 887, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_44() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 60000, 1);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1108800000, 265620000, false);
        rest(m, 1105500000, 49800000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 68947650329);
        assert!(q == 315388458 && u == 349573356, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 216098);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(68947650329);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 315388458 && coin::value(&ch) == 68598076973, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(216098);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 216098, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_45() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 40000, 0);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 931300000, 196600000, true);
        rest(m, 954500000, 22440000, true);
        rest(m, 932400000, 57240000, true);
        rest(m, 983900000, 122120000, false);
        rest(m, 953000000, 125200000, true);
        rest(m, 950500000, 24480000, true);
        rest(m, 927400000, 111280000, true);
        rest(m, 945400000, 160160000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 3185450607718);
        assert!(q == 122120000 && u == 120153868, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 51648377105078);
        assert!(q == 655083312 && u == 697400000, 1);
        let c = mint_quote(3185450607718);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 122120000 && coin::value(&ch) == 3185330453850, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(51648377105078);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 655083312 && coin::value(&ch) == 51647679705078, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_46() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 100, 100);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 10000000, 469200, true);
        rest(m, 420000000, 450900, true);
        rest(m, 1830000000, 383400, false);
        rest(m, 2230000000, 410800, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 95718291988);
        assert!(q == 786258 && u == 1617706, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 187773837873);
        assert!(q == 192129 && u == 920100, 1);
        let c = mint_quote(95718291988);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 786258 && coin::value(&ch) == 95716674282, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(187773837873);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 192129 && coin::value(&ch) == 187772917773, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_47() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(100000, 90000, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 1191300000, 260550000, false);
        rest(m, 1154900000, 385560000, true);
        rest(m, 1178900000, 361530000, false);
        rest(m, 1204000000, 38430000, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 49289145430);
        assert!(q == 659849490 && u == 782870652, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 776072);
        assert!(q == 830696 && u == 720000, 1);
        let c = mint_quote(49289145430);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 659849490 && coin::value(&ch) == 48506274778, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(776072);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 830696 && coin::value(&ch) == 56072, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }

    #[test]
    fun market_case_48() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(1000000, 11000, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 800000000, 6534000, false);
        rest(m, 685000000, 52008000, false);
        rest(m, 209000000, 8426000, true);
        rest(m, 548000000, 28864000, true);
        rest(m, 637000000, 41756000, false);
        rest(m, 862000000, 28215000, false);
        rest(m, 927000000, 30635000, false);
        rest(m, 584000000, 37202000, false);
        rest(m, 369000000, 52272000, true);
        rest(m, 795000000, 29788000, false);
        rest(m, 245000000, 52415000, true);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 66694);
        assert!(q == 109890 && u == 64240, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 73715929672);
        assert!(q == 49658840 && u == 141977000, 1);
        let c = mint_quote(66694);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 109890 && coin::value(&ch) == 2454, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(73715929672);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 49658840 && coin::value(&ch) == 73573952672, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 584000000, 4);
    }

    #[test]
    fun market_case_49() acquires Caps {
        setup();
        let (m, cap) = market::create_market<BASE, QUOTE>(10000000, 1800, 10);
        market::store_cap(&signs(MAKER), cap);
        rest(m, 3730000000, 6456600, false);
        rest(m, 4500000000, 8305200, false);
        rest(m, 1810000000, 968400, false);
        let (q, u) = market::quote_quote_for_base<BASE, QUOTE>(m, 9097666378010);
        assert!(q == 15714469 && u == 63209322, 0);
        let (q, u) = market::quote_base_for_quote<BASE, QUOTE>(m, 3605967259);
        assert!(q == 0 && u == 0, 1);
        let c = mint_quote(9097666378010);
        let (o, ch) = market::swap_quote_for_base<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 15714469 && coin::value(&ch) == 9097603168688, 2);
        burn_base(o);
        burn_quote(ch);
        let c = mint_base(3605967259);
        let (o, ch) = market::swap_base_for_quote<BASE, QUOTE>(&signs(TAKER), m, c, 0);
        assert!(coin::value(&o) == 0 && coin::value(&ch) == 3605967259, 3);
        burn_quote(o);
        burn_base(ch);
        assert!(market::best_ask<BASE, QUOTE>(m) == 18446744073709551615, 4);
    }
}
