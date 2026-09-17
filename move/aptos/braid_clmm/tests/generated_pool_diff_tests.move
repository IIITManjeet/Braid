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
module braid_clmm::generated_pool_diff_tests {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use braid_clmm::i32::{Self, I32};
    use braid_clmm::pool;

    struct A {}
    struct B {}

    struct Caps has key {
        a_mint: MintCapability<A>,
        a_burn: BurnCapability<A>,
        b_mint: MintCapability<B>,
        b_burn: BurnCapability<B>,
    }

    fun setup() {
        account::create_account_for_test(@aptos_framework);
        let braid = account::create_account_for_test(@braid_clmm);
        account::create_account_for_test(@0xA);
        let (ab, af, am) = coin::initialize<A>(
            &braid, std::string::utf8(b"A"), std::string::utf8(b"A"), 8, false);
        let (bb, bf, bm) = coin::initialize<B>(
            &braid, std::string::utf8(b"B"), std::string::utf8(b"B"), 8, false);
        coin::destroy_freeze_cap(af);
        coin::destroy_freeze_cap(bf);
        move_to(&braid, Caps { a_mint: am, a_burn: ab, b_mint: bm, b_burn: bb });
    }

    fun lp(): signer { account::create_signer_for_test(@0xA) }

    fun mint_a(v: u64): Coin<A> acquires Caps {
        coin::mint<A>(v, &borrow_global<Caps>(@braid_clmm).a_mint)
    }

    fun mint_b(v: u64): Coin<B> acquires Caps {
        coin::mint<B>(v, &borrow_global<Caps>(@braid_clmm).b_mint)
    }

    fun burn_a(c: Coin<A>) acquires Caps {
        coin::burn<A>(c, &borrow_global<Caps>(@braid_clmm).a_burn)
    }

    fun burn_b(c: Coin<B>) acquires Caps {
        coin::burn<B>(c, &borrow_global<Caps>(@braid_clmm).b_burn)
    }

    fun tick_of(magnitude: u32, is_negative: bool): I32 {
        if (is_negative) { i32::neg_from(magnitude) } else { i32::from_u32(magnitude) }
    }

    fun add(p: address, lm: u32, ln: bool, um: u32, un: bool, a0: u64, a1: u64, c0: u64, c1: u64) acquires Caps {
        let ca = mint_a(a0);
        let cb = mint_b(a1);
        let (ra, rb) = pool::add_liquidity<A, B>(&lp(), p, tick_of(lm, ln), tick_of(um, un), ca, cb);
        assert!(coin::value(&ra) == c0 && coin::value(&rb) == c1, 100);
        burn_a(ra);
        burn_b(rb);
    }

    fun swap(p: address, a_to_b: bool, amount: u64, limit: u128, want_out: u64, want_change: u64) acquires Caps {
        if (a_to_b) {
            let c = mint_a(amount);
            let (o, ch) = pool::swap_a_for_b<A, B>(p, c, 0, limit);
            assert!(coin::value(&o) == want_out, 101);
            assert!(coin::value(&ch) == want_change, 102);
            burn_b(o);
            burn_a(ch);
        } else {
            let c = mint_b(amount);
            let (o, ch) = pool::swap_b_for_a<A, B>(p, c, 0, limit);
            assert!(coin::value(&o) == want_out, 101);
            assert!(coin::value(&ch) == want_change, 102);
            burn_a(o);
            burn_b(ch);
        }
    }


    #[test]
    fun pool_case_0() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2312456486763430559, 5, 1);
        add(p, 41694, true, 40926, true, 6820382752, 6892783, 5176951615, 0);
        add(p, 41834, true, 41201, true, 2589181396, 63890129, 0, 27117590);
        assert!(pool::liquidity<A, B>(p) == 26564585259, 0);
        swap(p, true, 81, 19812, 1, 0);
        swap(p, false, 64261, 2340445059289199681, 4087034, 0);
        swap(p, true, 96444766105, 19812, 43729547, 93621710586);
        assert!(pool::sqrt_price<A, B>(p) == 2277987687322260362, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294925461, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_1() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(436758460774307457, 30, 1);
        add(p, 75464, true, 74679, true, 725214, 959036006545056, 0, 959036006543795);
        add(p, 75574, true, 74293, true, 769870, 3732328411076, 0, 3732328410549);
        add(p, 75152, true, 74729, true, 28810, 3990822763, 0, 3990822730);
        assert!(pool::liquidity<A, B>(p) == 2556028, 0);
        swap(p, true, 23151, 427982084422998583, 12, 0);
        swap(p, false, 15327, 17175572088390372486202642652453860, 1546972, 14435);
        swap(p, true, 5282145157270796, 446517778066511846, 0, 5282145157270796);
        assert!(pool::sqrt_price<A, B>(p) == 449519341112332546, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294893003, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_2() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(24632665375600736634, 100, 200);
        add(p, 115000, true, 11800, false, 4728394470960429, 2880, 4728394470960008, 1);
        add(p, 130200, true, 157200, false, 5225743431976271, 2095634226328, 5224567471525571, 0);
        assert!(pool::liquidity<A, B>(p) == 1571116273478, 0);
        swap(p, true, 4632504, 19812, 8177725, 0);
        swap(p, false, 41744495398, 17175572088390372486202642652453860, 22729118323, 0);
        assert!(pool::sqrt_price<A, B>(p) == 25117797305889318924, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 6174, 2);
        assert!(pool::liquidity<A, B>(p) == 1571116273478, 3);
    }

    #[test]
    fun pool_case_3() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17766415815920292108, 0, 60);
        add(p, 33360, true, 39420, false, 943603, 8200320619508080, 0, 8200320618695141);
        assert!(pool::liquidity<A, B>(p) == 1049658, 0);
        swap(p, true, 3296103219007, 8415515806374054821, 532084, 3296102008016);
        swap(p, true, 1442007862503, 19812, 280852, 1442004598989);
        swap(p, false, 70726355356405, 17175572088390372486202642652453860, 0, 70726355356405);
        assert!(pool::sqrt_price<A, B>(p) == 3479787665918138903, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294933935, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_4() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1801921365224205244617, 100, 10);
        add(p, 84480, false, 92600, false, 628375887047638, 1674977626602950, 628348517709468, 25);
        add(p, 84240, false, 95120, false, 6896079575, 9532, 6896079574, 17);
        add(p, 88800, false, 96260, false, 3053943898, 965511987, 3053786154, 5);
        assert!(pool::liquidity<A, B>(p) == 56990298010394, 0);
        swap(p, false, 8237674312709066, 2058333899027419569534, 27369433424, 7960897452947712);
        swap(p, false, 7538056958126, 17175572088390372486202642652453860, 62485, 7537190185875);
        swap(p, false, 43, 17175572088390372486202642652453860, 0, 43);
        assert!(pool::sqrt_price<A, B>(p) == 2270254566421471237647, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 96260, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_5() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1946187363822456, 30, 10);
        add(p, 187700, true, 181300, true, 76089292904, 209173515, 705, 209171556);
        add(p, 185850, true, 176880, true, 771343000286, 72582982, 435, 72578942);
        assert!(pool::liquidity<A, B>(p) == 393750671, 0);
        swap(p, true, 1396, 1713533062553544, 0, 0);
        swap(p, true, 5797729278811, 19812, 5995, 5159434859430);
        swap(p, false, 806577, 1951504971988408, 0, 806577);
        assert!(pool::sqrt_price<A, B>(p) == 1549779061254117, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294779595, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_6() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18021924543002216265, 0, 1);
        add(p, 1212, true, 129, false, 9705809381069140, 4967739945888553, 5538993385719585, 0);
        add(p, 988, true, 328, true, 90484386, 76786, 90462913, 0);
        add(p, 809, true, 180, false, 5337, 2558772734, 0, 2558770008);
        assert!(pool::liquidity<A, B>(p) == 138887865757832365, 0);
        swap(p, false, 893918630585652, 18444899583751176499, 930429260724876, 0);
        swap(p, true, 78830723, 17887272418042030973, 76236311, 0);
        assert!(pool::sqrt_price<A, B>(p) == 18140652602540367752, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966961, 2);
        assert!(pool::liquidity<A, B>(p) == 138887865757832365, 3);
    }

    #[test]
    fun pool_case_7() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(3574301406808097150, 100, 200);
        add(p, 110000, true, 12400, true, 84676194239663, 7582237285636115, 1, 7577373365215415);
        assert!(pool::liquidity<A, B>(p) == 25643394637134, 0);
        swap(p, false, 53, 17175572088390372486202642652453860, 1385, 0);
        swap(p, false, 602258962625999, 17175572088390372486202642652453860, 84676194238276, 593343405873112);
        assert!(pool::sqrt_price<A, B>(p) == 9923630973469837947, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294954896, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_8() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(4601646251261894067, 100, 60);
        add(p, 54420, true, 15120, true, 829786511355, 8241647495, 745454175212, 0);
        add(p, 70020, true, 8220, true, 40322940418, 800509412836846, 1, 800505876590615);
        add(p, 57480, true, 26940, true, 8812991335, 58431190, 8763601356, 0);
        assert!(pool::liquidity<A, B>(p) == 61309064869, 0);
        swap(p, false, 17, 17175572088390372486202642652453860, 257, 0);
        swap(p, true, 582023591, 19812, 35772212, 0);
        swap(p, true, 65, 19812, 3, 0);
        assert!(pool::sqrt_price<A, B>(p) == 4590883069313313132, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294939478, 2);
        assert!(pool::liquidity<A, B>(p) == 61309064869, 3);
    }

    #[test]
    fun pool_case_9() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(93991450268594310664070742063700, 30, 10);
        add(p, 581970, false, 588430, false, 8250515731, 512456805081600, 8250515730, 276082448008);
        assert!(pool::liquidity<A, B>(p) == 671, 0);
        swap(p, true, 704445, 79262279369138780552336064479720, 512180722633590, 704441);
        swap(p, true, 6345280206154612, 73113745258127703484113380964601, 0, 6345280206154612);
        assert!(pool::sqrt_price<A, B>(p) == 79910873949802239789840164040483, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 581969, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_10() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(196665672015281112660, 100, 60);
        add(p, 22860, false, 69120, false, 28237, 587801790941831, 0, 587801787527564);
        add(p, 2100, false, 69960, false, 10804895, 731842166260, 0, 730217960918);
        add(p, 6000, false, 53220, false, 68917, 781172, 66911, 8);
        assert!(pool::liquidity<A, B>(p) == 170601437, 0);
        swap(p, false, 4741278061693014, 225780355933189916067, 2063477, 4741277789711210);
        assert!(pool::sqrt_price<A, B>(p) == 225780355933189916067, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 50096, 2);
        assert!(pool::liquidity<A, B>(p) == 170601437, 3);
    }

    #[test]
    fun pool_case_11() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19616531613418474501, 0, 10);
        add(p, 570, false, 1580, false, 49003278, 378116773346620, 0, 378116669761212);
        add(p, 530, false, 1550, false, 95361514915935, 34644693, 95361500762338, 0);
        add(p, 4970, true, 7100, false, 531689784359429, 9695501295408356, 0, 9065438156505867);
        assert!(pool::liquidity<A, B>(p) == 2222960452340303, 0);
        swap(p, false, 1656051, 17175572088390372486202642652453860, 1464430, 0);
        swap(p, false, 3440726642849, 17175572088390372486202642652453860, 3038180054639, 0);
        swap(p, true, 724602544, 16770856437109679306, 821803576, 0);
        assert!(pool::sqrt_price<A, B>(p) == 19645076914208655940, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 1258, 2);
        assert!(pool::liquidity<A, B>(p) == 2222960452340303, 3);
    }

    #[test]
    fun pool_case_12() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(67824452161964159803, 100, 200);
        add(p, 36000, true, 158400, false, 74160256, 99156571970842, 0, 99155613219323);
        add(p, 12200, false, 158200, false, 5004032, 19694632566, 0, 19660799633);
        add(p, 38200, true, 128600, false, 3600937290458962, 1648, 3600937290458835, 0);
        assert!(pool::liquidity<A, B>(p) == 291459252, 0);
        swap(p, false, 88065, 990181970892358895014, 6448, 0);
        assert!(pool::sqrt_price<A, B>(p) == 67829970123477772325, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 26043, 2);
        assert!(pool::liquidity<A, B>(p) == 291459252, 3);
    }

    #[test]
    fun pool_case_13() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(25340958645767685960, 100, 1);
        add(p, 5659, false, 6623, false, 3057458796603, 201477094383, 3015053177998, 0);
        add(p, 6281, false, 6940, false, 6286033966920, 8911391, 6285994744272, 0);
        add(p, 6003, false, 6872, false, 4785004592, 81537599998, 0, 75479981140);
        assert!(pool::liquidity<A, B>(p) == 4570304736968, 0);
        swap(p, true, 78605522922026, 25304242716978154464, 9096617950, 78600646875726);
        swap(p, false, 15457827296, 25768972915722635089, 8112927352, 0);
        swap(p, false, 701790, 17175572088390372486202642652453860, 367432, 0);
        assert!(pool::sqrt_price<A, B>(p) == 25366012763124374266, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 6370, 2);
        assert!(pool::liquidity<A, B>(p) == 4570304736968, 3);
    }

    #[test]
    fun pool_case_14() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(237094531979280804619603003, 100, 200);
        add(p, 319200, false, 424600, false, 46954239792785, 183553748, 46954239792784, 2027686);
        add(p, 253600, false, 424800, false, 331520718438192, 81284643, 331520718438191, 6093447);
        add(p, 318600, false, 455600, false, 985919, 2779548487, 985918, 3032141);
        assert!(pool::liquidity<A, B>(p) == 655, 0);
        swap(p, true, 88, 19812, 3033233599, 78);
        swap(p, false, 180, 17175572088390372486202642652453860, 0, 180);
        swap(p, true, 55249810389995, 19812, 0, 55249810389995);
        assert!(pool::sqrt_price<A, B>(p) == 5922409440882556285220797, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 253599, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_15() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18494127802745863261, 30, 200);
        add(p, 27000, true, 145200, false, 157056, 46331711, 0, 46214587);
        add(p, 82000, true, 42600, false, 40201732510, 6241, 40201726949, 0);
        add(p, 148600, true, 98200, false, 53713303959299, 6968947794309, 46827204278533, 0);
        assert!(pool::liquidity<A, B>(p) == 6955209547397, 0);
        swap(p, true, 67451614, 174526428935310869, 67594529, 0);
        swap(p, false, 21630, 17175572088390372486202642652453860, 21455, 0);
        swap(p, false, 4680903, 17175572088390372486202642652453860, 4643063, 0);
        assert!(pool::sqrt_price<A, B>(p) == 18493960961932702100, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 51, 2);
        assert!(pool::liquidity<A, B>(p) == 6955209547397, 3);
    }

    #[test]
    fun pool_case_16() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19244855761996811229, 0, 200);
        add(p, 62400, true, 54000, false, 87476768087178, 36007, 87476768055055, 0);
        assert!(pool::liquidity<A, B>(p) == 36039, 0);
        swap(p, true, 617495342, 19812, 36005, 616713859);
        swap(p, true, 48, 19812, 0, 48);
        swap(p, true, 31049377933512, 19812, 0, 31049377933512);
        assert!(pool::sqrt_price<A, B>(p) == 814683057031365979, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294904895, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_17() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1637150846568580901571, 5, 10);
        add(p, 89140, false, 94060, false, 8480758724958765, 159628212, 8480758724820715, 0);
        assert!(pool::liquidity<A, B>(p) == 62823432, 0);
        swap(p, true, 1012465, 19812, 159628211, 991589);
        assert!(pool::sqrt_price<A, B>(p) == 1590279469577966198426, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 89139, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_18() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(13943338620991434751, 30, 10);
        add(p, 13110, true, 1700, false, 4579, 686769215681, 0, 686769213001);
        add(p, 6410, true, 1110, false, 922412160217191, 48194793, 922411556080889, 0);
        assert!(pool::liquidity<A, B>(p) == 1602646457, 0);
        swap(p, false, 817135487, 17175572088390372486202642652453860, 604140879, 332971635);
        swap(p, true, 5006, 19812, 0, 5006);
        assert!(pool::sqrt_price<A, B>(p) == 20083199749974656100, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 1700, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_19() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(83534191452405242, 30, 60);
        add(p, 145620, true, 95700, true, 423485, 422769283850, 46, 422769283833);
        add(p, 111000, true, 87960, true, 175064, 88968566076734, 57, 88968566076733);
        add(p, 129780, true, 92700, true, 134623, 735616900, 67, 735616896);
        assert!(pool::liquidity<A, B>(p) == 6582, 0);
        swap(p, true, 42040470983225, 36254182724680146, 13, 42040469398498);
        assert!(pool::sqrt_price<A, B>(p) == 36254182724680146, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294842648, 2);
        assert!(pool::liquidity<A, B>(p) == 5328, 3);
    }

    #[test]
    fun pool_case_20() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1663463942021996902, 0, 200);
        add(p, 181600, true, 4000, false, 5941, 568593, 4, 568540);
        add(p, 161000, true, 35400, false, 735955315, 139752453831769, 8, 139752447775268);
        add(p, 190000, true, 27600, false, 734440443307, 8031, 734439477315, 0);
        add(p, 95600, true, 24800, false, 17224285939, 95858184, 4564928336, 0);
        assert!(pool::liquidity<A, B>(p) == 1239658743, 0);
        swap(p, true, 448599287075369, 19812, 101922763, 448261125040297);
        swap(p, false, 1526112992605259, 3665333547312650, 0, 1526112992605259);
        swap(p, false, 5101721425007248, 17175572088390372486202642652453860, 0, 5101721425007248);
        assert!(pool::sqrt_price<A, B>(p) == 1381428528399329, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294777295, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_21() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(92264310181553229290, 100, 200);
        add(p, 112000, true, 49200, false, 478223775, 433049832737014, 0, 433028955979907);
        assert!(pool::liquidity<A, B>(p) == 4177056180, 0);
        swap(p, true, 63, 19812, 1546, 0);
        swap(p, false, 28423, 17175572088390372486202642652453860, 1124, 0);
        assert!(pool::sqrt_price<A, B>(p) == 92264427617091616943, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 32197, 2);
        assert!(pool::liquidity<A, B>(p) == 4177056180, 3);
    }

    #[test]
    fun pool_case_22() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2264208140279352891563, 0, 1);
        add(p, 95820, false, 96555, false, 68541, 3532293, 68329, 1);
        assert!(pool::liquidity<A, B>(p) == 1503051, 0);
        swap(p, false, 9448587370, 17175572088390372486202642652453860, 210, 9445346141);
        swap(p, false, 57501788976, 2328771083794142887778, 0, 57501788976);
        assert!(pool::sqrt_price<A, B>(p) == 2303987302044002007908, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 96555, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_23() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19372129987831744044, 100, 200);
        add(p, 151600, true, 55400, false, 340368, 91698437, 0, 91296813);
        add(p, 92600, true, 114200, false, 36095447705, 65369, 36095388084, 0);
        add(p, 46400, true, 3400, false, 6891, 806561, 0, 746139);
        add(p, 133000, true, 148600, false, 5513547, 5878411686, 0, 5872334794);
        assert!(pool::liquidity<A, B>(p) == 6302676, 0);
        swap(p, false, 630, 17175572088390372486202642652453860, 564, 0);
        swap(p, true, 2666530, 19812, 2022301, 0);
        swap(p, true, 9225018284505, 19812, 4582623, 9219742116188);
        assert!(pool::sqrt_price<A, B>(p) == 9421762148222699, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294815695, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_24() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(8798444081894723177, 0, 60);
        add(p, 60720, true, 15840, false, 3523171423742680, 60515729, 3523171191850189, 0);
        add(p, 39420, true, 25020, false, 12611, 8232927, 0, 8230575);
        assert!(pool::liquidity<A, B>(p) == 141092059, 0);
        swap(p, false, 919382571, 19362446827979437378, 161392995, 838582571);
        swap(p, false, 133800896483, 17175572088390372486202642652453860, 70512105, 133637491652);
        assert!(pool::sqrt_price<A, B>(p) == 64445849987248335137, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 25020, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_25() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17958206055793155945, 100, 200);
        add(p, 89600, true, 137600, false, 50500, 35171722201, 0, 35171674851);
        add(p, 25200, true, 53200, false, 66230794411, 453821773, 65601059119, 0);
        add(p, 800, true, 148600, false, 5821877700762, 722510858, 5763587650068, 0);
        add(p, 97400, true, 53400, false, 201573389988943, 28636549135011, 173171022351749, 0);
        assert!(pool::liquidity<A, B>(p) == 29706775938339, 0);
        swap(p, false, 1122888, 17175572088390372486202642652453860, 1172965, 0);
        swap(p, false, 9204200890374, 17175572088390372486202642652453860, 7311091487045, 0);
        swap(p, true, 933, 19812, 1512, 0);
        assert!(pool::sqrt_price<A, B>(p) == 23616500435260791535, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4941, 2);
        assert!(pool::liquidity<A, B>(p) == 29706775938339, 3);
    }

    #[test]
    fun pool_case_26() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1194814895423674226, 0, 60);
        add(p, 77700, true, 40020, true, 7118360, 3072071518071, 1, 3072071478936);
        assert!(pool::liquidity<A, B>(p) == 885006, 0);
        swap(p, false, 79701, 17175572088390372486202642652453860, 7118358, 17358);
        swap(p, false, 909993781, 17175572088390372486202642652453860, 0, 909993781);
        assert!(pool::sqrt_price<A, B>(p) == 2494249607062615997, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294927276, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_27() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(768056566332440578, 5, 60);
        add(p, 63780, true, 29700, true, 264974484921, 862837088528839, 15, 862837082894945);
        add(p, 109200, true, 57780, true, 2859, 3452342933443, 5, 3452342933425);
        add(p, 78840, true, 60540, true, 7733026487926206, 8644, 7733026486609446, 0);
        assert!(pool::liquidity<A, B>(p) == 13517570715, 0);
        swap(p, false, 23, 17175572088390372486202642652453860, 12690, 0);
        swap(p, true, 356, 19812, 0, 0);
        swap(p, false, 261, 17175572088390372486202642652453860, 149977, 0);
        assert!(pool::sqrt_price<A, B>(p) == 768056950323938669, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294903717, 2);
        assert!(pool::liquidity<A, B>(p) == 13517570715, 3);
    }

    #[test]
    fun pool_case_28() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19378326484457228525, 0, 60);
        add(p, 29040, true, 31860, false, 31074715, 290331965647, 0, 290298077050);
        add(p, 30600, true, 27240, false, 83836, 4043213197265, 0, 4043213096778);
        add(p, 20340, true, 22920, false, 88112, 754490, 0, 658762);
        assert!(pool::liquidity<A, B>(p) == 41770153, 0);
        swap(p, true, 2116757886719, 13606574545976317335, 13069350, 2116741020085);
        swap(p, false, 890, 13626998700891404210, 1635, 0);
        swap(p, true, 747104, 3084153757518484487, 401210, 0);
        assert!(pool::sqrt_price<A, B>(p) == 13429783197758060090, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294960947, 2);
        assert!(pool::liquidity<A, B>(p) == 41770153, 3);
    }

    #[test]
    fun pool_case_29() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(60774944528180613562530, 30, 200);
        add(p, 62600, false, 225800, false, 2697951748570, 97368314238228, 2697943087677, 1999);
        add(p, 130600, false, 163600, false, 69503, 5462654478730940, 0, 5454840067556852);
        assert!(pool::liquidity<A, B>(p) == 32755020668, 0);
        swap(p, true, 6674593901, 948413785933632312986, 104333269283665, 6099598354);
        assert!(pool::sqrt_price<A, B>(p) == 948413785933632312986, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 78802, 2);
        assert!(pool::liquidity<A, B>(p) == 29760353003, 3);
    }

    #[test]
    fun pool_case_30() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(4850610968932219057, 0, 1);
        add(p, 27014, true, 26712, true, 1990519, 2042168032592789, 0, 2042168024476826);
        add(p, 27255, true, 26525, true, 2207158932, 904183181367937, 0, 904182757409713);
        add(p, 26806, true, 26661, true, 40019967288, 6570, 40019907451, 0);
        add(p, 26870, true, 26551, true, 2213845062545, 66979105486452, 0, 66837973660280);
        assert!(pool::liquidity<A, B>(p) == 70494611087126, 0);
        swap(p, false, 5171320348, 4945626744196226387, 74769909733, 0);
        assert!(pool::sqrt_price<A, B>(p) == 4851964183251029044, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294940584, 2);
        assert!(pool::liquidity<A, B>(p) == 70492517075747, 3);
    }

    #[test]
    fun pool_case_31() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18397007526049253580, 30, 60);
        add(p, 18540, true, 31500, false, 74649, 30871416767130, 0, 30871416710694);
        add(p, 44940, true, 23100, false, 470486210956, 755955592, 469903180383, 0);
        add(p, 33780, true, 4440, false, 7671657775411, 31936663, 7671649844962, 0);
        assert!(pool::liquidity<A, B>(p) == 887283289, 0);
        swap(p, false, 59706741857335, 17175572088390372486202642652453860, 591035668, 59704880582360);
        swap(p, true, 456810519295, 19812, 0, 456810519295);
        assert!(pool::sqrt_price<A, B>(p) == 89104437532541615436, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 31500, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_32() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1322030754403057106224, 100, 10);
        add(p, 80420, false, 92890, false, 308903645607661, 9293963158537, 308901114123704, 10);
        add(p, 81930, false, 92710, false, 3032256560797826, 523601, 3032256560797633, 3);
        assert!(pool::liquidity<A, B>(p) == 583725553549, 0);
        swap(p, false, 3815192907481797, 17175572088390372486202642652453860, 2531484146, 3796136469443986);
        assert!(pool::sqrt_price<A, B>(p) == 1918225218991181851924, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 92890, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_33() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(589404897885536755494239213, 0, 60);
        add(p, 343560, false, 362820, false, 59057888215937, 8697207, 59057888215936, 2466145);
        add(p, 341460, false, 369660, false, 316732395218431, 402084439629, 316732395218430, 4974342);
        assert!(pool::liquidity<A, B>(p) == 67131, 0);
        swap(p, true, 737485692, 394466188835295077195997466, 402085696347, 737485690);
        swap(p, true, 4306377, 19812, 0, 4306377);
        swap(p, true, 41510730, 19812, 0, 41510730);
        assert!(pool::sqrt_price<A, B>(p) == 478915288425693244000844650, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 341459, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_34() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(3049593024929516081, 0, 60);
        add(p, 68640, true, 17880, true, 56280892372, 5860491985185, 3, 5858415247713);
        assert!(pool::liquidity<A, B>(p) == 15615625217, 0);
        swap(p, true, 63004166820, 1065858347815889195, 1032940981, 0);
        assert!(pool::sqrt_price<A, B>(p) == 1829379445458248941, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294921075, 2);
        assert!(pool::liquidity<A, B>(p) == 15615625217, 3);
    }

    #[test]
    fun pool_case_35() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1996979064254105302, 0, 200);
        add(p, 105200, true, 103400, false, 589465685, 2269, 589262441, 0);
        add(p, 80800, true, 40000, true, 99864, 674075177, 0, 674070280);
        add(p, 165600, true, 66000, false, 6087858, 7695841144298, 3, 7695841072833);
        assert!(pool::liquidity<A, B>(p) == 737717, 0);
        swap(p, true, 5749, 56181238076833833, 67, 0);
        swap(p, false, 4077, 17175572088390372486202642652453860, 331531, 0);
        swap(p, true, 83396581604048, 140665814834693712, 77706, 83396495363644);
        assert!(pool::sqrt_price<A, B>(p) == 140665814834693712, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294869766, 2);
        assert!(pool::liquidity<A, B>(p) == 683708, 3);
    }

    #[test]
    fun pool_case_36() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(156103081332913934, 0, 200);
        add(p, 232600, true, 26200, false, 253210, 153136983100, 77, 153136983081);
        add(p, 190000, true, 64400, true, 8417265881010, 30698120318484, 89, 30697362374077);
        add(p, 216600, true, 42600, true, 54607, 983763, 58, 983758);
        assert!(pool::liquidity<A, B>(p) == 90366194019, 0);
        swap(p, true, 7841, 10231467429658587, 0, 0);
        swap(p, true, 121, 19812, 0, 0);
        swap(p, false, 3341, 1835016130169650868, 46654234, 0);
        assert!(pool::sqrt_price<A, B>(p) == 156103763225705356, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294871848, 2);
        assert!(pool::liquidity<A, B>(p) == 90366194019, 3);
    }

    #[test]
    fun pool_case_37() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18676553816237110248, 30, 1);
        add(p, 125, false, 680, false, 4963706814197430, 8122, 4963706814169709, 0);
        add(p, 76, true, 327, false, 7962672, 3112162091473, 0, 3112129010322);
        add(p, 474, true, 329, false, 449085825, 74088, 449077544, 0);
        add(p, 247, true, 763, false, 6642587522, 2967, 6642584507, 0);
        assert!(pool::liquidity<A, B>(p) == 2039183897, 0);
        swap(p, true, 59437175, 19812, 33166325, 26453863);
        swap(p, true, 66694323163, 17924873277192778616, 0, 66694323163);
        swap(p, true, 410, 19812, 0, 410);
        assert!(pool::sqrt_price<A, B>(p) == 18014717575017094255, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966821, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_38() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19332459780688452712, 30, 200);
        add(p, 4200, true, 153600, false, 61009, 4807237886601109, 0, 4807237886585921);
        add(p, 116800, true, 4200, false, 999297127713155, 37569131819564, 994135313854971, 0);
        add(p, 92600, true, 16200, false, 64369, 6303898671067234, 0, 6303898670936014);
        assert!(pool::liquidity<A, B>(p) == 35947708725231, 0);
        swap(p, true, 391568756216, 19812, 423958133780, 0);
        assert!(pool::sqrt_price<A, B>(p) == 19114903572819990285, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 711, 2);
        assert!(pool::liquidity<A, B>(p) == 35947708725231, 3);
    }

    #[test]
    fun pool_case_39() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(15378417425540639, 0, 200);
        add(p, 159000, true, 63000, true, 2633, 660030638, 280, 660030637);
        add(p, 278000, true, 140600, true, 2369033296536070, 5794106559657250, 144, 5794078331635636);
        assert!(pool::liquidity<A, B>(p) == 33897514509775, 0);
        swap(p, true, 8096650370039035, 19812, 4692714846, 0);
        swap(p, true, 416780, 11065300116678963, 0, 0);
        swap(p, false, 3609511312, 17175572088390372486202642652453860, 6475957906780304, 0);
        assert!(pool::sqrt_price<A, B>(p) == 14788947115489232, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294824713, 2);
        assert!(pool::liquidity<A, B>(p) == 33897514509775, 3);
    }

    #[test]
    fun pool_case_40() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17937424453337635077, 5, 200);
        add(p, 139400, true, 120600, false, 45385865, 519414, 44837290, 0);
        add(p, 90800, true, 106400, false, 2438036763, 6586301, 2431027318, 0);
        assert!(pool::liquidity<A, B>(p) == 7383182, 0);
        swap(p, false, 60, 17175572088390372486202642652453860, 62, 0);
        swap(p, false, 598872729737, 137227145076348349317, 6600275, 598824961022);
        assert!(pool::sqrt_price<A, B>(p) == 137227145076348349317, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 40137, 2);
        assert!(pool::liquidity<A, B>(p) == 7383182, 3);
    }

    #[test]
    fun pool_case_41() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18064638076072997804, 5, 10);
        add(p, 3850, true, 360, true, 6037, 28281487, 0, 27969786);
        assert!(pool::liquidity<A, B>(p) == 2019000, 0);
        swap(p, false, 632352998639592, 17175572088390372486202642652453860, 6036, 632352998633782);
        assert!(pool::sqrt_price<A, B>(p) == 18117689507910179518, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966936, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_42() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1209667637047469475, 5, 200);
        add(p, 149600, true, 42600, true, 7103072215903945, 1848739557915356, 6, 1781182574958739);
        add(p, 82200, true, 97200, false, 17101, 4833795, 15, 4833739);
        add(p, 135000, true, 39600, false, 1088150665334, 7287497, 1086440797882, 0);
        add(p, 191000, true, 51800, false, 886431383, 590045423, 10, 586218869);
        assert!(pool::liquidity<A, B>(p) == 1039150595933886, 0);
        swap(p, false, 38, 1785243189663330070, 8604, 0);
        swap(p, false, 245, 17175572088390372486202642652453860, 56741, 0);
        assert!(pool::sqrt_price<A, B>(p) == 1209667637052457716, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294912802, 2);
        assert!(pool::liquidity<A, B>(p) == 1039150595933886, 3);
    }

    #[test]
    fun pool_case_43() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2057100690477252993, 30, 10);
        add(p, 45460, true, 39930, true, 9195893973245214, 9394724209740223, 0, 9346011460305227);
        add(p, 51510, true, 36630, true, 15825816, 7427, 15254015, 0);
        assert!(pool::liquidity<A, B>(p) == 5730077293898590, 0);
        swap(p, false, 9832918, 17175572088390372486202642652453860, 788326095, 0);
        swap(p, false, 36, 2625142992634834318, 2814, 0);
        assert!(pool::sqrt_price<A, B>(p) == 2057100722037352045, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294923422, 2);
        assert!(pool::liquidity<A, B>(p) == 5730077293898590, 3);
    }

    #[test]
    fun pool_case_44() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17601371257360615281, 0, 1);
        add(p, 1472, true, 637, true, 6042, 29017359048474, 0, 29017359038784);
        add(p, 1534, true, 480, true, 3390782840, 7766333405, 0, 3766899405);
        assert!(pool::liquidity<A, B>(p) == 142832039907, 0);
        swap(p, true, 457269, 19812, 416316, 0);
        assert!(pool::sqrt_price<A, B>(p) == 17601317490090546299, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966357, 2);
        assert!(pool::liquidity<A, B>(p) == 142832039907, 3);
    }

    #[test]
    fun pool_case_45() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18478909696030126727, 100, 60);
        add(p, 36240, true, 33900, false, 57972715, 857891613, 0, 798228259);
        add(p, 24900, true, 41520, false, 82084, 6548994699846, 0, 6548994632718);
        add(p, 34440, true, 33000, false, 3393, 8758, 0, 5294);
        add(p, 3420, true, 23220, false, 57219949892272, 291131749, 57218694848820, 0);
        assert!(pool::liquidity<A, B>(p) == 1903259004, 0);
        swap(p, false, 463662193610199, 17175572088390372486202642652453860, 1313101639, 463657818641429);
        assert!(pool::sqrt_price<A, B>(p) == 147051679888672259837, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 41520, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_46() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(168455634420563, 30, 1);
        add(p, 232575, true, 231647, true, 45108864550046, 5998245845387258, 5299, 5998245845383075);
        add(p, 232703, true, 231328, true, 8469482188, 51577759, 1942, 51577758);
        add(p, 232181, true, 231867, true, 89231152620, 4650661417403268, 154, 4650661417403264);
        add(p, 232331, true, 231895, true, 76940, 7626630634, 916, 7626630633);
        assert!(pool::liquidity<A, B>(p) == 19046154213, 0);
        swap(p, false, 7863363949, 17175572088390372486202642652453860, 45206565253478, 7863360077);
        swap(p, true, 241702, 19812, 0, 241702);
        swap(p, true, 2670469, 19812, 0, 2670469);
        assert!(pool::sqrt_price<A, B>(p) == 174963384631780, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294735968, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_47() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(458851758954916723652, 0, 200);
        add(p, 53600, false, 88800, false, 157579389, 64395, 157579211, 2);
        assert!(pool::liquidity<A, B>(p) == 6257, 0);
        swap(p, false, 77493961753102, 17175572088390372486202642652453860, 177, 77493961378422);
        swap(p, true, 8408939040, 19812, 0, 8408939040);
        assert!(pool::sqrt_price<A, B>(p) == 1563474546184340651101, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 88800, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_48() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17686263503962197414, 5, 60);
        add(p, 31140, true, 14160, false, 7663995, 7306255508, 0, 7295839283);
        add(p, 9120, true, 33360, false, 69672, 1651, 65331, 0);
        add(p, 18780, true, 30900, false, 597379999706352, 890225403021, 596079057531687, 0);
        add(p, 15600, true, 7740, false, 80175202143347, 412250879913, 79875380886347, 0);
        assert!(pool::liquidity<A, B>(p) == 2391961916326, 0);
        swap(p, true, 758, 19812, 695, 0);
        assert!(pool::sqrt_price<A, B>(p) == 17686263498597714246, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966453, 2);
        assert!(pool::liquidity<A, B>(p) == 2391961916326, 3);
    }

    #[test]
    fun pool_case_49() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(732977965942760116760, 100, 10);
        add(p, 69310, false, 75530, false, 426691125, 75308, 426691103, 6);
        assert!(pool::liquidity<A, B>(p) == 9719, 0);
        swap(p, true, 87551839151543, 19812, 75301, 87551839151481);
        assert!(pool::sqrt_price<A, B>(p) == 590054330642268204557, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 69309, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_50() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18291533534699408704, 30, 200);
        add(p, 95400, true, 19800, false, 455845680684043, 78421487594, 455794876391065, 0);
        add(p, 49800, true, 65200, false, 8767768288042340, 6067692576, 8767761810179181, 0);
        add(p, 122600, true, 94200, false, 3929373, 84918064, 0, 81028279);
        assert!(pool::liquidity<A, B>(p) == 86450816578, 0);
        swap(p, false, 64370378131216, 17175572088390372486202642652453860, 57286085507, 64066165512328);
        assert!(pool::sqrt_price<A, B>(p) == 2048068427860524029785, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 94200, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_51() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2579724036417261766, 30, 10);
        add(p, 42850, true, 34180, true, 810819739, 6484156, 341187172, 0);
        add(p, 44660, true, 36740, true, 31075801, 80200, 28928622, 0);
        assert!(pool::liquidity<A, B>(p) == 290982801, 0);
        swap(p, true, 8530906279587821, 19812, 6564355, 8530905878005002);
        swap(p, false, 920675466, 17175572088390372486202642652453860, 0, 920675466);
        swap(p, true, 538456, 19812, 0, 538456);
        assert!(pool::sqrt_price<A, B>(p) == 1977828497627636875, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294922635, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_52() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(25959332954341334333, 0, 1);
        add(p, 6369, false, 7063, false, 33765931, 2229916537, 0, 2095619572);
        add(p, 6782, false, 6853, false, 31849, 59372, 20252, 0);
        add(p, 6739, false, 7596, false, 826394093659, 3852, 826394078169, 0);
        assert!(pool::liquidity<A, B>(p) == 4176778570, 0);
        swap(p, false, 4161154771, 17175572088390372486202642652453860, 33793015, 4093457987);
        assert!(pool::sqrt_price<A, B>(p) == 26968483143540141657, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 7596, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_53() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(14842151417560412106, 5, 1);
        add(p, 4598, true, 3955, true, 8449, 63474701468, 0, 63474697988);
        add(p, 5090, true, 4120, true, 28906204472308, 27843759, 28906191043995, 0);
        add(p, 4848, true, 3760, true, 8108, 6977, 0, 2512);
        add(p, 4420, true, 4107, true, 774052, 636679, 0, 487826);
        assert!(pool::liquidity<A, B>(p) == 1003379657, 0);
        swap(p, true, 1705, 19812, 1102, 0);
        assert!(pool::sqrt_price<A, B>(p) == 14842131141433574098, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294962947, 2);
        assert!(pool::liquidity<A, B>(p) == 1003379657, 3);
    }

    #[test]
    fun pool_case_54() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(235006061841747691, 100, 60);
        add(p, 125340, true, 59820, true, 567068, 5042968839, 13, 5042968734);
        add(p, 92580, true, 43440, true, 2760527184726697, 76806, 2760525383502167, 0);
        add(p, 129300, true, 66600, true, 299619205, 984442402070, 30, 984442335805);
        assert!(pool::liquidity<A, B>(p) == 31770724, 0);
        swap(p, false, 5969062334661, 17175572088390372486202642652453860, 2101410756, 5969059554756);
        swap(p, true, 270988, 19812, 0, 270988);
        assert!(pool::sqrt_price<A, B>(p) == 2102225351207229506, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294923856, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_55() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(28574046855, 100, 1);
        add(p, 406106, true, 405283, true, 54835106555286, 1999340, 326137790300, 1999339);
        add(p, 405946, true, 405617, true, 78222458711, 142629887, 913256903, 142629886);
        assert!(pool::liquidity<A, B>(p) == 3812660, 0);
        swap(p, false, 74, 17175572088390372486202642652453860, 54586277966791, 68);
        swap(p, false, 9280689656148677, 29496346151, 0, 9280689656148677);
        swap(p, true, 388222186550964, 28873304942, 0, 388222186550964);
        assert!(pool::sqrt_price<A, B>(p) == 29224776474, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294562013, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_56() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17796914931340437388, 30, 10);
        add(p, 5320, true, 4050, false, 83946580940, 870358859917, 0, 794621177557);
        add(p, 760, true, 5770, false, 687858782022484, 31550, 687858777620708, 0);
        add(p, 5890, true, 4820, false, 949872279, 9835392441, 0, 9002252990);
        add(p, 5420, true, 690, true, 5912, 258210, 4106, 0);
        assert!(pool::liquidity<A, B>(p) == 385695905238, 0);
        swap(p, true, 2100360204217, 15876585025863601281, 40149877924, 2051861887919);
        assert!(pool::sqrt_price<A, B>(p) == 15876585025863601281, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294964295, 2);
        assert!(pool::liquidity<A, B>(p) == 385680574237, 3);
    }

    #[test]
    fun pool_case_57() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18902357732281469086, 0, 200);
        add(p, 78400, true, 19000, false, 1814724240, 573813170072, 0, 570717909585);
        add(p, 20200, true, 85200, false, 4605343454289, 35046412, 4605292419326, 0);
        add(p, 38000, true, 75000, false, 43766008088, 30591, 43765974796, 0);
        add(p, 91400, true, 17400, false, 5431239, 7829059, 1132662, 0);
        assert!(pool::liquidity<A, B>(p) == 3141125893, 0);
        swap(p, false, 831842, 151848374071548784143, 792019, 0);
        assert!(pool::sqrt_price<A, B>(p) == 18907242852141821878, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 493, 2);
        assert!(pool::liquidity<A, B>(p) == 3141125893, 3);
    }

    #[test]
    fun pool_case_58() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17848310732716790740, 100, 60);
        add(p, 18780, true, 18000, false, 7722, 27945689994, 0, 27945682893);
        add(p, 9480, true, 44460, false, 3737, 894893740852206, 0, 894893740850812);
        assert!(pool::liquidity<A, B>(p) == 16354, 0);
        swap(p, true, 5594191845193, 19812, 8492, 5594191823896);
        swap(p, false, 76860, 31079915250646307977, 0, 76860);
        assert!(pool::sqrt_price<A, B>(p) == 7213359759455392164, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294948515, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_59() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2683441335951209434450, 5, 1);
        add(p, 99263, false, 99921, false, 259640865632, 2202562179453775, 163016673324, 1);
        add(p, 99592, false, 100311, false, 6881286397, 3490623289744356, 0, 3488038439001627);
        add(p, 99018, false, 100199, false, 842568511, 202949839, 842558786, 2);
        add(p, 98910, false, 99615, false, 37654956, 20518725, 37654940, 0);
        assert!(pool::liquidity<A, B>(p) == 923654002573238, 0);
        swap(p, true, 418587, 19812, 8853441360, 0);
        assert!(pool::sqrt_price<A, B>(p) == 2683441159134818779637, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 99604, 2);
        assert!(pool::liquidity<A, B>(p) == 923654002573238, 3);
    }

    #[test]
    fun pool_case_60() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(388244854179207048, 30, 60);
        add(p, 104220, true, 75420, true, 9562596, 3968876490, 0, 3968840112);
        assert!(pool::liquidity<A, B>(p) == 2333541, 0);
        swap(p, true, 4506, 19812, 1, 0);
        swap(p, true, 85068, 255687780227073918, 37, 0);
        assert!(pool::sqrt_price<A, B>(p) == 387932395919317428, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294890055, 2);
        assert!(pool::liquidity<A, B>(p) == 2333541, 3);
    }

    #[test]
    fun pool_case_61() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1308356157370, 100, 60);
        add(p, 364080, true, 310860, true, 831314594570865, 77311746362, 3505384572, 77311746356);
        add(p, 336900, true, 325920, true, 65245313207, 78016711722, 2317551, 78016711721);
        add(p, 348840, true, 322920, true, 9261807551570180, 304289446, 69235832804, 304289338);
        assert!(pool::liquidity<A, B>(p) == 2519782107, 0);
        swap(p, true, 462634, 994500400099, 0, 0);
        assert!(pool::sqrt_price<A, B>(p) == 1308356157354, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294638046, 2);
        assert!(pool::liquidity<A, B>(p) == 2519782107, 3);
    }

    #[test]
    fun pool_case_62() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2475735780256804354491, 5, 1);
        add(p, 97548, false, 98629, false, 9160343, 139867142154, 0, 23869787380);
        assert!(pool::liquidity<A, B>(p) == 39280548214, 0);
        swap(p, false, 39017543, 2523979119483248965536, 2165, 0);
        assert!(pool::sqrt_price<A, B>(p) == 2475754094327897675602, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 97993, 2);
        assert!(pool::liquidity<A, B>(p) == 39280548214, 3);
    }

    #[test]
    fun pool_case_63() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(6393365386305707, 30, 10);
        add(p, 164050, true, 156070, true, 19175259, 91079769700303, 71, 91079769700299);
        add(p, 166410, true, 156800, true, 1363535913368949, 789252238320, 637, 788846392559);
        assert!(pool::liquidity<A, B>(p) == 3939881797229, 0);
        swap(p, true, 15401652019, 5958060741180643, 1844, 0);
        assert!(pool::sqrt_price<A, B>(p) == 6393356750198711, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294807940, 2);
        assert!(pool::liquidity<A, B>(p) == 3939881797229, 3);
    }

    #[test]
    fun pool_case_64() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(4628119983029513756, 5, 10);
        add(p, 30260, true, 23740, true, 2675809022, 19356313180, 0, 19240689091);
        add(p, 30420, true, 25870, true, 83124401070, 2670059567344725, 0, 2670051662551085);
        assert!(pool::liquidity<A, B>(p) == 247893727573, 0);
        swap(p, true, 20173120151323, 19812, 8020417727, 20026764904539);
        swap(p, true, 2267, 3274366183760223988, 0, 2267);
        assert!(pool::sqrt_price<A, B>(p) == 4030796208832630834, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294936875, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_65() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(639308873781869365154, 30, 1);
        add(p, 70820, false, 71144, false, 97293, 6725035, 83545, 0);
        add(p, 70813, false, 71375, false, 33414097, 80545890671533, 0, 80537067268249);
        add(p, 70830, false, 70922, false, 59911751, 8953727147439036, 0, 8953017709574144);
        add(p, 70245, false, 71409, false, 4413882210, 7294545276418, 0, 171683297820);
        assert!(pool::liquidity<A, B>(p) == 11213976838932, 0);
        swap(p, true, 459033226, 19812, 548917995066, 0);
        swap(p, false, 907740220182, 17175572088390372486202642652453860, 753798985, 0);
        swap(p, true, 3863262770864, 19812, 8197228976254, 3856213151073);
        assert!(pool::sqrt_price<A, B>(p) == 618292892426237915444, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 70244, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_66() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19382787056905840105, 0, 10);
        add(p, 60, true, 3660, false, 74297, 921761, 0, 888190);
        assert!(pool::liquidity<A, B>(p) == 624702, 0);
        swap(p, true, 508939408195840, 18255901578322650177, 33570, 508939408163794);
        swap(p, true, 99436356, 19812, 0, 99436356);
        assert!(pool::sqrt_price<A, B>(p) == 18391489527427947883, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294967235, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_67() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(3355238382032722728, 5, 10);
        add(p, 38620, true, 28250, true, 15996, 91134575, 0, 91134151);
        assert!(pool::liquidity<A, B>(p) == 11491, 0);
        swap(p, true, 764976846030632, 19812, 423, 764976846014559);
        swap(p, false, 598408878624677, 2947860257806087325, 0, 598408878624677);
        assert!(pool::sqrt_price<A, B>(p) == 2675093747444413281, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294928675, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_68() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(177945124859506510, 5, 200);
        add(p, 128800, true, 28400, true, 24819190, 17941, 60, 15933);
        add(p, 227800, true, 66400, true, 1967, 88628202, 66, 88628201);
        add(p, 197200, true, 82600, true, 898638336, 12165, 846017823, 0);
        add(p, 142600, true, 200, false, 6705865211, 6962954738422337, 55, 6962954737844630);
        assert!(pool::liquidity<A, B>(p) == 66828723, 0);
        swap(p, true, 4041, 19812, 0, 0);
        swap(p, true, 38, 19812, 0, 0);
        swap(p, true, 4185773464803665, 66958570989513447, 402080, 4185761975914795);
        assert!(pool::sqrt_price<A, B>(p) == 66958570989513447, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294854919, 2);
        assert!(pool::liquidity<A, B>(p) == 66828723, 3);
    }

    #[test]
    fun pool_case_69() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19026676857953419855, 30, 10);
        add(p, 5590, true, 7330, false, 958841, 83970, 874540, 0);
        add(p, 2260, true, 7720, false, 85600151, 123699850, 0, 82845455);
        assert!(pool::liquidity<A, B>(p) == 295746558, 0);
        swap(p, true, 1397139704388600, 16658872861933960155, 37961706, 1397139663511367);
        assert!(pool::sqrt_price<A, B>(p) == 16658872861933960155, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294965257, 2);
        assert!(pool::liquidity<A, B>(p) == 295746558, 3);
    }

    #[test]
    fun pool_case_70() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(127102186161906215742, 0, 1);
        add(p, 38026, false, 39279, false, 3495675516961, 81000, 3495675514973, 0);
        add(p, 38175, false, 38827, false, 97017624172, 196085751036, 94859594359, 0);
        add(p, 38363, false, 38825, false, 761443183055, 72236660, 761441787062, 0);
        add(p, 38089, false, 39042, false, 634257213271373, 44947107482, 634256406529331, 0);
        assert!(pool::liquidity<A, B>(p) == 1598582057460, 0);
        swap(p, true, 3326397523751615, 19812, 241105176174, 3326392330939596);
        assert!(pool::sqrt_price<A, B>(p) == 123481682259379714339, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 38025, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_71() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(23212270854346865748, 100, 1);
        add(p, 4553, false, 4912, false, 79698, 1898996468921780, 0, 1898996468904447);
        add(p, 4059, false, 5353, false, 52859222749, 4922342, 52854865673, 0);
        add(p, 4257, false, 5035, false, 507510588, 90980, 507436401, 0);
        assert!(pool::liquidity<A, B>(p) == 158337207, 0);
        swap(p, false, 4802726056212, 23396255723307950509, 989510, 4802724461028);
        swap(p, false, 64609375977939, 17175572088390372486202642652453860, 3521445, 64609370084792);
        assert!(pool::sqrt_price<A, B>(p) == 24107536280208633135, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 5353, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_72() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(2051243209697829183539, 30, 1);
        add(p, 94111, false, 94740, false, 42980395152, 77359233135, 42954108846, 0);
        add(p, 93801, false, 94900, false, 53026, 1284837869353, 0, 1284413956477);
        add(p, 93883, false, 94962, false, 78308, 2245029026735, 0, 2244563691050);
        assert!(pool::liquidity<A, B>(p) == 116743014178, 0);
        swap(p, false, 656519291493980, 17175572088390372486202642652453860, 26417638, 656183192076144);
        swap(p, true, 585806863516, 2116567078855485233898, 0, 585806863516);
        swap(p, false, 55, 17175572088390372486202642652453860, 0, 55);
        assert!(pool::sqrt_price<A, B>(p) == 2127601340178487637648, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 94962, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_73() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(570154814577178727, 5, 10);
        add(p, 73800, true, 63160, true, 4377213, 3022919438996259, 5, 3022919438993319);
        add(p, 76310, true, 64620, true, 9683060166, 447023615978, 3, 447011428503);
        assert!(pool::liquidity<A, B>(p) == 1373383391, 0);
        swap(p, true, 158147918812355, 19812, 12190411, 158130007889596);
        swap(p, true, 7178236, 19812, 0, 7178236);
        swap(p, false, 926533040165314, 17175572088390372486202642652453860, 0, 926533040165314);
        assert!(pool::sqrt_price<A, B>(p) == 406398385353315334, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294890985, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_74() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19017057879754442288, 0, 200);
        add(p, 25600, true, 128200, false, 232820437314, 8094117, 232810026293, 0);
        add(p, 99400, true, 88800, false, 69314, 32631865, 0, 32557794);
        add(p, 68000, true, 136200, false, 9678816996118753, 32559, 9678816996087128, 0);
        assert!(pool::liquidity<A, B>(p) == 10856109, 0);
        swap(p, true, 801322, 19812, 791412, 0);
        swap(p, false, 88724184722936, 58060208706861533917, 7882683, 88724160954204);
        swap(p, false, 4092568912179, 17175572088390372486202642652453860, 3430592, 4086033908784);
        assert!(pool::sqrt_price<A, B>(p) == 16723118871868718434179, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 136200, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_75() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(6417964601294915584, 0, 200);
        add(p, 134600, true, 13600, true, 86911638, 674386777403333, 0, 674386743936570);
        add(p, 111200, true, 107800, false, 498353176519182, 521942316342, 493999965813792, 0);
        add(p, 173200, true, 83000, false, 6284084, 78234277238737, 1, 78234276474251);
        assert!(pool::liquidity<A, B>(p) == 1517069891640, 0);
        swap(p, true, 8215, 19812, 994, 0);
        swap(p, true, 4844847281, 19812, 585804905, 0);
        swap(p, true, 862853768821, 19812, 87014764512, 0);
        assert!(pool::sqrt_price<A, B>(p) == 5352789349971344846, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294942549, 2);
        assert!(pool::liquidity<A, B>(p) == 1517069891640, 3);
    }

    #[test]
    fun pool_case_76() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(5241171661930340974, 5, 1);
        add(p, 25578, true, 24576, true, 8220, 56620836586712, 0, 56620836586250);
        add(p, 25288, true, 24994, true, 8693, 1554939363608, 0, 1554939363124);
        assert!(pool::liquidity<A, B>(p) == 365024, 0);
        swap(p, false, 904334909630, 17175572088390372486202642652453860, 16910, 904334908231);
        swap(p, true, 1457281509771, 19812, 0, 1457281509771);
        swap(p, true, 410, 19812, 0, 410);
        assert!(pool::sqrt_price<A, B>(p) == 5398652135344465289, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294942720, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_77() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(54692916376317312, 5, 60);
        add(p, 153180, true, 73200, true, 6845822, 466908317530372, 268, 466908317530314);
        add(p, 124260, true, 107700, true, 4910052298915047, 87091, 4910041494675100, 0);
        add(p, 119280, true, 74880, true, 85195713163, 65288, 36374938369, 0);
        assert!(pool::liquidity<A, B>(p) == 256125049, 0);
        swap(p, true, 299664, 19812, 2, 0);
        assert!(pool::sqrt_price<A, B>(p) == 54692726747115763, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294850871, 2);
        assert!(pool::liquidity<A, B>(p) == 256125049, 3);
    }

    #[test]
    fun pool_case_78() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(311087726937971068, 5, 200);
        add(p, 83800, true, 40800, true, 7345, 3797865, 16, 3797864);
        assert!(pool::liquidity<A, B>(p) == 142, 0);
        swap(p, true, 575741001, 19812, 0, 575740046);
        swap(p, false, 45751109457, 37367546489639491713, 0, 45751109457);
        swap(p, false, 47302616217124, 17175572088390372486202642652453860, 0, 47302616217124);
        assert!(pool::sqrt_price<A, B>(p) == 279458177174408777, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294883495, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_79() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19158159858125116230, 5, 10);
        add(p, 5370, true, 5390, false, 7475, 696568544555251, 0, 696568544544962);
        add(p, 3200, true, 5870, false, 90148339697, 1899834, 90146126062, 0);
        add(p, 2520, true, 3380, false, 57833875185, 70723087281840, 0, 70646393089444);
        add(p, 4510, true, 1040, false, 46159, 42961405892, 0, 42960585899);
        assert!(pool::liquidity<A, B>(p) == 488681231083, 0);
        swap(p, true, 12636182045534, 19812, 76696922507, 12552375043556);
        assert!(pool::sqrt_price<A, B>(p) == 14103194133907016808, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294961925, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_80() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17569954574270620689, 100, 200);
        add(p, 108200, true, 142000, false, 6680906980063, 4889892513753744, 1, 4883855327930651);
        assert!(pool::liquidity<A, B>(p) == 6368364357319, 0);
        swap(p, false, 737969165276525, 17175572088390372486202642652453860, 6631109071957, 0);
        swap(p, true, 807856126109, 19812, 689211823175340, 0);
        assert!(pool::sqrt_price<A, B>(p) == 137425365691904690661, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 40165, 2);
        assert!(pool::liquidity<A, B>(p) == 6368364357319, 3);
    }

    #[test]
    fun pool_case_81() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17637725886941810139, 0, 200);
        add(p, 71000, true, 27800, false, 3299555370053, 5349048356391, 0, 1508506600135);
        add(p, 35000, true, 54400, false, 96031095089839, 983125, 96031093858366, 0);
        add(p, 81400, true, 98800, false, 959178735545406, 27444338393566, 928822097290495, 0);
        assert!(pool::liquidity<A, B>(p) == 33366396593103, 0);
        swap(p, true, 7316624738607, 19812, 5529574016732, 0);
        swap(p, false, 57167270, 66060705440882782540, 91501972, 0);
        assert!(pool::sqrt_price<A, B>(p) == 14580710668391331938, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294962591, 2);
        assert!(pool::liquidity<A, B>(p) == 33366396593103, 3);
    }

    #[test]
    fun pool_case_82() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18658737239942150216, 5, 1);
        add(p, 467, true, 650, false, 6644852604327973, 18416, 6644852604316991, 0);
        add(p, 187, true, 925, false, 79418, 823857873686631, 0, 823857873637810);
        assert!(pool::liquidity<A, B>(p) == 2880064, 0);
        swap(p, true, 6640678178607122, 19812, 67235, 6640678178539728);
        assert!(pool::sqrt_price<A, B>(p) == 18021023514351651832, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966828, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_83() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17747413984881218618, 0, 60);
        add(p, 40380, true, 9480, false, 642342938011, 9949982, 642337936158, 0);
        add(p, 6000, true, 39240, false, 6501670039973, 6456415352, 6475442443848, 0);
        add(p, 6960, true, 6660, false, 24224163964831, 548012206417855, 0, 528792049410049);
        add(p, 40020, true, 24180, false, 2173689188775374, 7266184, 2173689182264782, 0);
        assert!(pool::liquidity<A, B>(p) == 75114368995895, 0);
        swap(p, true, 7261735666863, 4307297208428666397, 6149598325621, 0);
        assert!(pool::sqrt_price<A, B>(p) == 16237182747033019749, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294964744, 2);
        assert!(pool::liquidity<A, B>(p) == 75114368995895, 3);
    }

    #[test]
    fun pool_case_84() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(41111962355354, 100, 60);
        add(p, 277740, true, 215160, true, 8131556070566, 831886657, 202526, 831886630);
        assert!(pool::liquidity<A, B>(p) == 20242051, 0);
        swap(p, true, 3055, 28578860904351, 0, 0);
        swap(p, true, 78950672669, 19812, 0, 0);
        swap(p, true, 5528, 19812, 0, 0);
        assert!(pool::sqrt_price<A, B>(p) == 40761184761401, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294706829, 2);
        assert!(pool::liquidity<A, B>(p) == 20242051, 3);
    }

    #[test]
    fun pool_case_85() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1295671313271960477407, 100, 10);
        add(p, 83710, false, 89800, false, 508166668741, 7268, 508166668736, 3);
        add(p, 78000, false, 90210, false, 7211, 6255385478541, 0, 6255339109380);
        add(p, 80910, false, 86600, false, 209711376, 86331842200380, 0, 83754650607386);
        add(p, 78240, false, 90700, false, 737916683340885, 9668, 737916683340883, 9);
        assert!(pool::liquidity<A, B>(p) == 196580000015, 0);
        swap(p, true, 8150556876754, 19812, 2577237979075, 8149908100493);
        swap(p, true, 365694999320945, 19812, 0, 365694999320945);
        assert!(pool::sqrt_price<A, B>(p) == 911136658137925791823, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 77999, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_86() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17920392842969070489, 100, 10);
        add(p, 2150, true, 5290, false, 8973460603366, 42320, 8973460452406, 0);
        add(p, 6590, true, 270, false, 6076002, 862435494, 0, 826620058);
        add(p, 6700, true, 6570, false, 98629, 8456755, 0, 8375100);
        add(p, 6100, true, 1870, false, 1931589926527449, 888246, 1931589926077778, 0);
        assert!(pool::liquidity<A, B>(p) == 146714243, 0);
        swap(p, false, 517604955767, 20110329021334276281, 6601282, 517598350546);
        swap(p, false, 612312, 17175572088390372486202642652453860, 173976, 362341);
        swap(p, true, 139114216159, 19812, 0, 139114216159);
        assert!(pool::sqrt_price<A, B>(p) == 25619952899466879618, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 6570, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_87() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(1135716274090793915, 5, 1);
        add(p, 56039, true, 55430, true, 150143035111183, 12008000, 150139407068070, 0);
        add(p, 56442, true, 55744, true, 635317075739, 4127, 635317057560, 0);
        assert!(pool::liquidity<A, B>(p) == 13848829198, 0);
        swap(p, false, 25120503418436, 17175572088390372486202642652453860, 3628061290, 25120489433676);
        swap(p, true, 65509, 1133972934397859130, 0, 65509);
        swap(p, false, 79182, 1160239202280949653, 0, 79182);
        assert!(pool::sqrt_price<A, B>(p) == 1154337339978027859, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294911866, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_88() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17599669830524482751, 0, 60);
        add(p, 2460, true, 25620, false, 413195, 1138, 400637, 0);
        add(p, 46620, true, 44040, false, 49982484327031, 741911796047814, 0, 696229824698517);
        assert!(pool::liquidity<A, B>(p) == 53312592932149, 0);
        swap(p, false, 7029750346381, 26301346763915529633, 6784996520950, 0);
        assert!(pool::sqrt_price<A, B>(p) == 20032040841005773608, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 1648, 2);
        assert!(pool::liquidity<A, B>(p) == 53312592932149, 3);
    }

    #[test]
    fun pool_case_89() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(28840092998323128794, 5, 1);
        add(p, 8401, false, 9360, false, 25336589919, 2790352553249212, 0, 2790273965184182);
        add(p, 8484, false, 9271, false, 9628413355993, 46448779899, 9614434440875, 0);
        add(p, 8692, false, 9250, false, 904617035, 7186653070210553, 0, 7186651323678111);
        assert!(pool::liquidity<A, B>(p) == 3312490198805, 0);
        swap(p, false, 446, 17175572088390372486202642652453860, 182, 0);
        assert!(pool::sqrt_price<A, B>(p) == 28840093000801264764, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 8938, 2);
        assert!(pool::liquidity<A, B>(p) == 3312490198805, 3);
    }

    #[test]
    fun pool_case_90() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(6652843819021285323, 5, 200);
        add(p, 57200, true, 70200, false, 4339, 38181, 2, 37701);
        add(p, 82800, true, 114800, false, 70702, 9437318822960, 1, 9437318814159);
        add(p, 86800, true, 7400, true, 6048874934, 130425750, 5551708544, 0);
        assert!(pool::liquidity<A, B>(p) == 375232047, 0);
        swap(p, false, 762460, 10779700074087945836, 5826200, 0);
        assert!(pool::sqrt_price<A, B>(p) == 6690308257207196527, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294947010, 2);
        assert!(pool::liquidity<A, B>(p) == 375232047, 3);
    }

    #[test]
    fun pool_case_91() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18374713340242449195, 30, 200);
        add(p, 50200, true, 137200, false, 74496401627, 574951326079, 0, 506995857150);
        add(p, 122800, true, 147400, false, 35755148, 678314831, 0, 642892911);
        assert!(pool::liquidity<A, B>(p) == 74318785436, 0);
        swap(p, true, 9006901008, 655049008386040473, 7952719433, 0);
        swap(p, false, 88452515, 17175572088390372486202642652453860, 111413438, 0);
        assert!(pool::sqrt_price<A, B>(p) == 16422649493864677894, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294964971, 2);
        assert!(pool::liquidity<A, B>(p) == 74318785436, 3);
    }

    #[test]
    fun pool_case_92() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(186648358482895794453, 100, 1);
        add(p, 46149, false, 46897, false, 787309, 6080377875340710, 0, 6080377856549024);
        add(p, 45585, false, 46791, false, 7940246696458, 789868, 7940246690930, 0);
        add(p, 45715, false, 46771, false, 8792, 3875817568568, 0, 3875816498760);
        assert!(pool::liquidity<A, B>(p) == 272091660, 0);
        swap(p, true, 1819, 19812, 184181, 0);
        swap(p, true, 924072201286, 185364195116996125310, 18757380, 924072014924);
        swap(p, true, 3780983, 19812, 1709798, 3763514);
        assert!(pool::sqrt_price<A, B>(p) == 180192176222168051869, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 45584, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_93() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(13505599535068044996, 100, 10);
        add(p, 8150, true, 2380, true, 3189472013348, 5054988, 3189453893945, 0);
        add(p, 9740, true, 390, true, 8937671085153191, 3077957, 8937671076097353, 0);
        assert!(pool::liquidity<A, B>(p) == 101816667, 0);
        swap(p, true, 647267294900754, 19812, 8132944, 647267277507710);
        swap(p, true, 17785912786, 9272214821871987134, 0, 17785912786);
        assert!(pool::sqrt_price<A, B>(p) == 11335192088629232563, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294957555, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_94() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(617057604104835716043, 30, 60);
        add(p, 38280, false, 81480, false, 94041984377247, 687986, 94041984376914, 1);
        add(p, 37620, false, 90660, false, 2260541989126055, 8621544163635573, 2254404330646561, 3);
        add(p, 64860, false, 78180, false, 3938234562, 468452012941, 3351199167, 2);
        assert!(pool::liquidity<A, B>(p) == 320666729897274, 0);
        swap(p, false, 96117745220, 1172015629480171985509, 85641226, 0);
        assert!(pool::sqrt_price<A, B>(p) == 617063116807289239486, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 70205, 2);
        assert!(pool::liquidity<A, B>(p) == 320666729897274, 3);
    }

    #[test]
    fun pool_case_95() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18197791486945181101, 5, 1);
        add(p, 863, true, 492, false, 91309, 20753899046788, 0, 20753898977704);
        add(p, 513, true, 227, false, 78261748, 3218230967, 0, 3181156461);
        assert!(pool::liquidity<A, B>(p) == 3137182009, 0);
        swap(p, true, 7474249825846, 19812, 37143588, 7474211175313);
        assert!(pool::sqrt_price<A, B>(p) == 17667734020254669931, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294966432, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_96() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18734881496810216086, 5, 10);
        add(p, 6470, true, 6520, false, 5448176, 7545435832214, 0, 7545429778838);
        add(p, 240, false, 2350, false, 31773, 6993121645729, 0, 6993121644548);
        assert!(pool::liquidity<A, B>(p) == 21063791, 0);
        swap(p, false, 770416751, 17175572088390372486202642652453860, 5479947, 762710840);
        swap(p, true, 328656411757, 19812, 0, 328656411757);
        assert!(pool::sqrt_price<A, B>(p) == 25555986207179199899, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 6520, 2);
        assert!(pool::liquidity<A, B>(p) == 0, 3);
    }

    #[test]
    fun pool_case_97() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(19380848972008639241, 100, 200);
        add(p, 143000, true, 12600, false, 1387368829, 1644, 1387368172, 0);
        add(p, 52200, true, 99200, false, 97827616126, 9859, 97827606593, 0);
        add(p, 141000, true, 60600, false, 5886797651, 471214447, 5481249185, 0);
        assert!(pool::liquidity<A, B>(p) == 448885552, 0);
        swap(p, true, 3548327, 536716497044427638, 3845994, 0);
        swap(p, true, 55813567541983, 2827609494750787275, 398962761, 55811044639045);
        assert!(pool::sqrt_price<A, B>(p) == 2827609494750787275, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 4294929785, 2);
        assert!(pool::liquidity<A, B>(p) == 448885552, 3);
    }

    #[test]
    fun pool_case_98() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(18617151452172022595, 5, 60);
        add(p, 9720, true, 8880, false, 5647, 139181977733526, 0, 139181977727155);
        add(p, 20700, true, 19920, false, 379479592162829, 5892877502, 379473992297677, 0);
        assert!(pool::liquidity<A, B>(p) == 9010628122, 0);
        swap(p, true, 181, 7870176362183926548, 182, 0);
        assert!(pool::sqrt_price<A, B>(p) == 18617151078222496918, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 183, 2);
        assert!(pool::liquidity<A, B>(p) == 9010628122, 3);
    }

    #[test]
    fun pool_case_99() acquires Caps {
        setup();
        let p = pool::create_pool<A, B>(17650075999602487806, 0, 10);
        add(p, 8070, true, 3330, false, 55301556159662, 470479710, 55301232798557, 0);
        add(p, 7080, true, 810, true, 8954, 7238540, 0, 6639055);
        add(p, 7090, true, 6690, false, 107860840920, 77195094021463, 0, 77111512178064);
        assert!(pool::liquidity<A, B>(p) == 329048889615, 0);
        swap(p, false, 82226001970, 17175572088390372486202642652453860, 71216021331, 0);
        assert!(pool::sqrt_price<A, B>(p) == 22262108882286828963, 1);
        assert!(i32::bits(pool::current_tick<A, B>(p)) == 3760, 2);
        assert!(pool::liquidity<A, B>(p) == 327417571784, 3);
    }
}
