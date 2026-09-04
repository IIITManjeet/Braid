/// A signed 32-bit integer, because Move has none and ticks need one.
///
/// Everything else in Braid is unsigned. A tick is the exception because it is
/// not a price but the exponent of one -- `price = 1.0001^tick`, so anything
/// below 1.0 needs a negative tick.
///
/// Two's complement in a u32: one representation of zero, and add/sub need no
/// case analysis. The arithmetic goes through u64 and reduces mod 2^32, since
/// Move aborts on u32 overflow and two's complement depends on that wrap.
///
/// The raw bits are meaningless read as a u32 (-1 is 4294967295), so nothing
/// outside this module should look at them.
module braid_clmm::i32 {

    /// Magnitude exceeds what a signed 32-bit value can hold.
    const EOverflow: u64 = 0;

    /// `1 << 31`. Set in every negative value.
    const SIGN_BIT: u32 = 2147483648;
    /// `2^31 - 1`. The largest representable magnitude.
    const MAX_MAGNITUDE: u32 = 2147483647;
    /// `2^32`, used as the modulus. Held as a `u64` because it does not fit a
    /// `u32` -- which is the entire point of doing the arithmetic one width up.
    const WRAP: u64 = 4294967296;

    public struct I32 has copy, drop, store {
        bits: u32,
    }

    // ------------------------------------------------------------------ //
    // Construction                                                       //
    // ------------------------------------------------------------------ //

    public fun zero(): I32 { I32 { bits: 0 } }

    /// `+v`.
    public fun from_u32(v: u32): I32 {
        assert!(v <= MAX_MAGNITUDE, EOverflow);
        I32 { bits: v }
    }

    /// `-v`, given the magnitude.
    public fun neg_from(v: u32): I32 {
        assert!(v <= MAX_MAGNITUDE, EOverflow);
        if (v == 0) {
            I32 { bits: 0 }
        } else {
            I32 { bits: ((WRAP - (v as u64)) as u32) }
        }
    }

    /// Reinterpret a raw bit pattern. For deserialisation only -- prefer
    /// `from_u32` / `neg_from`, which cannot produce a surprising value.
    public fun from_bits(b: u32): I32 { I32 { bits: b } }

    /// The raw two's-complement bits. Meaningless as a magnitude.
    public fun bits(x: I32): u32 { x.bits }

    // ------------------------------------------------------------------ //
    // Sign and magnitude                                                 //
    // ------------------------------------------------------------------ //

    public fun is_neg(x: I32): bool { x.bits >= SIGN_BIT }

    /// `|x|`, as an unsigned magnitude.
    public fun abs_u32(x: I32): u32 {
        if (is_neg(x)) {
            ((WRAP - (x.bits as u64)) as u32)
        } else {
            x.bits
        }
    }

    public fun neg(x: I32): I32 {
        if (x.bits == 0) {
            x
        } else {
            I32 { bits: ((WRAP - (x.bits as u64)) as u32) }
        }
    }

    // ------------------------------------------------------------------ //
    // Arithmetic                                                         //
    // ------------------------------------------------------------------ //
    //
    // Both go through `u64` and reduce modulo 2^32. Move aborts on `u32`
    // overflow, so the wrap that two's complement depends on has to be done
    // one width up and brought back down.

    public fun add(a: I32, b: I32): I32 {
        I32 { bits: ((((a.bits as u64) + (b.bits as u64)) % WRAP) as u32) }
    }

    public fun sub(a: I32, b: I32): I32 { add(a, neg(b)) }

    /// Arithmetic shift right, i.e. floor division by `2^n`.
    ///
    /// Not the same as shifting the raw bits: a logical shift pulls zeros into
    /// the top, which turns a negative into a large positive. The sign bit has
    /// to be smeared back down, so -1 >> 8 stays -1 rather than becoming
    /// 16777215.
    public fun shr(x: I32, n: u8): I32 {
        if (n == 0) return x;
        if (n >= 32) {
            // Everything has shifted out; only the sign survives.
            return if (is_neg(x)) { neg_from(1) } else { zero() }
        };
        let logical = x.bits >> n;
        if (is_neg(x)) {
            I32 { bits: logical | (4294967295u32 << (32 - n)) }
        } else {
            I32 { bits: logical }
        }
    }

    // ------------------------------------------------------------------ //
    // Comparison                                                         //
    // ------------------------------------------------------------------ //

    public fun eq(a: I32, b: I32): bool { a.bits == b.bits }

    /// Signed less-than.
    ///
    /// Different signs: the negative one is smaller, no comparison needed.
    /// Same sign: the unsigned comparison is already correct -- for two
    /// negatives, `-2` is `0xFFFFFFFE` and `-1` is `0xFFFFFFFF`, and
    /// `0xFFFFFFFE < 0xFFFFFFFF` gives `-2 < -1`.
    public fun lt(a: I32, b: I32): bool {
        let a_neg = is_neg(a);
        let b_neg = is_neg(b);
        if (a_neg != b_neg) { a_neg } else { a.bits < b.bits }
    }

    public fun gt(a: I32, b: I32): bool { lt(b, a) }

    public fun lte(a: I32, b: I32): bool { !lt(b, a) }

    public fun gte(a: I32, b: I32): bool { !lt(a, b) }

    public fun min(a: I32, b: I32): I32 { if (lt(a, b)) a else b }

    public fun max(a: I32, b: I32): I32 { if (lt(a, b)) b else a }
}
