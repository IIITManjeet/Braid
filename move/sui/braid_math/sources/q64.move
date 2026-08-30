/// Q64.64 unsigned fixed-point.
///
/// A value is a `u128` interpreted as `raw / 2^64`: the high 64 bits are the
/// integer part, the low 64 bits the fraction. That gives a range of
/// `[0, 2^64)` at a resolution of `2^-64` (~5.4e-20), which is what prices
/// need -- an orderbook tick and a CLMM sqrt-price both have to survive being
/// multiplied by a pool reserve without the rounding error reaching the last
/// unit of the output amount.
///
/// Nothing in Braid prices anything negative, so there is no signed variant.
/// Ticks are signed, but a tick is an exponent, not a price, and it lives in
/// the CLMM package.
///
/// Every operation that can lose information comes in a `_floor` / `_ceil`
/// pair with no unsuffixed default, for the reason spelled out in `full_math`:
/// truncation always moves value in one direction, so the direction has to be
/// chosen at the call site.
///
/// Overflow and divide-by-zero aborts from the delegating operations
/// (`mul_*`, `div_*`, `from_frac_*`, `sqrt`) carry `full_math`'s abort codes,
/// not this module's.
module braid_math::q64 {
    use braid_math::full_math;

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// Result did not fit in the target width.
    const EOverflow: u64 = 0;
    /// Subtraction would have gone below zero.
    const EUnderflow: u64 = 1;
    /// Denominator, or the value being inverted, was zero.
    const EDivideByZero: u64 = 2;

    // ------------------------------------------------------------------ //
    // Constants                                                          //
    // ------------------------------------------------------------------ //

    /// 2^64 -- the raw representation of 1.0.
    const Q64: u128 = 18446744073709551616;
    /// Mask selecting the fractional bits.
    const FRACT_MASK: u128 = 18446744073709551615;
    /// Mask selecting the integer bits.
    const INT_MASK: u128 = 340282366920938463444927863358058659840;

    const MAX_U64: u256 = 18446744073709551615;
    const MAX_U128: u256 = 340282366920938463463374607431768211455;

    /// The raw value of 1.0.
    public fun one(): u128 { Q64 }

    /// The raw value of 0.0.
    public fun zero(): u128 { 0 }

    /// Number of fractional bits in the representation.
    public fun fractional_bits(): u8 { 64 }

    // ------------------------------------------------------------------ //
    // Conversion in                                                      //
    // ------------------------------------------------------------------ //

    /// Exact: an integer is representable with a zero fraction. Cannot
    /// overflow, since `(2^64 - 1) * 2^64 < 2^128`.
    public fun from_u64(x: u64): u128 {
        (x as u128) << 64
    }

    /// `floor(num / denom)` as Q64.64.
    public fun from_frac_floor(num: u64, denom: u64): u128 {
        full_math::shl_div((num as u128), (denom as u128), 64)
    }

    /// `ceil(num / denom)` as Q64.64.
    public fun from_frac_ceil(num: u64, denom: u64): u128 {
        full_math::shl_div_ceil((num as u128), (denom as u128), 64)
    }

    // ------------------------------------------------------------------ //
    // Conversion out                                                     //
    // ------------------------------------------------------------------ //

    /// Integer part, discarding the fraction. Cannot overflow: a `u128`
    /// shifted right by 64 always fits a `u64`.
    public fun to_u64_floor(v: u128): u64 {
        ((v >> 64) as u64)
    }

    /// Smallest integer `>= v`.
    public fun to_u64_ceil(v: u128): u64 {
        let mut r = v >> 64;
        if (v & FRACT_MASK != 0) { r = r + 1 };
        assert!((r as u256) <= MAX_U64, EOverflow);
        (r as u64)
    }

    /// Fractional part, still scaled by `2^64`.
    public fun fract(v: u128): u128 { v & FRACT_MASK }

    /// `v` with its fraction cleared, still Q64.64.
    public fun floor(v: u128): u128 { v & INT_MASK }

    // ------------------------------------------------------------------ //
    // Arithmetic                                                         //
    // ------------------------------------------------------------------ //

    /// Exact. Aborts natively if the sum leaves `u128`.
    public fun add(a: u128, b: u128): u128 { a + b }

    /// Exact, with an explicit code rather than a native arithmetic abort.
    public fun sub(a: u128, b: u128): u128 {
        assert!(a >= b, EUnderflow);
        a - b
    }

    /// `floor(a * b)`. Both operands and the result are Q64.64.
    public fun mul_floor(a: u128, b: u128): u128 {
        full_math::mul_shr(a, b, 64)
    }

    /// `ceil(a * b)`.
    public fun mul_ceil(a: u128, b: u128): u128 {
        full_math::mul_shr_ceil(a, b, 64)
    }

    /// `floor(a / b)`.
    public fun div_floor(a: u128, b: u128): u128 {
        full_math::shl_div(a, b, 64)
    }

    /// `ceil(a / b)`.
    public fun div_ceil(a: u128, b: u128): u128 {
        full_math::shl_div_ceil(a, b, 64)
    }

    // ------------------------------------------------------------------ //
    // Mixed integer / fixed-point -- the workhorse                       //
    // ------------------------------------------------------------------ //
    //
    // Applying a price to an amount is the most common operation in the
    // exchange, and it is where the rounding decision has teeth: the result is
    // what a trader receives or pays.

    /// `floor(x * v)` -- integer in, integer out. For amounts paid *out*.
    public fun mul_u64_floor(x: u64, v: u128): u64 {
        let r = ((x as u256) * (v as u256)) >> 64;
        assert!(r <= MAX_U64, EOverflow);
        (r as u64)
    }

    /// `ceil(x * v)` -- for amounts collected *in*.
    public fun mul_u64_ceil(x: u64, v: u128): u64 {
        let n = (x as u256) * (v as u256);
        let mut r = n >> 64;
        if (n & MAX_U64 != 0) { r = r + 1 };
        assert!(r <= MAX_U64, EOverflow);
        (r as u64)
    }

    /// `floor(x / v)` -- integer in, integer out.
    public fun div_u64_floor(x: u64, v: u128): u64 {
        assert!(v != 0, EDivideByZero);
        let r = ((x as u256) << 64) / (v as u256);
        assert!(r <= MAX_U64, EOverflow);
        (r as u64)
    }

    /// `ceil(x / v)`.
    public fun div_u64_ceil(x: u64, v: u128): u64 {
        assert!(v != 0, EDivideByZero);
        let d = (v as u256);
        let n = (x as u256) << 64;
        let mut r = n / d;
        if (n % d != 0) { r = r + 1 };
        assert!(r <= MAX_U64, EOverflow);
        (r as u64)
    }

    // ------------------------------------------------------------------ //
    // sqrt, reciprocal, pow                                              //
    // ------------------------------------------------------------------ //

    /// `floor(sqrt(v))` in Q64.64.
    ///
    /// `sqrt(raw / 2^64) = sqrt(raw * 2^64) / 2^64`, so the raw input is
    /// widened and shifted left by 64 before the integer sqrt. The shifted
    /// value needs up to 192 bits, hence the `u256`; the result is at most
    /// `2^96` and always fits.
    public fun sqrt(v: u128): u128 {
        let r = full_math::sqrt_u256((v as u256) << 64);
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `floor(1 / v)`.
    ///
    /// `1 / (raw / 2^64) = 2^128 / raw`, so any `v` below `2^-64` in value --
    /// raw 1 -- inverts to `2^128` and overflows.
    public fun recip_floor(v: u128): u128 {
        assert!(v != 0, EDivideByZero);
        let r = (1u256 << 128) / (v as u256);
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `ceil(1 / v)`.
    public fun recip_ceil(v: u128): u128 {
        assert!(v != 0, EDivideByZero);
        let d = (v as u256);
        let n = 1u256 << 128;
        let mut r = n / d;
        if (n % d != 0) { r = r + 1 };
        assert!(r <= MAX_U128, EOverflow);
        (r as u128)
    }

    /// `floor(base^exp)` by exponentiation by squaring.
    ///
    /// Each squaring truncates, so the error compounds over `log2(exp)` steps
    /// rather than `exp` steps. Good enough for fee-growth accumulators; the
    /// CLMM's `1.0001^tick` will use a precomputed table instead, because there
    /// the error has to be bounded per tick rather than in aggregate.
    public fun pow_floor(base: u128, exp: u64): u128 {
        let mut result = Q64;
        let mut b = base;
        let mut e = exp;
        while (e > 0) {
            if (e & 1 == 1) { result = mul_floor(result, b) };
            e = e >> 1;
            if (e > 0) { b = mul_floor(b, b) };
        };
        result
    }

    // ------------------------------------------------------------------ //
    // Comparison                                                         //
    // ------------------------------------------------------------------ //

    public fun is_zero(v: u128): bool { v == 0 }

    public fun min(a: u128, b: u128): u128 { if (a < b) a else b }

    public fun max(a: u128, b: u128): u128 { if (a > b) a else b }
}
