//! Rust mirror of `braid_clmm`: tick math, liquidity math, the swap step, the
//! tick bitmap, and the pool's swap loop.
//!
//! The loop is the part that makes this more than a formula. A swap is chopped
//! into steps at every boundary the bitmap search returns -- including the
//! *uninitialized* ones at the edge of each 256-bit word, where liquidity does
//! not change at all. Each step rounds on its own, so a replica that walked a
//! sorted list of initialized ticks instead would take fewer, longer steps and
//! disagree with the chain by a unit or two on any swap that spans a word. So
//! the bitmap is reproduced word for word.
//!
//! Same rule as the other modules: transliteration, not reimplementation.

use std::collections::BTreeMap;

use ethnum::U256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClmmError {
    /// `tick_math::EInvalidTick`.
    InvalidTick,
    /// `tick_math::EInvalidSqrtPrice`.
    InvalidSqrtPrice,
    /// `swap_math::EZeroLiquidity`.
    ZeroLiquidity,
    /// Any `EOverflow`, or an arithmetic abort Move raises without a name.
    Overflow,
    /// `swap_math::EPriceUnderflow`.
    PriceUnderflow,
    /// `swap_math::EInvalidFee` / `pool::EInvalidFee`.
    InvalidFee,
    /// `liquidity_math::EInvalidPriceRange`.
    InvalidPriceRange,
    /// `tick::ELiquidityOverflow`.
    LiquidityOverflow,
    /// `pool::EZeroAmount`.
    ZeroAmount,
    /// `pool::EInvalidRange`.
    InvalidRange,
    /// `pool::ETooManyCrossings`.
    TooManyCrossings,
    /// `pool::EInvalidPriceLimit`.
    InvalidPriceLimit,
}

pub type Result<T> = core::result::Result<T, ClmmError>;

// ---------------------------------------------------------------------------
// tick_math
// ---------------------------------------------------------------------------

pub const MAX_TICK: i32 = 689_382;
pub const MIN_TICK: i32 = -MAX_TICK;
pub const MIN_SQRT_PRICE: u128 = 19_812;
pub const MAX_SQRT_PRICE: u128 = 17_175_572_088_390_372_486_202_642_652_453_860;

/// `1.0001^(-2^i/2)` in Q128.128, emitted by scripts/gen_tick_math.py.
const C: [u128; 20] = [
    0xfffcb933bd6fad37aa2d162d1a594001,
    0xfff97272373d413259a46990580e2139,
    0xfff2e50f5f656932ef12357cf3c7fdcb,
    0xffe5caca7e10e4e61c3624eaa0941ccf,
    0xffcb9843d60f6159c9db58835c926643,
    0xff973b41fa98c081472e6896dfb254bf,
    0xff2ea16466c96a3843ec78b326b52860,
    0xfe5dee046a99a2a811c461f1969c3052,
    0xfcbe86c7900a88aedcffc83b479aa3a3,
    0xf987a7253ac413176f2b074cf7815e53,
    0xf3392b0822b70005940c7a398e4b70f2,
    0xe7159475a2c29b7443b29c7fa6e889d8,
    0xd097f3bdfd2022b8845ad8f792aa5825,
    0xa9f746462d870fdf8a65dc1f90e061e4,
    0x70d869a156d2a1b890bb3df62baf32f6,
    0x31be135f97d08fd981231505542fcfa5,
    0x09aa508b5b7a84e1c677de54f3e99bc8,
    0x005d6af8dedb81196699c329225ee604,
    0x00002216e584f5fa1ea926041bedfe97,
    0x00000000048a170391f7dc42444e8fa2,
];

const MAX_U64: u128 = u64::MAX as u128;

#[inline]
fn u(v: u128) -> U256 {
    U256::from(v)
}

pub fn sqrt_price_at_tick(tick: i32) -> Result<u128> {
    let abs_tick = tick.unsigned_abs();
    if abs_tick > MAX_TICK as u32 {
        return Err(ClmmError::InvalidTick);
    }
    let mut ratio = U256::from_words(1, 0);
    for (i, c) in C.iter().enumerate() {
        if abs_tick & (1 << i) != 0 {
            ratio = (ratio * u(*c)) >> 128;
        }
    }
    if tick >= 0 {
        ratio = U256::MAX / ratio;
    }
    let mut r: U256 = ratio >> 64u32;
    if ratio & u(MAX_U64) != 0u128 {
        r += 1u128;
    }
    Ok(r.as_u128())
}

pub fn tick_at_sqrt_price(sqrt_price: u128) -> Result<i32> {
    if !(MIN_SQRT_PRICE..=MAX_SQRT_PRICE).contains(&sqrt_price) {
        return Err(ClmmError::InvalidSqrtPrice);
    }
    let mut lo: u32 = 0;
    let mut hi: u32 = 2 * MAX_TICK as u32;
    while lo < hi {
        let mid = (lo + hi + 1) / 2;
        if sqrt_price_at_tick(tick_from_offset(mid))? <= sqrt_price {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    Ok(tick_from_offset(lo))
}

fn tick_from_offset(offset: u32) -> i32 {
    offset as i32 - MAX_TICK
}

// ---------------------------------------------------------------------------
// liquidity_math
// ---------------------------------------------------------------------------

fn ordered(a: u128, b: u128) -> Result<(U256, U256)> {
    if a == 0 || b == 0 {
        return Err(ClmmError::InvalidPriceRange);
    }
    Ok(if a <= b { (u(a), u(b)) } else { (u(b), u(a)) })
}

fn div_round(n: U256, d: U256, round_up: bool) -> U256 {
    let q = n / d;
    if round_up && n % d != 0u128 { q + 1u128 } else { q }
}

fn to_u64(v: U256) -> Result<u64> {
    if v > u(MAX_U64) { Err(ClmmError::Overflow) } else { Ok(v.as_u64()) }
}

fn to_u128(v: U256) -> Result<u128> {
    if v > u(u128::MAX) { Err(ClmmError::Overflow) } else { Ok(v.as_u128()) }
}

pub fn amount0_delta(sqrt_a: u128, sqrt_b: u128, liquidity: u128, round_up: bool) -> Result<u64> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    if liquidity == 0 || lo == hi {
        return Ok(0);
    }
    let prod = u(liquidity) * (hi - lo);
    // MAX_U192: the `<< 64` below must not discard bits.
    if prod > (U256::ONE << 192) - 1u128 {
        return Err(ClmmError::Overflow);
    }
    to_u64(div_round(prod << 64, lo * hi, round_up))
}

pub fn amount1_delta(sqrt_a: u128, sqrt_b: u128, liquidity: u128, round_up: bool) -> Result<u64> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    if liquidity == 0 || lo == hi {
        return Ok(0);
    }
    let prod = u(liquidity) * (hi - lo);
    to_u64(div_round(prod, U256::ONE << 64, round_up))
}

pub fn amounts_for_liquidity(
    sqrt_price: u128,
    sqrt_a: u128,
    sqrt_b: u128,
    liquidity: u128,
    round_up: bool,
) -> Result<(u64, u64)> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    let p = u(sqrt_price);
    if p <= lo {
        Ok((amount0_delta(sqrt_a, sqrt_b, liquidity, round_up)?, 0))
    } else if p >= hi {
        Ok((0, amount1_delta(sqrt_a, sqrt_b, liquidity, round_up)?))
    } else {
        Ok((
            amount0_delta(sqrt_price, hi.as_u128(), liquidity, round_up)?,
            amount1_delta(lo.as_u128(), sqrt_price, liquidity, round_up)?,
        ))
    }
}

pub fn liquidity_from_amount0(sqrt_a: u128, sqrt_b: u128, amount0: u64) -> Result<u128> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    if hi <= lo {
        return Err(ClmmError::InvalidPriceRange);
    }
    let intermediate = (lo * hi) >> 64;
    to_u128(U256::from(amount0) * intermediate / (hi - lo))
}

pub fn liquidity_from_amount1(sqrt_a: u128, sqrt_b: u128, amount1: u64) -> Result<u128> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    if hi <= lo {
        return Err(ClmmError::InvalidPriceRange);
    }
    to_u128((U256::from(amount1) << 64) / (hi - lo))
}

pub fn liquidity_for_amounts(
    sqrt_price: u128,
    sqrt_a: u128,
    sqrt_b: u128,
    amount0: u64,
    amount1: u64,
) -> Result<u128> {
    let (lo, hi) = ordered(sqrt_a, sqrt_b)?;
    let p = u(sqrt_price);
    if p <= lo {
        liquidity_from_amount0(sqrt_a, sqrt_b, amount0)
    } else if p >= hi {
        liquidity_from_amount1(sqrt_a, sqrt_b, amount1)
    } else {
        let from_0 = liquidity_from_amount0(sqrt_price, hi.as_u128(), amount0)?;
        let from_1 = liquidity_from_amount1(lo.as_u128(), sqrt_price, amount1)?;
        Ok(from_0.min(from_1))
    }
}

pub fn add_delta(liquidity: u128, delta: u128, is_add: bool) -> Result<u128> {
    if is_add {
        liquidity.checked_add(delta).ok_or(ClmmError::Overflow)
    } else if liquidity >= delta {
        Ok(liquidity - delta)
    } else {
        Err(ClmmError::Overflow)
    }
}

// ---------------------------------------------------------------------------
// swap_math
// ---------------------------------------------------------------------------

pub const BPS_DENOM: u64 = 10_000;
pub const MAX_FEE_BPS: u64 = 1_000;

fn ceil_div(n: U256, d: U256) -> U256 {
    let q = n / d;
    if n % d == 0u128 { q } else { q + 1u128 }
}

pub fn next_sqrt_price_from_amount0_in(sqrt_price: u128, liquidity: u128, amount: u64) -> Result<u128> {
    if liquidity == 0 {
        return Err(ClmmError::ZeroLiquidity);
    }
    if sqrt_price == 0 {
        return Err(ClmmError::PriceUnderflow);
    }
    if amount == 0 {
        return Ok(sqrt_price);
    }
    let num = u(liquidity) << 64;
    let denom = num / u(sqrt_price) + U256::from(amount);
    to_u128(ceil_div(num, denom))
}

pub fn next_sqrt_price_from_amount1_in(sqrt_price: u128, liquidity: u128, amount: u64) -> Result<u128> {
    if liquidity == 0 {
        return Err(ClmmError::ZeroLiquidity);
    }
    if amount == 0 {
        return Ok(sqrt_price);
    }
    let step = (U256::from(amount) << 64) / u(liquidity);
    to_u128(u(sqrt_price) + step)
}

pub fn next_sqrt_price_from_input(
    sqrt_price: u128,
    liquidity: u128,
    amount_in: u64,
    zero_for_one: bool,
) -> Result<u128> {
    if zero_for_one {
        next_sqrt_price_from_amount0_in(sqrt_price, liquidity, amount_in)
    } else {
        next_sqrt_price_from_amount1_in(sqrt_price, liquidity, amount_in)
    }
}

/// `(sqrt_next, amount_in, amount_out, fee_amount)`.
pub fn compute_swap_step(
    sqrt_current: u128,
    sqrt_target: u128,
    liquidity: u128,
    amount_remaining: u64,
    fee_bps: u64,
) -> Result<(u128, u64, u64, u64)> {
    if fee_bps > MAX_FEE_BPS {
        return Err(ClmmError::InvalidFee);
    }
    if liquidity == 0 {
        return Err(ClmmError::ZeroLiquidity);
    }
    let zero_for_one = sqrt_current >= sqrt_target;

    let fee_on_budget = ceil_div(
        U256::from(amount_remaining) * U256::from(fee_bps),
        U256::from(BPS_DENOM),
    );
    let remaining_less_fee = (U256::from(amount_remaining) - fee_on_budget).as_u64();

    let to_target = if zero_for_one {
        amount0_delta(sqrt_target, sqrt_current, liquidity, true)?
    } else {
        amount1_delta(sqrt_current, sqrt_target, liquidity, true)?
    };

    let sqrt_next = if remaining_less_fee >= to_target {
        sqrt_target
    } else {
        next_sqrt_price_from_input(sqrt_current, liquidity, remaining_less_fee, zero_for_one)?
    };
    let reached = sqrt_next == sqrt_target;

    let (amount_in, amount_out) = if zero_for_one {
        (
            if reached { to_target } else { amount0_delta(sqrt_next, sqrt_current, liquidity, true)? },
            amount1_delta(sqrt_next, sqrt_current, liquidity, false)?,
        )
    } else {
        (
            if reached { to_target } else { amount1_delta(sqrt_current, sqrt_next, liquidity, true)? },
            amount0_delta(sqrt_current, sqrt_next, liquidity, false)?,
        )
    };

    let fee_amount = if reached {
        ceil_div(
            U256::from(amount_in) * U256::from(fee_bps),
            U256::from(BPS_DENOM - fee_bps),
        )
        .as_u64()
    } else {
        amount_remaining - amount_in
    };

    Ok((sqrt_next, amount_in, amount_out, fee_amount))
}

// ---------------------------------------------------------------------------
// tick_bitmap
// ---------------------------------------------------------------------------

/// Floor division by the spacing. `div_euclid` is floor for a positive divisor.
pub fn compress(tick: i32, tick_spacing: u32) -> i32 {
    tick.div_euclid(tick_spacing as i32)
}

/// `(word_pos, bit_pos)`. `>>` on `i32` is arithmetic, as `i32::shr` is.
pub fn position(compressed: i32) -> (i32, u8) {
    (compressed >> 8, (compressed & 255) as u8)
}

fn scale(compressed: i32, tick_spacing: u32) -> Result<i32> {
    let v = compressed as i64 * tick_spacing as i64;
    if v.unsigned_abs() > i32::MAX as u64 {
        return Err(ClmmError::Overflow);
    }
    Ok(v as i32)
}

fn msb(x: U256) -> u8 {
    (255 - x.leading_zeros()) as u8
}

fn lsb(x: U256) -> u8 {
    x.trailing_zeros() as u8
}

pub fn next_initialized_tick_within_word(
    word: U256,
    tick: i32,
    tick_spacing: u32,
    lte: bool,
) -> Result<(i32, bool)> {
    let compressed = compress(tick, tick_spacing);
    if lte {
        let (_, bit_pos) = position(compressed);
        let mask = if bit_pos == 255 { U256::MAX } else { (U256::ONE << (bit_pos as u32 + 1)) - 1u128 };
        let masked = word & mask;
        if masked != 0u128 {
            let steps = bit_pos - msb(masked);
            Ok((scale(compressed - steps as i32, tick_spacing)?, true))
        } else {
            Ok((scale(compressed - bit_pos as i32, tick_spacing)?, false))
        }
    } else {
        let from = compressed + 1;
        let (_, bit_pos) = position(from);
        let mask = U256::MAX ^ ((U256::ONE << bit_pos as u32) - 1u128);
        let masked = word & mask;
        if masked != 0u128 {
            let steps = lsb(masked) - bit_pos;
            Ok((scale(from + steps as i32, tick_spacing)?, true))
        } else {
            Ok((scale(from + (255 - bit_pos) as i32, tick_spacing)?, false))
        }
    }
}

// ---------------------------------------------------------------------------
// The pool
// ---------------------------------------------------------------------------

pub const MAX_POOL_FEE_BPS: u64 = 1_000;
pub const MAX_CROSSINGS: u64 = 200;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TickState {
    pub liquidity_gross: u128,
    pub liquidity_net: i128,
}

/// The state a swap reads. Fee growth is left out: it never changes what a
/// swap pays, only what positions are later owed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pool {
    pub sqrt_price: u128,
    pub tick: i32,
    pub liquidity: u128,
    pub fee_bps: u64,
    pub tick_spacing: u32,
    pub ticks: BTreeMap<i32, TickState>,
    pub bitmap: BTreeMap<i32, U256>,
}

pub fn max_liquidity_per_tick(tick_spacing: u32) -> u128 {
    let usable = 2 * (MAX_TICK as u32 / tick_spacing) as u128 + 1;
    u128::MAX / usable
}

impl Pool {
    /// `pool::create_pool`.
    pub fn new(initial_sqrt_price: u128, fee_bps: u64, tick_spacing: u32) -> Result<Pool> {
        if fee_bps > MAX_POOL_FEE_BPS {
            return Err(ClmmError::InvalidFee);
        }
        if tick_spacing == 0 {
            return Err(ClmmError::InvalidRange);
        }
        Ok(Pool {
            sqrt_price: initial_sqrt_price,
            tick: tick_at_sqrt_price(initial_sqrt_price)?,
            liquidity: 0,
            fee_bps,
            tick_spacing,
            ticks: BTreeMap::new(),
            bitmap: BTreeMap::new(),
        })
    }

    /// Rebuild from an on-chain snapshot: the scalar fields plus every
    /// initialized tick. The bitmap is derived, since it is exactly the set of
    /// ticks with non-zero gross liquidity.
    pub fn from_snapshot(
        sqrt_price: u128,
        tick: i32,
        liquidity: u128,
        fee_bps: u64,
        tick_spacing: u32,
        ticks: impl IntoIterator<Item = (i32, TickState)>,
    ) -> Pool {
        let mut pool = Pool {
            sqrt_price,
            tick,
            liquidity,
            fee_bps,
            tick_spacing,
            ticks: BTreeMap::new(),
            bitmap: BTreeMap::new(),
        };
        for (t, state) in ticks {
            if state.liquidity_gross > 0 {
                pool.flip_tick_bit(t);
                pool.ticks.insert(t, state);
            }
        }
        pool
    }

    fn flip_tick_bit(&mut self, t: i32) {
        let (word_pos, bit_pos) = position(compress(t, self.tick_spacing));
        let word = self.bitmap.entry(word_pos).or_insert(U256::ZERO);
        *word ^= U256::ONE << bit_pos as u32;
    }

    fn next_tick(&self, from: i32, lte: bool) -> Result<(i32, bool)> {
        let compressed = compress(from, self.tick_spacing);
        let origin = if lte { compressed } else { compressed + 1 };
        let (word_pos, _) = position(origin);
        let word = self.bitmap.get(&word_pos).copied().unwrap_or(U256::ZERO);
        next_initialized_tick_within_word(word, from, self.tick_spacing, lte)
    }

    fn check_range(&self, lower: i32, upper: i32) -> Result<()> {
        if lower >= upper
            || lower.unsigned_abs() > MAX_TICK as u32
            || upper.unsigned_abs() > MAX_TICK as u32
            || lower.unsigned_abs() % self.tick_spacing != 0
            || upper.unsigned_abs() % self.tick_spacing != 0
        {
            return Err(ClmmError::InvalidRange);
        }
        Ok(())
    }

    fn update_tick(&mut self, t: i32, delta: u128, is_upper: bool) -> Result<()> {
        let max = max_liquidity_per_tick(self.tick_spacing);
        let state = self.ticks.get(&t).copied().unwrap_or_default();
        let gross_after = state.liquidity_gross.checked_add(delta).ok_or(ClmmError::LiquidityOverflow)?;
        if gross_after > max {
            return Err(ClmmError::LiquidityOverflow);
        }
        if delta > i128::MAX as u128 {
            return Err(ClmmError::Overflow);
        }
        let signed = if is_upper { -(delta as i128) } else { delta as i128 };
        let flipped = (gross_after == 0) != (state.liquidity_gross == 0);
        self.ticks.insert(
            t,
            TickState {
                liquidity_gross: gross_after,
                liquidity_net: state.liquidity_net.wrapping_add(signed),
            },
        );
        if flipped {
            self.flip_tick_bit(t);
        }
        Ok(())
    }

    /// `pool::add_liquidity`. Returns `(liquidity, amount0_taken, amount1_taken)`.
    pub fn add_liquidity(&mut self, lower: i32, upper: i32, amount0: u64, amount1: u64) -> Result<(u128, u64, u64)> {
        self.check_range(lower, upper)?;
        let sqrt_lower = sqrt_price_at_tick(lower)?;
        let sqrt_upper = sqrt_price_at_tick(upper)?;
        let liquidity = liquidity_for_amounts(self.sqrt_price, sqrt_lower, sqrt_upper, amount0, amount1)?;
        if liquidity == 0 {
            return Err(ClmmError::ZeroAmount);
        }

        // Validate both ticks before touching either, so a failed call leaves
        // the replica unchanged -- the chain gets that for free from the abort.
        let mut next = self.clone();
        next.update_tick(lower, liquidity, false)?;
        next.update_tick(upper, liquidity, true)?;
        let (need0, need1) = amounts_for_liquidity(next.sqrt_price, sqrt_lower, sqrt_upper, liquidity, true)?;
        if next.tick >= lower && next.tick < upper {
            next.liquidity = add_delta(next.liquidity, liquidity, true)?;
        }
        if need0 > amount0 || need1 > amount1 {
            return Err(ClmmError::Overflow);
        }
        *self = next;
        Ok((liquidity, need0, need1))
    }

    /// `pool::swap_a_for_b` / `swap_b_for_a`, without coins. Mutates the pool
    /// and returns `(input_spent, output)`.
    pub fn swap(&mut self, amount_in: u64, zero_for_one: bool, sqrt_price_limit: u128) -> Result<(u64, u64)> {
        if zero_for_one {
            if !(sqrt_price_limit < self.sqrt_price && sqrt_price_limit >= MIN_SQRT_PRICE) {
                return Err(ClmmError::InvalidPriceLimit);
            }
        } else if !(sqrt_price_limit > self.sqrt_price && sqrt_price_limit <= MAX_SQRT_PRICE) {
            return Err(ClmmError::InvalidPriceLimit);
        }
        if amount_in == 0 {
            return Err(ClmmError::ZeroAmount);
        }
        let mut next = self.clone();
        let (spent, out, _fee) = next.run_swap(amount_in, sqrt_price_limit, zero_for_one)?;
        *self = next;
        Ok((spent, out))
    }

    /// What `swap` would return, leaving the pool untouched. Uses the router's
    /// limit: the edge of the tick range.
    pub fn quote(&self, amount_in: u64, zero_for_one: bool) -> Result<(u64, u64)> {
        let limit = if zero_for_one { MIN_SQRT_PRICE } else { MAX_SQRT_PRICE };
        self.clone().swap(amount_in, zero_for_one, limit)
    }

    /// `pool::run_swap`. `(input_spent_including_fee, output, fee)`.
    fn run_swap(&mut self, amount_in: u64, limit: u128, zero_for_one: bool) -> Result<(u64, u64, u64)> {
        let mut remaining = amount_in;
        let mut total_out: u64 = 0;
        let mut total_fee: u64 = 0;
        let mut crossings: u64 = 0;

        while remaining > 0 && self.sqrt_price != limit {
            if crossings >= MAX_CROSSINGS {
                return Err(ClmmError::TooManyCrossings);
            }
            crossings += 1;

            if self.liquidity == 0 {
                break;
            }

            let (boundary, initialized) = self.next_tick(self.tick, zero_for_one)?;
            let clamped = boundary.clamp(MIN_TICK, MAX_TICK);
            let boundary_price = sqrt_price_at_tick(clamped)?;
            let target = if zero_for_one {
                if boundary_price < limit { limit } else { boundary_price }
            } else if boundary_price > limit {
                limit
            } else {
                boundary_price
            };

            let (next_price, step_in, step_out, step_fee) =
                compute_swap_step(self.sqrt_price, target, self.liquidity, remaining, self.fee_bps)?;

            remaining = remaining - step_in - step_fee;
            total_out = total_out.checked_add(step_out).ok_or(ClmmError::Overflow)?;
            total_fee = total_fee.checked_add(step_fee).ok_or(ClmmError::Overflow)?;

            self.sqrt_price = next_price;

            if next_price == boundary_price && initialized {
                let net = self.ticks.get(&clamped).copied().unwrap_or_default().liquidity_net;
                let applied = if zero_for_one { net.wrapping_neg() } else { net };
                self.liquidity = add_delta(self.liquidity, applied.unsigned_abs(), applied >= 0)?;
                self.tick = if zero_for_one { clamped - 1 } else { clamped };
            } else if next_price != boundary_price {
                self.tick = tick_at_sqrt_price(next_price)?;
            } else {
                self.tick = if zero_for_one { clamped - 1 } else { clamped };
            }
        }

        Ok((amount_in - remaining, total_out, total_fee))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const P0: u128 = 1 << 64;

    #[test]
    fn tick_math_matches_the_move_bounds() {
        assert_eq!(sqrt_price_at_tick(0).unwrap(), P0);
        assert_eq!(sqrt_price_at_tick(MIN_TICK).unwrap(), MIN_SQRT_PRICE);
        assert_eq!(sqrt_price_at_tick(MAX_TICK).unwrap(), MAX_SQRT_PRICE);
        assert_eq!(tick_at_sqrt_price(P0).unwrap(), 0);
        assert_eq!(tick_at_sqrt_price(MIN_SQRT_PRICE).unwrap(), MIN_TICK);
        assert_eq!(tick_at_sqrt_price(MAX_SQRT_PRICE).unwrap(), MAX_TICK);
        assert_eq!(sqrt_price_at_tick(MAX_TICK + 1), Err(ClmmError::InvalidTick));
    }

    #[test]
    fn ticks_round_trip_and_increase() {
        let mut prev = 0;
        for t in (-5000..5000).step_by(7) {
            let p = sqrt_price_at_tick(t).unwrap();
            assert!(p > prev);
            assert_eq!(tick_at_sqrt_price(p).unwrap(), t);
            prev = p;
        }
    }

    #[test]
    fn compress_floors_negative_ticks() {
        assert_eq!(compress(-5, 10), -1);
        assert_eq!(compress(-10, 10), -1);
        assert_eq!(compress(-11, 10), -2);
        assert_eq!(compress(5, 10), 0);
        assert_eq!(position(-1), (-1, 255));
    }

    /// The live testnet pool: 30 bps, spacing 60, one position -600..600 from
    /// 5,000,000 of each side. On chain the position held 169,187,499
    /// liquidity, and a 100,000 swap of token0 returned 99,641 at tick -12.
    #[test]
    fn reproduces_the_live_testnet_swap() {
        let mut pool = Pool::new(P0, 30, 60).unwrap();
        let (liquidity, _, _) = pool.add_liquidity(-600, 600, 5_000_000, 5_000_000).unwrap();
        assert_eq!(liquidity, 169_187_499);
        let (spent, out) = pool.swap(100_000, true, MIN_SQRT_PRICE).unwrap();
        assert_eq!((spent, out), (100_000, 99_641));
        assert_eq!(pool.tick, -12);
    }

    #[test]
    fn a_swap_past_the_last_range_returns_the_unspent_input() {
        let mut pool = Pool::new(P0, 30, 60).unwrap();
        pool.add_liquidity(-60, 60, 1_000, 1_000).unwrap();
        let (spent, out) = pool.quote(1_000_000, true).unwrap();
        assert!(spent < 1_000_000);
        assert!(out <= 1_000);
    }
}
