#[test_only]
module braid_clmm::tick_bitmap_tests {
    use braid_clmm::i32::{Self, I32};
    use braid_clmm::tick_bitmap as tb;

    fun pos(v: u32): I32 { i32::from_u32(v) }
    fun neg(v: u32): I32 { i32::neg_from(v) }

    /// Set the bits a list of ticks occupies, all assumed to be in one word.
    fun word_with(ticks: vector<I32>, spacing: u32): u256 {
        let mut w: u256 = 0;
        let mut i = 0;
        while (i < ticks.length()) {
            let (_, bit) = tb::tick_position(ticks[i], spacing);
            w = tb::flip(w, bit);
            i = i + 1;
        };
        w
    }

    // ---------------------------------------------------------------- //
    // Bit scanning                                                     //
    // ---------------------------------------------------------------- //

    #[test]
    fun msb_and_lsb_find_the_ends() {
        assert!(tb::msb(1) == 0, 0);
        assert!(tb::lsb(1) == 0, 1);
        assert!(tb::msb(10) == 3, 2);   // 0b1010
        assert!(tb::lsb(10) == 1, 3);   // 0b1010
        assert!(tb::msb(1u256 << 255) == 255, 4);
        assert!(tb::lsb(1u256 << 255) == 255, 5);
        // A word with both ends set.
        let w = (1u256 << 255) | 1;
        assert!(tb::msb(w) == 255, 6);
        assert!(tb::lsb(w) == 0, 7);
    }

    #[test]
    fun flip_is_its_own_inverse() {
        let w = tb::flip(0, 7);
        assert!(tb::is_set(w, 7), 0);
        assert!(!tb::is_set(w, 8), 1);
        assert!(tb::flip(w, 7) == 0, 2);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_bitmap::EZeroWord)]
    fun scanning_an_empty_word_is_rejected() {
        tb::msb(0);
    }

    // ---------------------------------------------------------------- //
    // Compression                                                      //
    // ---------------------------------------------------------------- //

    #[test]
    fun compression_floors_rather_than_truncating() {
        // The trap. Move's division truncates toward zero, which would put
        // -5, 0 and +5 in the same slot at spacing 10.
        assert!(i32::eq(tb::compress(neg(5), 10), neg(1)), 0);
        assert!(i32::eq(tb::compress(i32::zero(), 10), i32::zero()), 1);
        assert!(i32::eq(tb::compress(pos(5), 10), i32::zero()), 2);

        // Exact multiples land cleanly in both directions.
        assert!(i32::eq(tb::compress(neg(10), 10), neg(1)), 3);
        assert!(i32::eq(tb::compress(neg(20), 10), neg(2)), 4);
        assert!(i32::eq(tb::compress(pos(10), 10), pos(1)), 5);

        // Just past a multiple.
        assert!(i32::eq(tb::compress(neg(11), 10), neg(2)), 6);
        assert!(i32::eq(tb::compress(pos(11), 10), pos(1)), 7);
    }

    #[test]
    fun compression_is_monotonic_across_zero() {
        // Whatever the spacing, walking the ticks upward must never walk the
        // compressed value downward -- the bitmap's whole ordering depends on
        // it, and truncation would break it exactly at zero.
        let spacings = vector[1u32, 10, 60, 200];
        let mut s = 0;
        while (s < 4) {
            let spacing = spacings[s];
            let mut t = neg(500);
            let mut prev = tb::compress(t, spacing);
            let mut i = 0;
            while (i < 1000) {
                t = i32::add(t, pos(1));
                let c = tb::compress(t, spacing);
                assert!(i32::gte(c, prev), s);
                prev = c;
                i = i + 1;
            };
            s = s + 1;
        };
    }

    #[test]
    fun position_splits_into_word_and_bit() {
        // Compressed 0 is word 0, bit 0.
        let (w0, b0) = tb::position(i32::zero());
        assert!(i32::eq(w0, i32::zero()) && b0 == 0, 0);

        // Compressed 255 is still word 0.
        let (w1, b1) = tb::position(pos(255));
        assert!(i32::eq(w1, i32::zero()) && b1 == 255, 1);

        // 256 rolls into word 1.
        let (w2, b2) = tb::position(pos(256));
        assert!(i32::eq(w2, pos(1)) && b2 == 0, 2);

        // Negatives walk into negative words, not back toward zero.
        let (w3, b3) = tb::position(neg(1));
        assert!(i32::eq(w3, neg(1)) && b3 == 255, 3);

        let (w4, b4) = tb::position(neg(256));
        assert!(i32::eq(w4, neg(1)) && b4 == 0, 4);

        let (w5, b5) = tb::position(neg(257));
        assert!(i32::eq(w5, neg(2)) && b5 == 255, 5);
    }

    // ---------------------------------------------------------------- //
    // The search                                                       //
    // ---------------------------------------------------------------- //

    #[test]
    fun searching_down_finds_the_nearest_initialized_tick() {
        let spacing = 1;
        let word = word_with(vector[pos(10), pos(50), pos(70)], spacing);

        // From 70 downward, 70 itself qualifies -- the downward search is
        // inclusive, because a swap arriving at a boundary has not crossed it.
        let (t, ok) = tb::next_initialized_tick_within_word(word, pos(70), spacing, true);
        assert!(ok && i32::eq(t, pos(70)), 0);

        // From 69, the next one down is 50.
        let (t2, ok2) = tb::next_initialized_tick_within_word(word, pos(69), spacing, true);
        assert!(ok2 && i32::eq(t2, pos(50)), 1);

        // From 49, down to 10.
        let (t3, ok3) = tb::next_initialized_tick_within_word(word, pos(49), spacing, true);
        assert!(ok3 && i32::eq(t3, pos(10)), 2);
    }

    #[test]
    fun searching_up_skips_the_current_tick() {
        let spacing = 1;
        let word = word_with(vector[pos(10), pos(50), pos(70)], spacing);

        // From 10 upward, 10 does not count -- otherwise a swap that just
        // crossed a boundary would find it again and never progress.
        let (t, ok) = tb::next_initialized_tick_within_word(word, pos(10), spacing, false);
        assert!(ok && i32::eq(t, pos(50)), 0);

        let (t2, ok2) = tb::next_initialized_tick_within_word(word, pos(50), spacing, false);
        assert!(ok2 && i32::eq(t2, pos(70)), 1);
    }

    #[test]
    fun an_empty_word_returns_its_boundary_and_says_so() {
        let spacing = 1;
        let word: u256 = 0;

        // Downward from bit 100 with nothing set: stop at the bottom of the
        // word, bit 0, and report "not initialized".
        let (t, ok) = tb::next_initialized_tick_within_word(word, pos(100), spacing, true);
        assert!(!ok, 0);
        assert!(i32::eq(t, i32::zero()), 1);

        // Upward: stop at the top of the word, bit 255.
        let (t2, ok2) = tb::next_initialized_tick_within_word(word, pos(100), spacing, false);
        assert!(!ok2, 2);
        assert!(i32::eq(t2, pos(255)), 3);
    }

    #[test]
    fun the_search_works_below_zero() {
        let spacing = 1;
        // Ticks -1 and -200 both live in word -1.
        let word = word_with(vector[neg(1), neg(200)], spacing);

        let (t, ok) = tb::next_initialized_tick_within_word(word, neg(1), spacing, true);
        assert!(ok && i32::eq(t, neg(1)), 0);

        let (t2, ok2) = tb::next_initialized_tick_within_word(word, neg(2), spacing, true);
        assert!(ok2 && i32::eq(t2, neg(200)), 1);

        let (t3, ok3) = tb::next_initialized_tick_within_word(word, neg(200), spacing, false);
        assert!(ok3 && i32::eq(t3, neg(1)), 2);
    }

    #[test]
    fun spacing_scales_the_answer_back_to_real_ticks() {
        let spacing = 60;
        // Real ticks 600 and 1200 compress to 10 and 20.
        let word = word_with(vector[pos(600), pos(1200)], spacing);

        let (t, ok) = tb::next_initialized_tick_within_word(word, pos(1200), spacing, true);
        assert!(ok && i32::eq(t, pos(1200)), 0);

        let (t2, ok2) = tb::next_initialized_tick_within_word(word, pos(1199), spacing, true);
        assert!(ok2 && i32::eq(t2, pos(600)), 1);

        let (t3, ok3) = tb::next_initialized_tick_within_word(word, pos(600), spacing, false);
        assert!(ok3 && i32::eq(t3, pos(1200)), 2);
    }

    #[test]
    fun a_tick_between_multiples_still_finds_its_neighbours() {
        let spacing = 60;
        let word = word_with(vector[pos(600), pos(1200)], spacing);

        // 900 is not a multiple of 60. Compressed it floors to 15, so the
        // search downward should still reach 600.
        let (t, ok) = tb::next_initialized_tick_within_word(word, pos(900), spacing, true);
        assert!(ok && i32::eq(t, pos(600)), 0);

        let (t2, ok2) = tb::next_initialized_tick_within_word(word, pos(900), spacing, false);
        assert!(ok2 && i32::eq(t2, pos(1200)), 1);
    }

    #[test]
    fun walking_a_word_visits_every_initialized_tick_in_order() {
        // The loop a swap actually runs: step to the boundary, then search
        // again from just past it.
        let spacing = 1;
        let word = word_with(vector[pos(3), pos(11), pos(90), pos(200)], spacing);

        let mut cursor = i32::zero();
        let mut found = vector<u32>[];
        let mut guard = 0;
        while (guard < 10) {
            let (t, ok) = tb::next_initialized_tick_within_word(word, cursor, spacing, false);
            if (!ok) break;
            found.push_back(i32::abs_u32(t));
            cursor = t;
            guard = guard + 1;
        };

        assert!(found.length() == 4, 0);
        assert!(found[0] == 3, 1);
        assert!(found[1] == 11, 2);
        assert!(found[2] == 90, 3);
        assert!(found[3] == 200, 4);
    }

    #[test]
    #[expected_failure(abort_code = braid_clmm::tick_bitmap::EInvalidTickSpacing)]
    fun a_zero_spacing_is_rejected() {
        tb::compress(pos(100), 0);
    }
}
