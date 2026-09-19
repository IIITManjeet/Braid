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
module braid_router::generated_route_diff_tests {
    use braid_router::test_world;


    #[test]
    fun optimized_route_0() {
        // 8000000 in: cpmm 8192, stable 1867704, clmm 120904, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 8000000, vector[8192, 1867704, 120904, 6003200], 7986004);
        assert!(got == 7986004 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_1() {
        // 394902 in: cpmm 0, stable 354898, clmm 0, clob 40004
        let (got, unspent) = test_world::buy_eth(0, 394902, vector[0, 354898, 0, 40004], 394591);
        assert!(got == 394591 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_2() {
        // 6360559 in: cpmm 0, stable 797799, clmm 0, clob 5562760
        let (got, unspent) = test_world::buy_eth(0, 6360559, vector[0, 797799, 0, 5562760], 6351286);
        assert!(got == 6351286 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_3() {
        // 88772 in: cpmm 0, stable 88772, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 88772, vector[0, 88772, 0, 0], 88728);
        assert!(got == 88728 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_4() {
        // 10047 in: cpmm 0, stable 10047, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 10047, vector[0, 10047, 0, 0], 10041);
        assert!(got == 10041 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_5() {
        // 9814498 in: cpmm 27841, stable 3309526, clmm 473931, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 9814498, vector[27841, 3309526, 473931, 6003200], 9788982);
        assert!(got == 9788982 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_6() {
        // 560479 in: cpmm 0, stable 340457, clmm 0, clob 220022
        let (got, unspent) = test_world::buy_eth(0, 560479, vector[0, 340457, 0, 220022], 559985);
        assert!(got == 559985 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_7() {
        // 27765 in: cpmm 0, stable 27765, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 27765, vector[0, 27765, 0, 0], 27752);
        assert!(got == 27752 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_8() {
        // 82760432 in: cpmm 57140077, stable 14449386, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 82760432, vector[57140077, 14449386, 5167769, 6003200], 29408603);
        assert!(got == 29408603 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_9() {
        // 20795272 in: cpmm 938730, stable 8685574, clmm 5167768, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 20795272, vector[938730, 8685574, 5167768, 6003200], 20288499);
        assert!(got == 20288499 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_10() {
        // 47688966 in: cpmm 24468864, stable 12049133, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 47688966, vector[24468864, 12049133, 5167769, 6003200], 27889123);
        assert!(got == 27889123 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_11() {
        // 80041 in: cpmm 0, stable 80041, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 80041, vector[0, 80041, 0, 0], 80001);
        assert!(got == 80001 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_12() {
        // 830110 in: cpmm 0, stable 350062, clmm 0, clob 480048
        let (got, unspent) = test_world::buy_eth(0, 830110, vector[0, 350062, 0, 480048], 829320);
        assert!(got == 829320 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_13() {
        // 39866652 in: cpmm 17245465, stable 11450218, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 39866652, vector[17245465, 11450218, 5167769, 6003200], 27054940);
        assert!(got == 27054940 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_14() {
        // 828352 in: cpmm 0, stable 378307, clmm 0, clob 450045
        let (got, unspent) = test_world::buy_eth(0, 828352, vector[0, 378307, 0, 450045], 827563);
        assert!(got == 827563 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_15() {
        // 51661249 in: cpmm 28147651, stable 12342629, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 51661249, vector[28147651, 12342629, 5167769, 6003200], 28191626);
        assert!(got == 28191626 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_16() {
        // 37136405 in: cpmm 14734068, stable 11231368, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 37136405, vector[14734068, 11231368, 5167769, 6003200], 26649449);
        assert!(got == 26649449 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_17() {
        // 6655949 in: cpmm 0, stable 792889, clmm 0, clob 5863060
        let (got, unspent) = test_world::buy_eth(0, 6655949, vector[0, 792889, 0, 5863060], 6646086);
        assert!(got == 6646086 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_18() {
        // 508969 in: cpmm 0, stable 358954, clmm 0, clob 150015
        let (got, unspent) = test_world::buy_eth(0, 508969, vector[0, 358954, 0, 150015], 508532);
        assert!(got == 508532 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_19() {
        // 17126 in: cpmm 0, stable 17126, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 17126, vector[0, 17126, 0, 0], 17118);
        assert!(got == 17118 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_20() {
        // 76336198 in: cpmm 51134009, stable 14031220, clmm 5167769, clob 6003200
        let (got, unspent) = test_world::buy_eth(0, 76336198, vector[51134009, 14031220, 5167769, 6003200], 29251788);
        assert!(got == 29251788 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_21() {
        // 241841 in: cpmm 0, stable 241841, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 241841, vector[0, 241841, 0, 0], 241686);
        assert!(got == 241686 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_22() {
        // 3796226 in: cpmm 0, stable 555406, clmm 0, clob 3240820
        let (got, unspent) = test_world::buy_eth(0, 3796226, vector[0, 555406, 0, 3240820], 3791636);
        assert!(got == 3791636 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_23() {
        // 318136 in: cpmm 0, stable 318136, clmm 0, clob 0
        let (got, unspent) = test_world::buy_eth(0, 318136, vector[0, 318136, 0, 0], 317907);
        assert!(got == 317907 && unspent == 0, 0);
    }

    #[test]
    fun optimized_route_24() {
        // 403757 in: cpmm 0, stable 343751, clmm 0, clob 60006
        let (got, unspent) = test_world::buy_eth(0, 403757, vector[0, 343751, 0, 60006], 403435);
        assert!(got == 403435 && unspent == 0, 0);
    }
}
