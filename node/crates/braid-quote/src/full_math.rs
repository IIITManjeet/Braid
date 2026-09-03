//! Rust mirror of `braid_math::full_math`.
//!
//! Every function here corresponds one-to-one with a Move function of the same
//! name, and must produce the *identical* value for every input. This is not a
//! reimplementation with the same intent -- it is a transliteration. Where the
//! Move code widens to `u256` before dividing, so does this; where it divides
//! twice in sequence rather than by a product, so does this.
//!
//! The reason is the differential fuzzer: random inputs go through both this and
//! the on-chain bytecode via `dev-inspect`, and a one-unit disagreement fails
//! the test. Any "tidying up" of the arithmetic here is a bug, however much
//! better it looks.

use ethnum::U256;

/// Mirrors the abort codes in the Move module, so a divergence in *failure*
/// is as detectable as a divergence in value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MathError {
    /// `EDivideByZero` -- Move abort code 0.
    DivideByZero,
    /// `EOverflow` -- Move abort code 1.
    Overflow,
}

impl MathError {
    /// The `u64` abort code the Move module would raise.
    pub fn abort_code(self) -> u64 {
        match self {
            MathError::DivideByZero => 0,
            MathError::Overflow => 1,
        }
    }
}

pub type Result<T> = core::result::Result<T, MathError>;

pub const MAX_U64: u128 = u64::MAX as u128;

#[inline]
fn u256(v: u128) -> U256 {
    U256::from(v)
}

/// Narrow a `u256` back to `u128`, checked -- the Move `assert!(r <= MAX_U128)`.
#[inline]
fn narrow_u128(v: U256) -> Result<u128> {
    if v > u256(u128::MAX) {
        Err(MathError::Overflow)
    } else {
        Ok(v.as_u128())
    }
}

// ---------------------------------------------------------------------------
// Widening multiply
// ---------------------------------------------------------------------------

/// Exact `a * b`. Cannot overflow: `(2^128 - 1)^2 < 2^256`.
#[inline]
pub fn full_mul(a: u128, b: u128) -> U256 {
    u256(a) * u256(b)
}

// ---------------------------------------------------------------------------
// mul_div -- u128
// ---------------------------------------------------------------------------

pub fn mul_div_floor(a: u128, b: u128, denom: u128) -> Result<u128> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    narrow_u128(full_mul(a, b) / u256(denom))
}

pub fn mul_div_ceil(a: u128, b: u128, denom: u128) -> Result<u128> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    let d = u256(denom);
    let n = full_mul(a, b);
    // `n / d` plus a correction, never `(n + d - 1) / d` -- the latter overflows
    // when `n` sits near the top of the u256 range.
    let mut r = n / d;
    if n % d != 0u128 {
        r += 1u128;
    }
    narrow_u128(r)
}

pub fn mul_div_round(a: u128, b: u128, denom: u128) -> Result<u128> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    let d = u256(denom);
    let n = full_mul(a, b);
    let mut r = n / d;
    if (n % d) * 2u128 >= d {
        r += 1u128;
    }
    narrow_u128(r)
}

// ---------------------------------------------------------------------------
// mul_div -- u64 wrappers
// ---------------------------------------------------------------------------

pub fn mul_div_floor_u64(a: u64, b: u64, denom: u64) -> Result<u64> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    // The Move version uses a u128 intermediate here, not u256.
    let r = (a as u128) * (b as u128) / (denom as u128);
    if r > MAX_U64 {
        Err(MathError::Overflow)
    } else {
        Ok(r as u64)
    }
}

pub fn mul_div_ceil_u64(a: u64, b: u64, denom: u64) -> Result<u64> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    let d = denom as u128;
    let n = (a as u128) * (b as u128);
    let mut r = n / d;
    if n % d != 0u128 {
        r += 1u128;
    }
    if r > MAX_U64 {
        Err(MathError::Overflow)
    } else {
        Ok(r as u64)
    }
}

// ---------------------------------------------------------------------------
// Shifts
// ---------------------------------------------------------------------------

pub fn mul_shr(a: u128, b: u128, shift: u32) -> Result<u128> {
    narrow_u128(full_mul(a, b) >> shift)
}

pub fn mul_shr_ceil(a: u128, b: u128, shift: u32) -> Result<u128> {
    let n = full_mul(a, b);
    let mut r = n >> shift;
    if n & ((U256::ONE << shift) - 1) != 0u128 {
        r += 1u128;
    }
    narrow_u128(r)
}

pub fn shl_div(a: u128, denom: u128, shift: u32) -> Result<u128> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    narrow_u128((u256(a) << shift) / u256(denom))
}

pub fn shl_div_ceil(a: u128, denom: u128, shift: u32) -> Result<u128> {
    if denom == 0 {
        return Err(MathError::DivideByZero);
    }
    let d = u256(denom);
    let n = u256(a) << shift;
    let mut r = n / d;
    if n % d != 0u128 {
        r += 1u128;
    }
    narrow_u128(r)
}

// ---------------------------------------------------------------------------
// Integer square root
// ---------------------------------------------------------------------------

/// Significant bits in `x`, 0 when `x == 0`.
///
/// Binary search over the width, exactly as the Move version does -- eight
/// comparisons regardless of input.
pub fn bit_length(x: U256) -> u16 {
    if x == 0u128 {
        return 0;
    }
    let mut v = x;
    let mut n: u16 = 1;
    if v >> 128 != 0u128 {
        v >>= 128;
        n += 128;
    }
    if v >> 64 != 0u128 {
        v >>= 64;
        n += 64;
    }
    if v >> 32 != 0u128 {
        v >>= 32;
        n += 32;
    }
    if v >> 16 != 0u128 {
        v >>= 16;
        n += 16;
    }
    if v >> 8 != 0u128 {
        v >>= 8;
        n += 8;
    }
    if v >> 4 != 0u128 {
        v >>= 4;
        n += 4;
    }
    if v >> 2 != 0u128 {
        v >>= 2;
        n += 2;
    }
    if v >> 1 != 0u128 {
        n += 1;
    }
    n
}

/// `floor(sqrt(x))`. Newton, seeded above the root so the sequence descends.
pub fn sqrt_u256(x: U256) -> U256 {
    if x == 0u128 {
        return U256::ZERO;
    }
    if x < 4u128 {
        return U256::ONE;
    }
    let shift = ((bit_length(x) + 1) / 2) as u32;
    let mut z = U256::ONE << shift;
    loop {
        let next = (z + x / z) >> 1;
        if next >= z {
            break;
        }
        z = next;
    }
    z
}

pub fn sqrt_u128(x: u128) -> u128 {
    sqrt_u256(u256(x)).as_u128()
}

/// `floor(sqrt(a * b))` without losing the intermediate to overflow.
pub fn sqrt_mul(a: u128, b: u128) -> Result<u128> {
    narrow_u128(sqrt_u256(full_mul(a, b)))
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

pub fn min_u64(a: u64, b: u64) -> u64 {
    if a < b { a } else { b }
}

pub fn abs_diff_u256(a: U256, b: U256) -> U256 {
    if a > b { a - b } else { b - a }
}

/// `ceil(n / d)` at u256 width, without the `n + d - 1` overflow trap.
pub fn ceil_div_u256(n: U256, d: U256) -> U256 {
    let q = n / d;
    if n % d == 0u128 { q } else { q + 1 }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MAX_U128: u128 = u128::MAX;

    #[test]
    fn rounding_modes_differ_on_a_remainder() {
        assert_eq!(mul_div_floor(10, 10, 3).unwrap(), 33);
        assert_eq!(mul_div_ceil(10, 10, 3).unwrap(), 34);
        assert_eq!(mul_div_round(10, 10, 3).unwrap(), 33);
        assert_eq!(mul_div_round(10, 10, 6).unwrap(), 17);
        assert_eq!(mul_div_round(1, 1, 2).unwrap(), 1);
    }

    #[test]
    fn mul_div_survives_a_u128_overflowing_intermediate() {
        assert_eq!(mul_div_floor(MAX_U128, MAX_U128, MAX_U128).unwrap(), MAX_U128);
        assert_eq!(mul_div_ceil(MAX_U128, MAX_U128, MAX_U128).unwrap(), MAX_U128);
    }

    #[test]
    fn errors_match_the_move_abort_codes() {
        assert_eq!(mul_div_floor(1, 1, 0), Err(MathError::DivideByZero));
        assert_eq!(MathError::DivideByZero.abort_code(), 0);
        assert_eq!(mul_div_floor(MAX_U128, MAX_U128, 1), Err(MathError::Overflow));
        assert_eq!(MathError::Overflow.abort_code(), 1);
    }

    #[test]
    fn bit_length_counts_significant_bits() {
        assert_eq!(bit_length(U256::ZERO), 0);
        assert_eq!(bit_length(U256::ONE), 1);
        assert_eq!(bit_length(U256::new(255)), 8);
        assert_eq!(bit_length(U256::new(256)), 9);
        assert_eq!(bit_length(U256::ONE << 200), 201);
    }

    #[test]
    fn sqrt_returns_the_floor() {
        for (x, want) in [(0u128, 0u128), (1, 1), (3, 1), (4, 2), (8, 2), (9, 3), (9999, 99), (10000, 100)] {
            assert_eq!(sqrt_u128(x), want, "sqrt({x})");
        }
    }

    #[test]
    fn sqrt_is_exact_at_the_top_of_the_range() {
        let n = full_mul(MAX_U128, MAX_U128);
        assert_eq!(sqrt_u256(n), U256::from(MAX_U128));
        assert_eq!(sqrt_u256(n - 1), U256::from(MAX_U128) - 1);
    }

    #[test]
    fn sqrt_never_overestimates() {
        let mut i: u128 = 1;
        while i < 100_000 {
            let z = sqrt_u128(i);
            assert!(z * z <= i);
            assert!((z + 1) * (z + 1) > i);
            i = i * 7 + 1;
        }
    }

    #[test]
    fn sqrt_mul_is_the_initial_lp_share_formula() {
        assert_eq!(sqrt_mul(1_000_000, 4_000_000).unwrap(), 2_000_000);
        assert_eq!(sqrt_mul(MAX_U128, MAX_U128).unwrap(), MAX_U128);
    }

    #[test]
    fn shifts_round_in_the_stated_direction() {
        assert_eq!(mul_shr(7, 1, 1).unwrap(), 3);
        assert_eq!(mul_shr_ceil(7, 1, 1).unwrap(), 4);
        assert_eq!(mul_shr(8, 1, 1).unwrap(), 4);
        assert_eq!(mul_shr_ceil(8, 1, 1).unwrap(), 4);
        assert_eq!(shl_div(3, 4, 1).unwrap(), 1);
        assert_eq!(shl_div_ceil(3, 4, 1).unwrap(), 2);
    }
}
