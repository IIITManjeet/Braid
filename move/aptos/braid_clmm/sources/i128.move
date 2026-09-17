/// A signed 128-bit integer, for one job: a tick's net liquidity change.
///
/// Crossing a tick upward adds the liquidity of every position starting there
/// and removes the liquidity of every position ending there, so the net can go
/// either way and has to be signed. Liquidity itself is a `u128`, so the delta
/// needs the same width.
///
/// Two's complement in a `u128`, same construction as `i32`. Deliberately
/// smaller than that module -- ticks need ordering and shifting, net liquidity
/// only needs to be accumulated and applied, so nothing else is here.
module braid_clmm::i128 {

    /// Magnitude exceeds what a signed 128-bit value can hold.
    const EOverflow: u64 = 0;

    /// `1 << 127`.
    const SIGN_BIT: u128 = 170141183460469231731687303715884105728;
    /// `2^127 - 1`.
    const MAX_MAGNITUDE: u128 = 170141183460469231731687303715884105727;
    /// `2^128`, the modulus. A `u256` because it does not fit a `u128`.
    const WRAP: u256 = 340282366920938463463374607431768211456;

    public struct I128 has copy, drop, store {
        bits: u128,
    }

    public fun zero(): I128 { I128 { bits: 0 } }

    public fun from_u128(v: u128): I128 {
        assert!(v <= MAX_MAGNITUDE, EOverflow);
        I128 { bits: v }
    }

    public fun neg_from(v: u128): I128 {
        assert!(v <= MAX_MAGNITUDE, EOverflow);
        if (v == 0) { I128 { bits: 0 } } else { I128 { bits: ((WRAP - (v as u256)) as u128) } }
    }

    public fun is_neg(x: I128): bool { x.bits >= SIGN_BIT }

    public fun is_zero(x: I128): bool { x.bits == 0 }

    public fun abs_u128(x: I128): u128 {
        if (is_neg(x)) { ((WRAP - (x.bits as u256)) as u128) } else { x.bits }
    }

    public fun neg(x: I128): I128 {
        if (x.bits == 0) { x } else { I128 { bits: ((WRAP - (x.bits as u256)) as u128) } }
    }

    /// Wrapping addition, done one width up because Move aborts on `u128`
    /// overflow and two's complement depends on that wrap.
    public fun add(a: I128, b: I128): I128 {
        I128 { bits: ((((a.bits as u256) + (b.bits as u256)) % WRAP) as u128) }
    }

    public fun sub(a: I128, b: I128): I128 { add(a, neg(b)) }

    public fun eq(a: I128, b: I128): bool { a.bits == b.bits }

    /// Build from a magnitude and a direction, the shape callers actually have.
    public fun from_delta(magnitude: u128, is_add: bool): I128 {
        if (is_add) { from_u128(magnitude) } else { neg_from(magnitude) }
    }

    /// Split back into `(magnitude, is_positive)`.
    public fun to_delta(x: I128): (u128, bool) {
        (abs_u128(x), !is_neg(x))
    }

    public fun bits(x: I128): u128 { x.bits }

    public fun max_magnitude(): u128 { MAX_MAGNITUDE }
}
