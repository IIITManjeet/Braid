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
    use sui::coin;
    use sui::test_scenario::{Self as ts, Scenario};
    use braid_clob::book;
    use braid_clob::market::{Self, Market};

    public struct BASE has drop {}
    public struct QUOTE has drop {}

    const MAKER: address = @0xA;
    const TAKER: address = @0xB;

    fun rest(sc: &mut Scenario, m: &mut Market<BASE, QUOTE>, price: u64, qty: u64, is_bid: bool) {
        if (is_bid) {
            let pay = coin::mint_for_testing<QUOTE>(18446744073709551615, sc.ctx());
            let (o, ch, _) = market::place_bid(m, price, qty, book::gtc(), pay, sc.ctx());
            coin::burn_for_testing(o);
            coin::burn_for_testing(ch);
        } else {
            let pay = coin::mint_for_testing<BASE>(qty, sc.ctx());
            let (o, ch, _) = market::place_ask(m, price, qty, book::gtc(), pay, sc.ctx());
            coin::burn_for_testing(o);
            coin::burn_for_testing(ch);
        }
    }


    #[test]
    fun market_case_0() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1400, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 4018000, true);
        rest(&mut sc, &mut m, 10000000, 3864000, true);
        rest(&mut sc, &mut m, 10000000, 488600, true);
        rest(&mut sc, &mut m, 10000000, 784000, true);
        rest(&mut sc, &mut m, 3770000000, 6637400, false);
        rest(&mut sc, &mut m, 10000000, 5271000, true);
        rest(&mut sc, &mut m, 10000000, 3603600, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 8161303);
        assert!(q == 2164183 && u == 8159788, 0);
        let (q, u) = market::quote_base_for_quote(&m, 51503);
        assert!(q == 503 && u == 50400, 1);
        let c = coin::mint_for_testing<QUOTE>(8161303, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 2164183 && ch.value() == 1515, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(51503, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 503 && ch.value() == 1103, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 3770000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_1() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 15000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 2061000000, 69255000, false);
        rest(&mut sc, &mut m, 2075000000, 25875000, false);
        rest(&mut sc, &mut m, 1617000000, 52395000, true);
        rest(&mut sc, &mut m, 1978000000, 66540000, false);
        rest(&mut sc, &mut m, 1779000000, 36930000, true);
        rest(&mut sc, &mut m, 1746000000, 15570000, true);
        rest(&mut sc, &mut m, 2262000000, 66060000, false);
        rest(&mut sc, &mut m, 2101000000, 13575000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 4862);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 9986460248004);
        assert!(q == 177588644 && u == 104895000, 1);
        let c = coin::mint_for_testing<QUOTE>(4862, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 4862, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(9986460248004, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 177588644 && ch.value() == 9986355353004, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1978000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_2() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1200, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 3093600, true);
        rest(&mut sc, &mut m, 5910000000, 2503200, false);
        rest(&mut sc, &mut m, 1480000000, 3814800, true);
        rest(&mut sc, &mut m, 1310000000, 4046400, true);
        rest(&mut sc, &mut m, 10000000, 3429600, true);
        rest(&mut sc, &mut m, 4340000000, 2060400, false);
        rest(&mut sc, &mut m, 10000000, 1197600, true);
        rest(&mut sc, &mut m, 690000000, 5120400, true);
        rest(&mut sc, &mut m, 570000000, 4263600, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 9308);
        assert!(q == 1199 && u == 5208, 0);
        let (q, u) = market::quote_base_for_quote(&m, 7216320517188);
        assert!(q == 16985525 && u == 24966000, 1);
        let c = coin::mint_for_testing<QUOTE>(9308, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1199 && ch.value() == 4100, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(7216320517188, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 16985525 && ch.value() == 7216295551188, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 4340000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_3() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 900, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 4990000000, 3344400, false);
        rest(&mut sc, &mut m, 10000000, 2992500, true);
        rest(&mut sc, &mut m, 4300000000, 1208700, false);
        rest(&mut sc, &mut m, 10000000, 3518100, true);
        rest(&mut sc, &mut m, 10000000, 1001700, true);
        rest(&mut sc, &mut m, 10000000, 1986300, true);
        rest(&mut sc, &mut m, 4900000000, 793800, false);
        rest(&mut sc, &mut m, 3120000000, 2270700, false);
        rest(&mut sc, &mut m, 2160000000, 98100, false);
        rest(&mut sc, &mut m, 10000000, 305100, true);
        rest(&mut sc, &mut m, 210000000, 325800, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 96786149);
        assert!(q == 7715700 && u == 33072066, 0);
        let (q, u) = market::quote_base_for_quote(&m, 73041408115795);
        assert!(q == 166455 && u == 10129500, 1);
        let c = coin::mint_for_testing<QUOTE>(96786149, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 7715700 && ch.value() == 63714083, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(73041408115795, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 166455 && ch.value() == 73041397986295, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_4() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 20000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 570100000, 62080000, true);
        rest(&mut sc, &mut m, 581300000, 68880000, true);
        rest(&mut sc, &mut m, 605900000, 34420000, false);
        rest(&mut sc, &mut m, 605500000, 22780000, false);
        rest(&mut sc, &mut m, 586000000, 55100000, true);
        rest(&mut sc, &mut m, 561900000, 61720000, true);
        rest(&mut sc, &mut m, 629200000, 86040000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 753);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 8796);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(753, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 753, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(8796, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 8796, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 605500000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_5() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1300, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1840000000, 392600, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 674507058);
        assert!(q == 392600 && u == 722384, 0);
        let (q, u) = market::quote_base_for_quote(&m, 55738512524);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(674507058, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 392600 && ch.value() == 673784674, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(55738512524, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 55738512524, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_6() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 50000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1805200000, 212200000, false);
        rest(&mut sc, &mut m, 1757100000, 30450000, true);
        rest(&mut sc, &mut m, 1780200000, 172850000, false);
        rest(&mut sc, &mut m, 1788200000, 120600000, false);
        rest(&mut sc, &mut m, 1776300000, 48150000, true);
        rest(&mut sc, &mut m, 1776100000, 9650000, true);
        rest(&mut sc, &mut m, 1782000000, 129750000, false);
        rest(&mut sc, &mut m, 1743300000, 21750000, true);
        rest(&mut sc, &mut m, 1757500000, 31600000, true);
        rest(&mut sc, &mut m, 1768400000, 92300000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 94688);
        assert!(q == 49500 && u == 89010, 0);
        let (q, u) = market::quote_base_for_quote(&m, 93744371158747);
        assert!(q == 408720510 && u == 233900000, 1);
        let c = coin::mint_for_testing<QUOTE>(94688, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 49500 && ch.value() == 5678, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(93744371158747, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 408720510 && ch.value() == 93744137258747, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1780200000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_7() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1700, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 2490000000, 7315100, false);
        rest(&mut sc, &mut m, 5010000000, 5990800, false);
        rest(&mut sc, &mut m, 10000000, 7668700, true);
        rest(&mut sc, &mut m, 5370000000, 1322600, false);
        rest(&mut sc, &mut m, 5590000000, 7542900, false);
        rest(&mut sc, &mut m, 2400000000, 7073700, false);
        rest(&mut sc, &mut m, 10000000, 5846300, true);
        rest(&mut sc, &mut m, 1580000000, 4510100, true);
        rest(&mut sc, &mut m, 3140000000, 2405500, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 120860726);
        assert!(q == 31127085 && u == 120856961, 0);
        let (q, u) = market::quote_base_for_quote(&m, 45417);
        assert!(q == 69137 && u == 44200, 1);
        let c = coin::mint_for_testing<QUOTE>(120860726, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 31127085 && ch.value() == 3765, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(45417, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 69137 && ch.value() == 1217, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 5590000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_8() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 700, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 3220000000, 2850400, false);
        rest(&mut sc, &mut m, 3970000000, 1167600, false);
        rest(&mut sc, &mut m, 3470000000, 2533300, false);
        rest(&mut sc, &mut m, 2540000000, 2107700, false);
        rest(&mut sc, &mut m, 2840000000, 3182200, false);
        rest(&mut sc, &mut m, 450000000, 2153200, true);
        rest(&mut sc, &mut m, 10000000, 1004500, true);
        rest(&mut sc, &mut m, 10000000, 821800, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 13889338);
        assert!(q == 5112800 && u == 13888042, 0);
        let (q, u) = market::quote_base_for_quote(&m, 3447621);
        assert!(q == 981883 && u == 3447500, 1);
        let c = coin::mint_for_testing<QUOTE>(13889338, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 5112800 && ch.value() == 1296, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(3447621, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 981883 && ch.value() == 121, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 2840000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_9() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 150000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 802000000, 1200000, true);
        rest(&mut sc, &mut m, 796700000, 526650000, true);
        rest(&mut sc, &mut m, 798700000, 625500000, true);
        rest(&mut sc, &mut m, 781300000, 36300000, true);
        rest(&mut sc, &mut m, 772700000, 588750000, true);
        rest(&mut sc, &mut m, 796300000, 72000000, true);
        rest(&mut sc, &mut m, 786100000, 524700000, true);
        rest(&mut sc, &mut m, 849600000, 462150000, false);
        rest(&mut sc, &mut m, 843700000, 150600000, false);
        rest(&mut sc, &mut m, 835200000, 56700000, false);
        rest(&mut sc, &mut m, 807800000, 435450000, true);
        rest(&mut sc, &mut m, 832700000, 221700000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 3216);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 863);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(3216, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 3216, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(863, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 863, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 832700000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_10() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 1000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1766000000, 492000, true);
        rest(&mut sc, &mut m, 1582000000, 1024000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 2652408280);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 46507224616);
        assert!(q == 2488840 && u == 1516000, 1);
        let c = coin::mint_for_testing<QUOTE>(2652408280, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 2652408280, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(46507224616, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 2488840 && ch.value() == 46505708616, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_11() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 1000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 802000000, 4287000, false);
        rest(&mut sc, &mut m, 780000000, 934000, false);
        rest(&mut sc, &mut m, 560000000, 424000, true);
        rest(&mut sc, &mut m, 441000000, 1867000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 360697474724);
        assert!(q == 5220477 && u == 4166694, 0);
        let (q, u) = market::quote_base_for_quote(&m, 24479707392);
        assert!(q == 1060680 && u == 2291000, 1);
        let c = coin::mint_for_testing<QUOTE>(360697474724, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 5220477 && ch.value() == 360693308030, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(24479707392, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1060680 && ch.value() == 24477416392, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_12() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 400, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 420000000, 11200, true);
        rest(&mut sc, &mut m, 3360000000, 1025600, false);
        rest(&mut sc, &mut m, 4530000000, 114400, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 87865);
        assert!(q == 25974 && u == 87360, 0);
        let (q, u) = market::quote_base_for_quote(&m, 3879100163);
        assert!(q == 4699 && u == 11200, 1);
        let c = coin::mint_for_testing<QUOTE>(87865, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 25974 && ch.value() == 505, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(3879100163, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 4699 && ch.value() == 3879088963, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 3360000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_13() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 20000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1588000000, 18040000, true);
        rest(&mut sc, &mut m, 1848000000, 6440000, true);
        rest(&mut sc, &mut m, 1547000000, 42380000, true);
        rest(&mut sc, &mut m, 1869000000, 93780000, false);
        rest(&mut sc, &mut m, 1835000000, 90280000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 78171158793);
        assert!(q == 93780000 && u == 175274820, 0);
        let (q, u) = market::quote_base_for_quote(&m, 59772785810);
        assert!(q == 271774300 && u == 157140000, 1);
        let c = coin::mint_for_testing<QUOTE>(78171158793, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 93780000 && ch.value() == 77995883973, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(59772785810, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 271774300 && ch.value() == 59615645810, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_14() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 4000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1092000000, 9284000, false);
        rest(&mut sc, &mut m, 994000000, 8568000, true);
        rest(&mut sc, &mut m, 1222000000, 8344000, false);
        rest(&mut sc, &mut m, 1120000000, 1596000, false);
        rest(&mut sc, &mut m, 1328000000, 8176000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 53898373);
        assert!(q == 27397260 && u == 32979744, 0);
        let (q, u) = market::quote_base_for_quote(&m, 51952216805233);
        assert!(q == 8515740 && u == 8568000, 1);
        let c = coin::mint_for_testing<QUOTE>(53898373, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 27397260 && ch.value() == 20918629, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(51952216805233, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 8515740 && ch.value() == 51952208237233, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_15() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 90000, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1101000000, 136350000, true);
        rest(&mut sc, &mut m, 1114700000, 197100000, true);
        rest(&mut sc, &mut m, 1138200000, 40770000, false);
        rest(&mut sc, &mut m, 1127800000, 27810000, true);
        rest(&mut sc, &mut m, 1157900000, 225270000, false);
        rest(&mut sc, &mut m, 1119000000, 324810000, true);
        rest(&mut sc, &mut m, 1125200000, 128970000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 760782787);
        assert!(q == 265773960 && u == 307244547, 0);
        let (q, u) = market::quote_base_for_quote(&m, 198853765578);
        assert!(q == 908862499 && u == 815040000, 1);
        let c = coin::mint_for_testing<QUOTE>(760782787, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 265773960 && ch.value() == 453538240, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(198853765578, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 908862499 && ch.value() == 198038725578, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_16() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 50000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1326400000, 117550000, true);
        rest(&mut sc, &mut m, 1320800000, 12000000, true);
        rest(&mut sc, &mut m, 1334800000, 89550000, false);
        rest(&mut sc, &mut m, 1292800000, 58500000, true);
        rest(&mut sc, &mut m, 1354300000, 216600000, false);
        rest(&mut sc, &mut m, 1369500000, 46150000, false);
        rest(&mut sc, &mut m, 1345600000, 54250000, false);
        rest(&mut sc, &mut m, 1343600000, 600000, false);
        rest(&mut sc, &mut m, 1305700000, 129350000, true);
        rest(&mut sc, &mut m, 1339600000, 240550000, false);
        rest(&mut sc, &mut m, 1294600000, 75400000, true);
        rest(&mut sc, &mut m, 1318100000, 154450000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 24454);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 458955181);
        assert!(q == 603274520 && u == 458950000, 1);
        let c = coin::mint_for_testing<QUOTE>(24454, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 24454, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(458955181, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 603274520 && ch.value() == 5181, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1334800000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_17() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 110000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1528400000, 379280000, true);
        rest(&mut sc, &mut m, 1508500000, 496210000, true);
        rest(&mut sc, &mut m, 1527000000, 208010000, true);
        rest(&mut sc, &mut m, 1514600000, 203280000, true);
        rest(&mut sc, &mut m, 1576000000, 143770000, false);
        rest(&mut sc, &mut m, 1533600000, 484440000, true);
        rest(&mut sc, &mut m, 1573900000, 307780000, false);
        rest(&mut sc, &mut m, 1506700000, 142010000, true);
        rest(&mut sc, &mut m, 1560200000, 31790000, false);
        rest(&mut sc, &mut m, 1510900000, 191290000, true);
        rest(&mut sc, &mut m, 1527900000, 343750000, true);
        rest(&mut sc, &mut m, 1527800000, 194920000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 65919913998);
        assert!(q == 483340000 && u == 760595220, 0);
        let (q, u) = market::quote_base_for_quote(&m, 8133);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(65919913998, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 483340000 && ch.value() == 65159318778, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(8133, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 8133, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_18() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1600, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 3190400, true);
        rest(&mut sc, &mut m, 670000000, 1212800, true);
        rest(&mut sc, &mut m, 1390000000, 7196800, false);
        rest(&mut sc, &mut m, 2130000000, 1302400, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 87527940104);
        assert!(q == 8498350 && u == 12777664, 0);
        let (q, u) = market::quote_base_for_quote(&m, 2393);
        assert!(q == 1071 && u == 1600, 1);
        let c = coin::mint_for_testing<QUOTE>(87527940104, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 8498350 && ch.value() == 87515162440, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(2393, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1071 && ch.value() == 793, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_19() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 700, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 1900500, true);
        rest(&mut sc, &mut m, 10000000, 3052000, true);
        rest(&mut sc, &mut m, 10000000, 2463300, true);
        rest(&mut sc, &mut m, 10000000, 3012100, true);
        rest(&mut sc, &mut m, 200000000, 3189200, true);
        rest(&mut sc, &mut m, 1700000000, 2898700, false);
        rest(&mut sc, &mut m, 10000000, 3457300, true);
        rest(&mut sc, &mut m, 4520000000, 3334100, false);
        rest(&mut sc, &mut m, 380000000, 2886800, true);
        rest(&mut sc, &mut m, 730000000, 996800, false);
        rest(&mut sc, &mut m, 2930000000, 2957500, false);
        rest(&mut sc, &mut m, 4270000000, 2132900, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 63426142429);
        assert!(q == 12307680 && u == 38498544, 0);
        let (q, u) = market::quote_base_for_quote(&m, 364524085675);
        assert!(q == 1871802 && u == 19961200, 1);
        let c = coin::mint_for_testing<QUOTE>(63426142429, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 12307680 && ch.value() == 63387643885, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(364524085675, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1871802 && ch.value() == 364504124475, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_20() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 90000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1753500000, 227610000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 1700);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 5664);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(1700, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 1700, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(5664, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 5664, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_21() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 130000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1743000000, 64220000, true);
        rest(&mut sc, &mut m, 1785000000, 292370000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 93766018158391);
        assert!(q == 289446300 && u == 521880450, 0);
        let (q, u) = market::quote_base_for_quote(&m, 95617);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(93766018158391, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 289446300 && ch.value() == 93765496277941, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(95617, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 95617, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_22() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 19000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1513000000, 38038000, false);
        rest(&mut sc, &mut m, 1810000000, 15732000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 26426846712131);
        assert!(q == 53232300 && u == 86026414, 0);
        let (q, u) = market::quote_base_for_quote(&m, 82833);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(26426846712131, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 53232300 && ch.value() == 26426760685717, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(82833, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 82833, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_23() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 800, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 1910400, true);
        rest(&mut sc, &mut m, 3920000000, 2108800, false);
        rest(&mut sc, &mut m, 10000000, 3124800, true);
        rest(&mut sc, &mut m, 120000000, 830400, true);
        rest(&mut sc, &mut m, 10000000, 192000, true);
        rest(&mut sc, &mut m, 10000000, 3189600, true);
        rest(&mut sc, &mut m, 3290000000, 872800, false);
        rest(&mut sc, &mut m, 4040000000, 3430400, false);
        rest(&mut sc, &mut m, 4060000000, 3840800, false);
        rest(&mut sc, &mut m, 10000000, 1544000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 62965);
        assert!(q == 18398 && u == 60536, 0);
        let (q, u) = market::quote_base_for_quote(&m, 5734628874890);
        assert!(q == 199236 && u == 10791200, 1);
        let c = coin::mint_for_testing<QUOTE>(62965, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 18398 && ch.value() == 2429, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(5734628874890, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 199236 && ch.value() == 5734618083690, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 3290000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_24() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 14000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 2166000000, 44212000, false);
        rest(&mut sc, &mut m, 1508000000, 23954000, true);
        rest(&mut sc, &mut m, 1874000000, 12530000, false);
        rest(&mut sc, &mut m, 2028000000, 6720000, false);
        rest(&mut sc, &mut m, 1652000000, 62776000, true);
        rest(&mut sc, &mut m, 1865000000, 68278000, false);
        rest(&mut sc, &mut m, 2228000000, 13748000, false);
        rest(&mut sc, &mut m, 1930000000, 2744000, false);
        rest(&mut sc, &mut m, 1725000000, 3416000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 71628777993);
        assert!(q == 148217176 && u == 296137506, 0);
        let (q, u) = market::quote_base_for_quote(&m, 89910157);
        assert!(q == 145347743 && u == 89908000, 1);
        let c = coin::mint_for_testing<QUOTE>(71628777993, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 148217176 && ch.value() == 71332640487, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(89910157, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 145347743 && ch.value() == 2157, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_25() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 16000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1397000000, 14928000, true);
        rest(&mut sc, &mut m, 1869000000, 49232000, false);
        rest(&mut sc, &mut m, 1993000000, 67824000, false);
        rest(&mut sc, &mut m, 1549000000, 60720000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 77517462922);
        assert!(q == 115885440 && u == 227187840, 0);
        let (q, u) = market::quote_base_for_quote(&m, 6986066359149);
        assert!(q == 113760599 && u == 75648000, 1);
        let c = coin::mint_for_testing<QUOTE>(77517462922, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 115885440 && ch.value() == 77290275082, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(6986066359149, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 113760599 && ch.value() == 6985990711149, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_26() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1100, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 4200000000, 2680700, false);
        rest(&mut sc, &mut m, 10000000, 3031600, true);
        rest(&mut sc, &mut m, 10000000, 4128300, true);
        rest(&mut sc, &mut m, 2220000000, 2374900, false);
        rest(&mut sc, &mut m, 3790000000, 3345100, false);
        rest(&mut sc, &mut m, 3980000000, 1006500, false);
        rest(&mut sc, &mut m, 1540000000, 1914000, false);
        rest(&mut sc, &mut m, 4380000000, 5480200, false);
        rest(&mut sc, &mut m, 10000000, 2696100, true);
        rest(&mut sc, &mut m, 1640000000, 4288900, false);
        rest(&mut sc, &mut m, 1630000000, 3414400, false);
        rest(&mut sc, &mut m, 1450000000, 4296600, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 9923157204);
        assert!(q == 28798419 && u == 78995191, 0);
        let (q, u) = market::quote_base_for_quote(&m, 531);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(9923157204, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 28798419 && ch.value() == 9844162013, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(531, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 531, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_27() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1200, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 410400, true);
        rest(&mut sc, &mut m, 10000000, 5912400, true);
        rest(&mut sc, &mut m, 10000000, 3159600, true);
        rest(&mut sc, &mut m, 10000000, 3806400, true);
        rest(&mut sc, &mut m, 10000000, 861600, true);
        rest(&mut sc, &mut m, 2660000000, 5539200, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 2758355522);
        assert!(q == 5483808 && u == 14734272, 0);
        let (q, u) = market::quote_base_for_quote(&m, 51476313413);
        assert!(q == 140088 && u == 14150400, 1);
        let c = coin::mint_for_testing<QUOTE>(2758355522, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 5483808 && ch.value() == 2743621250, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(51476313413, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 140088 && ch.value() == 51462163013, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_28() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1500, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 5676000, true);
        rest(&mut sc, &mut m, 10000000, 648000, true);
        rest(&mut sc, &mut m, 3660000000, 2848500, false);
        rest(&mut sc, &mut m, 10000000, 1558500, true);
        rest(&mut sc, &mut m, 10000000, 5316000, true);
        rest(&mut sc, &mut m, 800000000, 5730000, true);
        rest(&mut sc, &mut m, 620000000, 3912000, true);
        rest(&mut sc, &mut m, 2360000000, 5824500, false);
        rest(&mut sc, &mut m, 3130000000, 2052000, false);
        rest(&mut sc, &mut m, 10000000, 4594500, true);
        rest(&mut sc, &mut m, 2200000000, 1863000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 599484351524);
        assert!(q == 12575412 && u == 34692690, 0);
        let (q, u) = market::quote_base_for_quote(&m, 864);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(599484351524, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 12575412 && ch.value() == 599449658834, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(864, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 864, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_29() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 3000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1456000000, 12771000, false);
        rest(&mut sc, &mut m, 1211000000, 7560000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 4640809);
        assert!(q == 3831000 && u == 4639341, 0);
        let (q, u) = market::quote_base_for_quote(&m, 3831337443438);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(4640809, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 3831000 && ch.value() == 1468, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(3831337443438, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 3831337443438, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1211000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_30() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 4000, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1113000000, 17876000, false);
        rest(&mut sc, &mut m, 1083000000, 236000, false);
        rest(&mut sc, &mut m, 1295000000, 9792000, false);
        rest(&mut sc, &mut m, 716000000, 3360000, true);
        rest(&mut sc, &mut m, 1155000000, 4804000, false);
        rest(&mut sc, &mut m, 1117000000, 19880000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 4037);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 148095767579);
        assert!(q == 2403354 && u == 3360000, 1);
        let c = coin::mint_for_testing<QUOTE>(4037, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 4037, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(148095767579, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 2403354 && ch.value() == 148092407579, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1083000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_31() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 50000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1232600000, 126300000, false);
        rest(&mut sc, &mut m, 1161200000, 152450000, true);
        rest(&mut sc, &mut m, 1170500000, 116700000, true);
        rest(&mut sc, &mut m, 1202800000, 197850000, false);
        rest(&mut sc, &mut m, 1216200000, 166900000, false);
        rest(&mut sc, &mut m, 1183000000, 142600000, true);
        rest(&mut sc, &mut m, 1229500000, 50400000, false);
        rest(&mut sc, &mut m, 1196000000, 18050000, true);
        rest(&mut sc, &mut m, 1198800000, 145150000, true);
        rest(&mut sc, &mut m, 1226300000, 169300000, false);
        rest(&mut sc, &mut m, 1179900000, 194000000, true);
        rest(&mut sc, &mut m, 1223400000, 232900000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 9543208041);
        assert!(q == 943650000 && u == 1151144390, 0);
        let (q, u) = market::quote_base_for_quote(&m, 77692);
        assert!(q == 59940 && u == 50000, 1);
        let c = coin::mint_for_testing<QUOTE>(9543208041, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 943650000 && ch.value() == 8392063651, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(77692, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 59940 && ch.value() == 27692, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_32() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 500, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 38000, true);
        rest(&mut sc, &mut m, 3320000000, 928500, false);
        rest(&mut sc, &mut m, 10000000, 727500, true);
        rest(&mut sc, &mut m, 1300000000, 87500, true);
        rest(&mut sc, &mut m, 4880000000, 1666500, false);
        rest(&mut sc, &mut m, 10000000, 394500, true);
        rest(&mut sc, &mut m, 410000000, 233000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 6101746275);
        assert!(q == 2595000 && u == 11215140, 0);
        let (q, u) = market::quote_base_for_quote(&m, 79579605179039);
        assert!(q == 220880 && u == 1480500, 1);
        let c = coin::mint_for_testing<QUOTE>(6101746275, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 2595000 && ch.value() == 6090531135, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(79579605179039, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 220880 && ch.value() == 79579603698539, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_33() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1900, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 3620000000, 3402900, false);
        rest(&mut sc, &mut m, 10000000, 3355400, true);
        rest(&mut sc, &mut m, 4040000000, 7533500, false);
        rest(&mut sc, &mut m, 10000000, 2641000, true);
        rest(&mut sc, &mut m, 2620000000, 6610100, false);
        rest(&mut sc, &mut m, 3990000000, 8021800, false);
        rest(&mut sc, &mut m, 10000000, 5342800, true);
        rest(&mut sc, &mut m, 20000000, 5914700, true);
        rest(&mut sc, &mut m, 10000000, 7525900, true);
        rest(&mut sc, &mut m, 10000000, 279300, true);
        rest(&mut sc, &mut m, 10000000, 7841300, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 99807275103495);
        assert!(q == 25565743 && u == 92079282, 0);
        let (q, u) = market::quote_base_for_quote(&m, 1581428061208);
        assert!(q == 388112 && u == 32900400, 1);
        let c = coin::mint_for_testing<QUOTE>(99807275103495, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 25565743 && ch.value() == 99807183024213, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(1581428061208, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 388112 && ch.value() == 1581395160808, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_34() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1700, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 7308300, true);
        rest(&mut sc, &mut m, 10000000, 1009800, true);
        rest(&mut sc, &mut m, 10000000, 2403800, true);
        rest(&mut sc, &mut m, 840000000, 6800, true);
        rest(&mut sc, &mut m, 10000000, 1827500, true);
        rest(&mut sc, &mut m, 10000000, 5995900, true);
        rest(&mut sc, &mut m, 4840000000, 8355500, false);
        rest(&mut sc, &mut m, 10000000, 1264800, true);
        rest(&mut sc, &mut m, 10000000, 948600, true);
        rest(&mut sc, &mut m, 2390000000, 8265400, false);
        rest(&mut sc, &mut m, 1950000000, 2703000, false);
        rest(&mut sc, &mut m, 1680000000, 1917600, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 6531800240752);
        assert!(q == 21241500 && u == 68687344, 0);
        let (q, u) = market::quote_base_for_quote(&m, 879365556655);
        assert!(q == 213299 && u == 20765500, 1);
        let c = coin::mint_for_testing<QUOTE>(6531800240752, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 21241500 && ch.value() == 6531731553408, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(879365556655, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 213299 && ch.value() == 879344791155, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_35() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 120000, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1574600000, 273240000, false);
        rest(&mut sc, &mut m, 1513500000, 419880000, true);
        rest(&mut sc, &mut m, 1548100000, 266040000, false);
        rest(&mut sc, &mut m, 1530100000, 568920000, true);
        rest(&mut sc, &mut m, 1541600000, 589200000, false);
        rest(&mut sc, &mut m, 1559700000, 466920000, false);
        rest(&mut sc, &mut m, 1509900000, 162600000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 11613092921);
        assert!(q == 1593804600 && u == 2478666072, 0);
        let (q, u) = market::quote_base_for_quote(&m, 53858864359);
        assert!(q == 1749751109 && u == 1151400000, 1);
        let c = coin::mint_for_testing<QUOTE>(11613092921, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1593804600 && ch.value() == 9134426849, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(53858864359, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 1749751109 && ch.value() == 52707464359, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_36() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 200000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1261200000, 217600000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 30373);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 850539);
        assert!(q == 998870 && u == 800000, 1);
        let c = coin::mint_for_testing<QUOTE>(30373, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 30373, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(850539, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 998870 && ch.value() == 50539, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_37() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1600, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1280000000, 5964800, true);
        rest(&mut sc, &mut m, 540000000, 4840000, true);
        rest(&mut sc, &mut m, 10000000, 6548800, true);
        rest(&mut sc, &mut m, 3230000000, 704000, false);
        rest(&mut sc, &mut m, 870000000, 4972800, true);
        rest(&mut sc, &mut m, 10000000, 5256000, true);
        rest(&mut sc, &mut m, 1730000000, 2616000, false);
        rest(&mut sc, &mut m, 640000000, 564800, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 8900);
        assert!(q == 4752 && u == 8304, 0);
        let (q, u) = market::quote_base_for_quote(&m, 74850);
        assert!(q == 93265 && u == 73600, 1);
        let c = coin::mint_for_testing<QUOTE>(8900, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 4752 && ch.value() == 596, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(74850, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 93265 && ch.value() == 1250, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1730000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_38() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 40000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1996900000, 129760000, true);
        rest(&mut sc, &mut m, 1962800000, 43680000, true);
        rest(&mut sc, &mut m, 1972200000, 141360000, true);
        rest(&mut sc, &mut m, 1972700000, 64960000, true);
        rest(&mut sc, &mut m, 2006900000, 144520000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 6117799);
        assert!(q == 3039696 && u == 6100976, 0);
        let (q, u) = market::quote_base_for_quote(&m, 52665562133388);
        assert!(q == 751714453 && u == 379760000, 1);
        let c = coin::mint_for_testing<QUOTE>(6117799, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 3039696 && ch.value() == 16823, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(52665562133388, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 751714453 && ch.value() == 52665182373388, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 2006900000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_39() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 13000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1852000000, 53131000, false);
        rest(&mut sc, &mut m, 1866000000, 34060000, false);
        rest(&mut sc, &mut m, 1325000000, 38506000, true);
        rest(&mut sc, &mut m, 1678000000, 23465000, false);
        rest(&mut sc, &mut m, 1934000000, 57291000, false);
        rest(&mut sc, &mut m, 1546000000, 14339000, false);
        rest(&mut sc, &mut m, 1511000000, 20332000, true);
        rest(&mut sc, &mut m, 1202000000, 30758000, true);
        rest(&mut sc, &mut m, 1726000000, 9542000, false);
        rest(&mut sc, &mut m, 1672000000, 48113000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 21148755);
        assert!(q == 13676000 && u == 21143096, 0);
        let (q, u) = market::quote_base_for_quote(&m, 2749819127543);
        assert!(q == 118713218 && u == 89596000, 1);
        let c = coin::mint_for_testing<QUOTE>(21148755, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 13676000 && ch.value() == 5659, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(2749819127543, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 118713218 && ch.value() == 2749729531543, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1546000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_40() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1700, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 4450600, true);
        rest(&mut sc, &mut m, 3770000000, 5633800, false);
        rest(&mut sc, &mut m, 10000000, 8437100, true);
        rest(&mut sc, &mut m, 2420000000, 3530900, false);
        rest(&mut sc, &mut m, 2680000000, 5268300, false);
        rest(&mut sc, &mut m, 1950000000, 511700, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 1095);
        assert!(q == 0 && u == 0, 0);
        let (q, u) = market::quote_base_for_quote(&m, 13131806740564);
        assert!(q == 128748 && u == 12887700, 1);
        let c = coin::mint_for_testing<QUOTE>(1095, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 1095, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(13131806740564, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 128748 && ch.value() == 13131793852864, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 1950000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_41() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 140000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1505900000, 518280000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 9518879924489);
        assert!(q == 513097200 && u == 780477852, 0);
        let (q, u) = market::quote_base_for_quote(&m, 82662);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(9518879924489, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 513097200 && ch.value() == 9518099446637, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(82662, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 82662, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_42() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 2000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 110000000, 4550000, true);
        rest(&mut sc, &mut m, 3890000000, 8156000, false);
        rest(&mut sc, &mut m, 2710000000, 3146000, false);
        rest(&mut sc, &mut m, 10000000, 9692000, true);
        rest(&mut sc, &mut m, 10000000, 8338000, true);
        rest(&mut sc, &mut m, 10000000, 5816000, true);
        rest(&mut sc, &mut m, 10000000, 5102000, true);
        rest(&mut sc, &mut m, 1190000000, 3642000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 2983050380);
        assert!(q == 14942505 && u == 44586480, 0);
        let (q, u) = market::quote_base_for_quote(&m, 1115);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(2983050380, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 14942505 && ch.value() == 2938463900, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(1115, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 1115, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_43() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 7000, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1623000000, 30975000, true);
        rest(&mut sc, &mut m, 2144000000, 13020000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 77862354308);
        assert!(q == 12889800 && u == 27914880, 0);
        let (q, u) = market::quote_base_for_quote(&m, 887);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(77862354308, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 12889800 && ch.value() == 77834439428, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(887, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 887, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_44() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 60000, 1, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1108800000, 265620000, false);
        rest(&mut sc, &mut m, 1105500000, 49800000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 68947650329);
        assert!(q == 315388458 && u == 349573356, 0);
        let (q, u) = market::quote_base_for_quote(&m, 216098);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(68947650329, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 315388458 && ch.value() == 68598076973, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(216098, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 216098, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_45() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 40000, 0, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 931300000, 196600000, true);
        rest(&mut sc, &mut m, 954500000, 22440000, true);
        rest(&mut sc, &mut m, 932400000, 57240000, true);
        rest(&mut sc, &mut m, 983900000, 122120000, false);
        rest(&mut sc, &mut m, 953000000, 125200000, true);
        rest(&mut sc, &mut m, 950500000, 24480000, true);
        rest(&mut sc, &mut m, 927400000, 111280000, true);
        rest(&mut sc, &mut m, 945400000, 160160000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 3185450607718);
        assert!(q == 122120000 && u == 120153868, 0);
        let (q, u) = market::quote_base_for_quote(&m, 51648377105078);
        assert!(q == 655083312 && u == 697400000, 1);
        let c = coin::mint_for_testing<QUOTE>(3185450607718, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 122120000 && ch.value() == 3185330453850, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(51648377105078, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 655083312 && ch.value() == 51647679705078, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_46() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 100, 100, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 10000000, 469200, true);
        rest(&mut sc, &mut m, 420000000, 450900, true);
        rest(&mut sc, &mut m, 1830000000, 383400, false);
        rest(&mut sc, &mut m, 2230000000, 410800, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 95718291988);
        assert!(q == 786258 && u == 1617706, 0);
        let (q, u) = market::quote_base_for_quote(&m, 187773837873);
        assert!(q == 192129 && u == 920100, 1);
        let c = coin::mint_for_testing<QUOTE>(95718291988, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 786258 && ch.value() == 95716674282, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(187773837873, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 192129 && ch.value() == 187772917773, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_47() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(100000, 90000, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 1191300000, 260550000, false);
        rest(&mut sc, &mut m, 1154900000, 385560000, true);
        rest(&mut sc, &mut m, 1178900000, 361530000, false);
        rest(&mut sc, &mut m, 1204000000, 38430000, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 49289145430);
        assert!(q == 659849490 && u == 782870652, 0);
        let (q, u) = market::quote_base_for_quote(&m, 776072);
        assert!(q == 830696 && u == 720000, 1);
        let c = coin::mint_for_testing<QUOTE>(49289145430, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 659849490 && ch.value() == 48506274778, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(776072, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 830696 && ch.value() == 56072, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_48() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(1000000, 11000, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 800000000, 6534000, false);
        rest(&mut sc, &mut m, 685000000, 52008000, false);
        rest(&mut sc, &mut m, 209000000, 8426000, true);
        rest(&mut sc, &mut m, 548000000, 28864000, true);
        rest(&mut sc, &mut m, 637000000, 41756000, false);
        rest(&mut sc, &mut m, 862000000, 28215000, false);
        rest(&mut sc, &mut m, 927000000, 30635000, false);
        rest(&mut sc, &mut m, 584000000, 37202000, false);
        rest(&mut sc, &mut m, 369000000, 52272000, true);
        rest(&mut sc, &mut m, 795000000, 29788000, false);
        rest(&mut sc, &mut m, 245000000, 52415000, true);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 66694);
        assert!(q == 109890 && u == 64240, 0);
        let (q, u) = market::quote_base_for_quote(&m, 73715929672);
        assert!(q == 49658840 && u == 141977000, 1);
        let c = coin::mint_for_testing<QUOTE>(66694, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 109890 && ch.value() == 2454, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(73715929672, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 49658840 && ch.value() == 73573952672, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 584000000, 4);
        ts::return_shared(m);
        sc.end();
    }

    #[test]
    fun market_case_49() {
        let mut sc = ts::begin(MAKER);
        let cap = market::create_market<BASE, QUOTE>(10000000, 1800, 10, sc.ctx());
        transfer::public_transfer(cap, MAKER);
        sc.next_tx(MAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        rest(&mut sc, &mut m, 3730000000, 6456600, false);
        rest(&mut sc, &mut m, 4500000000, 8305200, false);
        rest(&mut sc, &mut m, 1810000000, 968400, false);
        ts::return_shared(m);
        sc.next_tx(TAKER);
        let mut m = sc.take_shared<Market<BASE, QUOTE>>();
        let (q, u) = market::quote_quote_for_base(&m, 9097666378010);
        assert!(q == 15714469 && u == 63209322, 0);
        let (q, u) = market::quote_base_for_quote(&m, 3605967259);
        assert!(q == 0 && u == 0, 1);
        let c = coin::mint_for_testing<QUOTE>(9097666378010, sc.ctx());
        let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 15714469 && ch.value() == 9097603168688, 2);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        let c = coin::mint_for_testing<BASE>(3605967259, sc.ctx());
        let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());
        assert!(o.value() == 0 && ch.value() == 3605967259, 3);
        coin::burn_for_testing(o);
        coin::burn_for_testing(ch);
        assert!(market::best_ask(&m) == 18446744073709551615, 4);
        ts::return_shared(m);
        sc.end();
    }
}
