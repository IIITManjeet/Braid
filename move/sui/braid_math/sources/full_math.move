/// 256-bit-intermediate multiply-divide with explicit rounding control.
///
/// Almost every price computation in an exchange is a `mul_div`. Two things go
/// wrong if you write it naively:
///
///   1. `a * b` overflows `u128` long before `a * b / d` would, so the
///      intermediate has to be widened to `u256`.
///   2. Integer division silently truncates, and truncation is not neutral --
///      it always moves value in the same direction. A swap that rounds its
///      output *up* leaks a unit to the trader on every fill; repeated a few
///      million times that drains the pool. So the rounding direction has to
///      be a deliberate choice at every call site, which means this library
///      must not offer a default.
///
/// The convention used throughout Braid: **round in favour of the pool**.
/// Exact-input swaps round the output down; exact-output swaps round the
/// required input up.
module braid_math::full_math {

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// Denominator was zero.
    const EDivideByZero: u64 = 0;
    /// Result did not fit in the target width.
    const EOverflow: u64 = 1;

    // ------------------------------------------------------------------ //
    // Constants                                                          //
    // ------------------------------------------------------------------ //

    const MAX_U64: u256 = 18446744073709551615;
    const MAX_U128: u256 = 340282366920938463463374607431768211455;

    public fun max_u64(): u64 { 18446744073709551615 }

    public fun max_u128(): u128 { 340282366920938463463374607431768211455 }

    // ------------------------------------------------------------------ //
    // Widening multiply                                                  //
    // ------------------------------------------------------------------ //

    /// Exact `a * b` as a `u256`. Cannot overflow: the product of two `u128`s
    /// is at most `(2^128 - 1)^2`, which is less than `2^256`.
    public fun full_mul(a: u128, b: u128): u256 {
        (a as u256) * (b as u256)
    }

    // ------------------------------------------------------------------ //
    // mul_div -- u128                                                    //
    // ------------------------------------------------------------------ //

    /// `floor(a * b / denom)`.
    public fun mul_div_floor(a: u128, b: u128, denom: u128): u128 {
        assert!(denom != 0, EDivideByZero);
        let r = full_mul(a, b) / (denom as u256);
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `ceil(a * b / denom)`.
    public fun mul_div_ceil(a: u128, b: u128, denom: u128): u128 {
        assert!(denom != 0, EDivideByZero);
        let d = (denom as u256);
        let n = full_mul(a, b);
        // Computed as `n / d` plus a correction rather than `(n + d - 1) / d`,
        // because `n + d - 1` can itself overflow `u256` when `n` sits near the
        // top of the range.
        let mut r = n / d;
        if (n % d != 0) { r = r + 1 };
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `round(a * b / denom)`, ties away from zero.
    public fun mul_div_round(a: u128, b: u128, denom: u128): u128 {
        assert!(denom != 0, EDivideByZero);
        let d = (denom as u256);
        let n = full_mul(a, b);
        let mut r = n / d;
        // `rem < d <= 2^128`, so `rem * 2 < 2^129` and cannot overflow u256.
        if ((n % d) * 2 >= d) { r = r + 1 };
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    // ------------------------------------------------------------------ //
    // mul_div -- u64 convenience wrappers                                //
    // ------------------------------------------------------------------ //

    /// `floor(a * b / denom)` over `u64` operands and result.
    public fun mul_div_floor_u64(a: u64, b: u64, denom: u64): u64 {
        assert!(denom != 0, EDivideByZero);
        let r = ((a as u128) * (b as u128)) / (denom as u128);
        assert!((r as u256) <= MAX_U64, EOverflow);
        (r as u64)
    }

    /// `ceil(a * b / denom)` over `u64` operands and result.
    public fun mul_div_ceil_u64(a: u64, b: u64, denom: u64): u64 {
        assert!(denom != 0, EDivideByZero);
        let d = (denom as u128);
        let n = (a as u128) * (b as u128);
        let mut r = n / d;
        if (n % d != 0) { r = r + 1 };
        assert!((r as u256) <= MAX_U64, EOverflow);
        (r as u64)
    }

    // ------------------------------------------------------------------ //
    // Shifts with 256-bit intermediates                                  //
    // ------------------------------------------------------------------ //

    /// `floor(a * b / 2^shift)`. The fixed-point multiply primitive.
    public fun mul_shr(a: u128, b: u128, shift: u8): u128 {
        let r = full_mul(a, b) >> shift;
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `ceil(a * b / 2^shift)`.
    public fun mul_shr_ceil(a: u128, b: u128, shift: u8): u128 {
        let n = full_mul(a, b);
        let mut r = n >> shift;
        // Any discarded low bit means the shift truncated.
        if (n & ((1u256 << shift) - 1) != 0) { r = r + 1 };
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `floor((a << shift) / denom)`. The fixed-point divide primitive.
    public fun shl_div(a: u128, denom: u128, shift: u8): u128 {
        assert!(denom != 0, EDivideByZero);
        let r = ((a as u256) << shift) / (denom as u256);
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `ceil((a << shift) / denom)`.
    public fun shl_div_ceil(a: u128, denom: u128, shift: u8): u128 {
        assert!(denom != 0, EDivideByZero);
        let d = (denom as u256);
        let n = ((a as u256) << shift);
        let mut r = n / d;
        if (n % d != 0) { r = r + 1 };
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    // ------------------------------------------------------------------ //
    // Integer square root                                                //
    // ------------------------------------------------------------------ //

    /// Number of significant bits in `x` (0 when `x == 0`).
    ///
    /// Binary search over the width rather than a loop over 256 bits, so the
    /// cost is a fixed 8 comparisons instead of being input-dependent.
    public fun bit_length(x: u256): u16 {
        if (x == 0) return 0;
        let mut v = x;
        let mut n: u16 = 1;
        if (v >> 128 != 0) { v = v >> 128; n = n + 128 };
        if (v >> 64 != 0) { v = v >> 64; n = n + 64 };
        if (v >> 32 != 0) { v = v >> 32; n = n + 32 };
        if (v >> 16 != 0) { v = v >> 16; n = n + 16 };
        if (v >> 8 != 0) { v = v >> 8; n = n + 8 };
        if (v >> 4 != 0) { v = v >> 4; n = n + 4 };
        if (v >> 2 != 0) { v = v >> 2; n = n + 2 };
        if (v >> 1 != 0) { n = n + 1 };
        n
    }

    /// `floor(sqrt(x))` for a `u256`.
    ///
    /// Newton's method. The seed is `2^ceil(bits(x)/2)`, which is guaranteed to
    /// be `>= sqrt(x)`; from an over-estimate the iteration decreases
    /// monotonically, so the first non-decreasing step lands on the floor.
    /// Seeding this way rather than with `x` itself also keeps `z + x / z`
    /// clear of the top of the `u256` range.
    public fun sqrt_u256(x: u256): u256 {
        if (x == 0) return 0;
        if (x < 4) return 1;

        let shift = (((bit_length(x) + 1) / 2) as u8);
        let mut z: u256 = 1 << shift;
        loop {
            let next = (z + x / z) >> 1;
            if (next >= z) break;
            z = next;
        };
        z
    }

    /// `floor(sqrt(x))` for a `u128`.
    public fun sqrt_u128(x: u128): u128 {
        (sqrt_u256(x as u256) as u128)
    }

    /// `floor(sqrt(a * b))` without losing the intermediate to overflow.
    /// This is the constant-product initial-LP-share formula.
    public fun sqrt_mul(a: u128, b: u128): u128 {
        let r = sqrt_u256(full_mul(a, b));
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    // ------------------------------------------------------------------ //
    // Misc                                                               //
    // ------------------------------------------------------------------ //

    public fun min_u128(a: u128, b: u128): u128 { if (a < b) a else b }

    public fun max_of_u128(a: u128, b: u128): u128 { if (a > b) a else b }

    public fun min_u64(a: u64, b: u64): u64 { if (a < b) a else b }

    public fun max_of_u64(a: u64, b: u64): u64 { if (a > b) a else b }

    /// `|a - b|`.
    public fun abs_diff(a: u128, b: u128): u128 { if (a > b) a - b else b - a }
}
