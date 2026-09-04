/// Finding the next tick where liquidity changes.
///
/// A swap walks from one liquidity boundary to the next, and there are 1.38
/// million ticks in range. Scanning them one at a time is hopeless, and most
/// are empty -- a pool with fifty positions has at most a hundred boundaries.
///
/// So initialized ticks are recorded in a bitmap: one bit per usable tick,
/// packed 256 to a word. Finding the next boundary inside the current word is
/// then a mask and a bit scan, and only when a word runs out empty does the
/// caller fetch the next one. In practice a swap touches one or two words.
///
/// This module is the bit arithmetic only -- it takes a word and returns an
/// answer. The pool owns the storage that maps word positions to words, which
/// keeps everything here callable without constructing an object.
///
/// # Tick spacing
///
/// Positions may only start and end on ticks divisible by the pool's spacing.
/// A 1bp pool might use spacing 1, a volatile pool 60. Dividing the tick by the
/// spacing gives a *compressed* tick, and it is compressed ticks that the
/// bitmap indexes -- otherwise a spacing-60 pool would waste 59 of every 60
/// bits.
module braid_clmm::tick_bitmap {
    use braid_clmm::i32::{Self, I32};
    use braid_math::full_math;

    /// Tick spacing must be positive.
    const EInvalidTickSpacing: u64 = 0;
    /// Asked for a bit position in an empty word.
    const EZeroWord: u64 = 1;
    /// A scaled tick left the representable range.
    const EOverflow: u64 = 2;

    const U256_MAX: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    const MAX_MAGNITUDE: u64 = 2147483647;

    // ------------------------------------------------------------------ //
    // Bit scanning                                                       //
    // ------------------------------------------------------------------ //

    /// Index of the highest set bit.
    public fun msb(x: u256): u8 {
        assert!(x != 0, EZeroWord);
        ((full_math::bit_length(x) - 1) as u8)
    }

    /// Index of the lowest set bit.
    ///
    /// `x & (-x)` clears everything except the lowest set bit -- the standard
    /// trick, written as `x & ((~x) + 1)` because Move has no unary minus on
    /// unsigned types.
    public fun lsb(x: u256): u8 {
        assert!(x != 0, EZeroWord);
        let isolated = x & ((x ^ U256_MAX) + 1);
        ((full_math::bit_length(isolated) - 1) as u8)
    }

    public fun is_set(word: u256, bit_pos: u8): bool {
        word & (1u256 << bit_pos) != 0
    }

    /// Toggle one bit. Called when a position is opened or closed at a tick.
    public fun flip(word: u256, bit_pos: u8): u256 {
        word ^ (1u256 << bit_pos)
    }

    // ------------------------------------------------------------------ //
    // Tick <-> bitmap coordinates                                        //
    // ------------------------------------------------------------------ //

    /// Divide a tick by the spacing, rounding toward negative infinity.
    ///
    /// The rounding is the trap. Move's division truncates toward zero, so
    /// `-5 / 10` is 0 and tick -5 would share a slot with tick 0 and tick +5.
    /// Flooring puts it at -1 where it belongs, and keeps the bitmap
    /// monotonic in the tick.
    public fun compress(tick: I32, tick_spacing: u32): I32 {
        assert!(tick_spacing > 0, EInvalidTickSpacing);
        let magnitude = i32::abs_u32(tick);
        let quotient = magnitude / tick_spacing;
        if (!i32::is_neg(tick)) {
            i32::from_u32(quotient)
        } else if (magnitude % tick_spacing == 0) {
            i32::neg_from(quotient)
        } else {
            i32::neg_from(quotient + 1)
        }
    }

    /// Split a compressed tick into the word holding it and its bit inside.
    ///
    /// The word index is an arithmetic shift, so negative ticks walk downward
    /// into negative words. The bit index is the low 8 bits, which are already
    /// correct in two's complement whatever the sign.
    public fun position(compressed: I32): (I32, u8) {
        (i32::shr(compressed, 8), ((i32::bits(compressed) & 255) as u8))
    }

    /// Undo the compression. Aborts rather than wrapping if the product leaves
    /// the signed range.
    fun scale(compressed: I32, tick_spacing: u32): I32 {
        let magnitude = (i32::abs_u32(compressed) as u64) * (tick_spacing as u64);
        assert!(magnitude <= MAX_MAGNITUDE, EOverflow);
        if (i32::is_neg(compressed)) {
            i32::neg_from((magnitude as u32))
        } else {
            i32::from_u32((magnitude as u32))
        }
    }

    // ------------------------------------------------------------------ //
    // The search                                                         //
    // ------------------------------------------------------------------ //

    /// The next initialized tick in one direction, if it lies in this word.
    ///
    /// `word` must be the one `position` names for `tick`. Returns the tick and
    /// whether it is actually initialized: when the word runs out empty the
    /// returned tick is the word's boundary, and the caller advances to it,
    /// loads the next word, and asks again. That boundary is a real answer, not
    /// a failure -- the price may legitimately move that far with no liquidity
    /// change, and stopping there bounds how much work one call does.
    ///
    /// `lte` searches downward (price falling, token0 in) and includes the
    /// current tick; upward search excludes it, so a swap that has just crossed
    /// a boundary does not immediately find it again.
    public fun next_initialized_tick_within_word(
        word: u256,
        tick: I32,
        tick_spacing: u32,
        lte: bool,
    ): (I32, bool) {
        let compressed = compress(tick, tick_spacing);

        if (lte) {
            let (_, bit_pos) = position(compressed);

            // Every bit at or below the current one.
            let mask = if (bit_pos == 255) {
                U256_MAX
            } else {
                (1u256 << (bit_pos + 1)) - 1
            };
            let masked = word & mask;

            if (masked != 0) {
                let steps = bit_pos - msb(masked);
                (scale(i32::sub(compressed, i32::from_u32((steps as u32))), tick_spacing), true)
            } else {
                (scale(i32::sub(compressed, i32::from_u32((bit_pos as u32))), tick_spacing), false)
            }
        } else {
            // Start from the next tick up, so the current one cannot match.
            let from = i32::add(compressed, i32::from_u32(1));
            let (_, bit_pos) = position(from);

            // Every bit at or above that one.
            let mask = U256_MAX ^ ((1u256 << bit_pos) - 1);
            let masked = word & mask;

            if (masked != 0) {
                let steps = lsb(masked) - bit_pos;
                (scale(i32::add(from, i32::from_u32((steps as u32))), tick_spacing), true)
            } else {
                let steps = 255 - bit_pos;
                (scale(i32::add(from, i32::from_u32((steps as u32))), tick_spacing), false)
            }
        }
    }

    /// The bit a tick occupies, for a caller about to flip it.
    ///
    /// Returns `(word_pos, bit_pos)`. The tick must already be a multiple of
    /// the spacing; the pool checks that when a position is created, since a
    /// misaligned tick would silently share a bit with its neighbour.
    public fun tick_position(tick: I32, tick_spacing: u32): (I32, u8) {
        position(compress(tick, tick_spacing))
    }
}
