//! Rust mirror of `braid_stable::stable_math`.
//!
//! Includes the limit-cycle detector. A replica that converged where the chain
//! orbits -- or picked a different orbit member -- would disagree by a few units
//! on exactly the states that are hardest to reason about, so the ring buffer
//! and the take-the-maximum rule are reproduced exactly.

use crate::full_math as fm;
use ethnum::U256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StableError {
    /// `ENotConverged` -- 0.
    NotConverged,
    /// `EZeroAmount` -- 1.
    ZeroAmount,
    /// `EInvalidAmp` -- 2.
    InvalidAmp,
    /// `EInsufficientLiquidity` -- 3.
    InsufficientLiquidity,
    /// `EInvalidFee` -- 4.
    InvalidFee,
    /// `EOverflow` -- 5.
    Overflow,
}

impl StableError {
    pub fn abort_code(self) -> u64 {
        match self {
            StableError::NotConverged => 0,
            StableError::ZeroAmount => 1,
            StableError::InvalidAmp => 2,
            StableError::InsufficientLiquidity => 3,
            StableError::InvalidFee => 4,
            StableError::Overflow => 5,
        }
    }
}

pub type Result<T> = core::result::Result<T, StableError>;

const N_COINS: u128 = 2;
const A_PRECISION: u128 = 100;
pub const MIN_AMP: u64 = 100;
pub const MAX_AMP: u64 = 100_000_000;
const MAX_ITER: usize = 255;
/// Ring buffer depth for limit-cycle detection. See `resolve_cycle`.
const CYCLE_WINDOW: usize = 8;
const BPS_DENOM: u128 = 10_000;
pub const MAX_FEE_BPS: u64 = 100;
pub const MINIMUM_LIQUIDITY: u64 = 1_000;

const MAX_U64: u128 = u64::MAX as u128;

pub fn assert_valid_amp(amp: u64) -> Result<()> {
    if amp < MIN_AMP || amp > MAX_AMP {
        return Err(StableError::InvalidAmp);
    }
    Ok(())
}

#[inline]
fn u(v: u128) -> U256 {
    U256::from(v)
}

/// `D` and `y` are both bounded by the sum of two `u64` reserves.
fn narrow(v: U256) -> Result<u128> {
    if v > u(MAX_U64 * 2) {
        Err(StableError::Overflow)
    } else {
        Ok(v.as_u128())
    }
}

// ---------------------------------------------------------------------------
// Limit-cycle detection
// ---------------------------------------------------------------------------

/// If `next` repeats a value still in the window, the iterate has closed an
/// orbit. Returns the **maximum** over the orbit's members -- overstating the
/// invariant makes the pool pay out less, which is the safe direction.
///
/// The scan starts at the match rather than at the window's start, because
/// values seen *before* the orbit was entered are larger (the sequence descends
/// toward the root) and would overstate by far more than a few units.
fn resolve_cycle(history: &[U256], next: U256) -> Option<U256> {
    let mut found = false;
    let mut best = next;
    for &v in history {
        if v == next {
            found = true;
        }
        if found && v > best {
            best = v;
        }
    }
    if found { Some(best) } else { None }
}

fn push_bounded(history: &mut Vec<U256>, v: U256) {
    history.push(v);
    if history.len() > CYCLE_WINDOW {
        history.remove(0);
    }
}

// ---------------------------------------------------------------------------
// D -- the invariant
// ---------------------------------------------------------------------------

pub fn get_d(x0: u64, x1: u64, amp: u64) -> Result<u128> {
    assert_valid_amp(amp)?;

    let s = u(x0 as u128) + u(x1 as u128);
    if s == 0u128 {
        return Ok(0);
    }
    if x0 == 0 || x1 == 0 {
        return Err(StableError::InsufficientLiquidity);
    }

    let xp0 = u(x0 as u128);
    let xp1 = u(x1 as u128);
    let ann = u(amp as u128) * u(N_COINS);
    let n = u(N_COINS);
    let ap = u(A_PRECISION);

    let mut d = s;
    let mut history: Vec<U256> = Vec::with_capacity(CYCLE_WINDOW);

    for _ in 0..MAX_ITER {
        // D_P = D^3 / (4 x0 x1), one coin at a time so the floors land where
        // Curve's do. Reordering these two lines changes the result.
        let mut d_p = d;
        d_p = d_p * d / (xp0 * n);
        d_p = d_p * d / (xp1 * n);

        let d_prev = d;
        let next = (ann * s / ap + d_p * n) * d / ((ann - ap) * d / ap + (n + 1) * d_p);

        if fm::abs_diff_u256(next, d_prev) <= 1u128 {
            return narrow(next);
        }
        if let Some(resolved) = resolve_cycle(&history, next) {
            return narrow(resolved);
        }
        push_bounded(&mut history, next);
        d = next;
    }
    Err(StableError::NotConverged)
}

// ---------------------------------------------------------------------------
// y -- the post-trade balance
// ---------------------------------------------------------------------------

pub fn get_y(x_new: u128, d: u128, amp: u64) -> Result<u128> {
    assert_valid_amp(amp)?;
    if x_new == 0 {
        return Err(StableError::ZeroAmount);
    }
    if d == 0 {
        return Ok(0);
    }

    let x = u(x_new);
    let dd = u(d);
    let ann = u(amp as u128) * u(N_COINS);
    let n = u(N_COINS);
    let ap = u(A_PRECISION);

    let mut c = dd;
    c = c * dd / (x * n);
    c = c * dd * ap / (ann * n);
    let b = x + dd * ap / ann;

    let mut y = dd;
    let mut history: Vec<U256> = Vec::with_capacity(CYCLE_WINDOW);

    for _ in 0..MAX_ITER {
        let y_prev = y;
        let next = (y * y + c) / (n * y + b - dd);

        if fm::abs_diff_u256(next, y_prev) <= 1u128 {
            return narrow(next);
        }
        if let Some(resolved) = resolve_cycle(&history, next) {
            return narrow(resolved);
        }
        push_bounded(&mut history, next);
        y = next;
    }
    Err(StableError::NotConverged)
}

// ---------------------------------------------------------------------------
// Swaps
// ---------------------------------------------------------------------------

pub fn amount_out(
    dx: u64,
    reserve_in: u64,
    reserve_out: u64,
    amp: u64,
    fee_bps: u64,
) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(StableError::InvalidFee);
    }
    if dx == 0 {
        return Err(StableError::ZeroAmount);
    }
    if reserve_in == 0 || reserve_out == 0 {
        return Err(StableError::InsufficientLiquidity);
    }

    let d = get_d(reserve_in, reserve_out, amp)?;
    let x_new = reserve_in as u128 + dx as u128;
    let y = get_y(x_new, d, amp)?;

    if y >= reserve_out as u128 {
        return Err(StableError::InsufficientLiquidity);
    }
    let dy_gross = u(reserve_out as u128) - u(y) - 1u128;
    if dy_gross == 0u128 {
        return Ok(0);
    }

    let fee = fm::ceil_div_u256(dy_gross * u(fee_bps as u128), u(BPS_DENOM));
    let dy = dy_gross - fee;
    if dy > u(MAX_U64) {
        return Err(StableError::Overflow);
    }
    Ok(dy.as_u128() as u64)
}

pub fn fee_on_output(dy_gross: u64, fee_bps: u64) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(StableError::InvalidFee);
    }
    Ok(fm::ceil_div_u256(u(dy_gross as u128) * u(fee_bps as u128), u(BPS_DENOM)).as_u128() as u64)
}

pub fn amount_in(
    dy: u64,
    reserve_in: u64,
    reserve_out: u64,
    amp: u64,
    fee_bps: u64,
) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(StableError::InvalidFee);
    }
    if dy == 0 {
        return Err(StableError::ZeroAmount);
    }
    if reserve_in == 0 || reserve_out == 0 {
        return Err(StableError::InsufficientLiquidity);
    }

    let dy_gross = fm::ceil_div_u256(
        u(dy as u128) * u(BPS_DENOM),
        u(BPS_DENOM - fee_bps as u128),
    );
    if dy_gross + 1u128 >= u(reserve_out as u128) {
        return Err(StableError::InsufficientLiquidity);
    }

    let d = get_d(reserve_in, reserve_out, amp)?;
    let y_target = u(reserve_out as u128) - dy_gross - 1u128;
    let x_new = get_y(y_target.as_u128(), d, amp)?;

    if x_new <= reserve_in as u128 {
        return Err(StableError::InsufficientLiquidity);
    }
    let dx = x_new - reserve_in as u128 + 1;
    if dx > MAX_U64 {
        return Err(StableError::Overflow);
    }
    Ok(dx as u64)
}

// ---------------------------------------------------------------------------
// Liquidity
// ---------------------------------------------------------------------------

pub fn initial_lp(x0: u64, x1: u64, amp: u64) -> Result<u64> {
    let d = get_d(x0, x1, amp)?;
    if d == 0 {
        return Err(StableError::ZeroAmount);
    }
    if d > MAX_U64 {
        return Err(StableError::Overflow);
    }
    Ok(d as u64)
}

/// `n / (4(n-1))` at n = 2 -- half the swap fee, rounded up.
pub fn imbalance_fee_bps(fee_bps: u64) -> u64 {
    fm::ceil_div_u256(u(fee_bps as u128), u(2)).as_u128() as u64
}

/// Returns `(lp_minted, fee_0, fee_1)`.
pub fn lp_for_deposit(
    deposit_0: u64,
    deposit_1: u64,
    reserve_0: u64,
    reserve_1: u64,
    lp_supply: u64,
    amp: u64,
    fee_bps: u64,
) -> Result<(u64, u64, u64)> {
    if lp_supply == 0 {
        return Err(StableError::InsufficientLiquidity);
    }
    if deposit_0 == 0 && deposit_1 == 0 {
        return Err(StableError::ZeroAmount);
    }

    let d0 = u(get_d(reserve_0, reserve_1, amp)?);
    let new_0 = u(reserve_0 as u128) + u(deposit_0 as u128);
    let new_1 = u(reserve_1 as u128) + u(deposit_1 as u128);
    if new_0 > u(MAX_U64) || new_1 > u(MAX_U64) {
        return Err(StableError::Overflow);
    }
    let d1 = u(get_d(new_0.as_u128() as u64, new_1.as_u128() as u64, amp)?);
    if d1 <= d0 {
        return Err(StableError::ZeroAmount);
    }

    let imb = u(imbalance_fee_bps(fee_bps) as u128);

    let ideal_0 = d1 * u(reserve_0 as u128) / d0;
    let ideal_1 = d1 * u(reserve_1 as u128) / d0;
    let fee_0 = fm::ceil_div_u256(fm::abs_diff_u256(ideal_0, new_0) * imb, u(BPS_DENOM));
    let fee_1 = fm::ceil_div_u256(fm::abs_diff_u256(ideal_1, new_1) * imb, u(BPS_DENOM));

    let adj_0 = new_0 - fee_0;
    let adj_1 = new_1 - fee_1;
    let d2 = u(get_d(adj_0.as_u128() as u64, adj_1.as_u128() as u64, amp)?);

    let minted = u(lp_supply as u128) * (d2 - d0) / d0;
    if minted == 0u128 {
        return Err(StableError::ZeroAmount);
    }
    if minted > u(MAX_U64) {
        return Err(StableError::Overflow);
    }
    Ok((
        minted.as_u128() as u64,
        fee_0.as_u128() as u64,
        fee_1.as_u128() as u64,
    ))
}

pub fn withdraw_amounts(
    lp_amount: u64,
    reserve_0: u64,
    reserve_1: u64,
    lp_supply: u64,
) -> Result<(u64, u64)> {
    if lp_supply == 0 {
        return Err(StableError::InsufficientLiquidity);
    }
    if lp_amount == 0 {
        return Err(StableError::ZeroAmount);
    }
    if lp_amount > lp_supply {
        return Err(StableError::InsufficientLiquidity);
    }
    let lp = lp_amount as u128;
    let supply = lp_supply as u128;
    Ok((
        (lp * reserve_0 as u128 / supply) as u64,
        (lp * reserve_1 as u128 / supply) as u64,
    ))
}

/// `D / supply` as Q64.64 -- the LP share price.
pub fn virtual_price(reserve_0: u64, reserve_1: u64, lp_supply: u64, amp: u64) -> Result<u128> {
    if lp_supply == 0 {
        return Err(StableError::InsufficientLiquidity);
    }
    let d = u(get_d(reserve_0, reserve_1, amp)?);
    Ok(((d << 64u32) / u(lp_supply as u128)).as_u128())
}

#[cfg(test)]
mod tests {
    use super::*;

    const R: u64 = 1_000_000_000;
    const AMP: u64 = 10_000;
    const FEE: u64 = 4;
    const ONE_Q64: u128 = 1u128 << 64;

    #[test]
    fn d_matches_the_move_fixtures() {
        assert_eq!(get_d(R, R, AMP).unwrap(), 2_000_000_000);
        assert_eq!(get_d(R, R, 100).unwrap(), 2_000_000_000);
        assert_eq!(get_d(R, R, 100_000_000).unwrap(), 2_000_000_000);
        assert_eq!(get_d(R, R / 2, AMP).unwrap(), 1_499_073_492);
    }

    #[test]
    fn swaps_match_the_move_fixtures() {
        assert_eq!(amount_out(1_000_000, R, R, AMP, FEE).unwrap(), 999_590);
        assert_eq!(amount_out(10_000_000, R, R, AMP, FEE).unwrap(), 9_995_009);
        assert_eq!(amount_out(100_000_000, R, R, AMP, FEE).unwrap(), 99_860_149);
        assert_eq!(amount_in(999_590, R, R, AMP, FEE).unwrap(), 1_000_001);
    }

    #[test]
    fn amplification_matches_the_move_fixtures() {
        assert_eq!(amount_out(100_000_000, R, R, 1_000, FEE).unwrap(), 99_052_097);
        assert_eq!(amount_out(100_000_000, R, R, 10_000, FEE).unwrap(), 99_860_149);
        assert_eq!(amount_out(100_000_000, R, R, 100_000, FEE).unwrap(), 99_949_914);
    }

    /// The states where the reference implementation runs out of iterations.
    #[test]
    fn the_solver_resolves_limit_cycles() {
        assert_eq!(get_d(R, 1_000_000, 100).unwrap(), 193_404_748);
        assert_eq!(
            get_d(606_615_483_488_917, 302_485_337_224, 100).unwrap(),
            93_681_094_686_186
        );
        assert_eq!(get_d(R, 1, AMP).unwrap(), 9_254_663);
    }

    #[test]
    fn d_is_asymmetric_at_extreme_skew_exactly_as_the_chain_is() {
        assert_eq!(get_d(7, 999_999, AMP).unwrap(), 167_134);
        assert_eq!(get_d(999_999, 7, AMP).unwrap(), 167_136);
    }

    #[test]
    fn liquidity_matches_the_move_fixtures() {
        assert_eq!(initial_lp(R, R, AMP).unwrap(), 2_000_000_000);
        assert_eq!(
            lp_for_deposit(1_000_000, 1_000_000, R, R, 2 * R, AMP, FEE).unwrap(),
            (2_000_000, 0, 0)
        );
        assert_eq!(
            lp_for_deposit(2_000_000, 0, R, R, 2 * R, AMP, FEE).unwrap(),
            (1_999_589, 201, 200)
        );
        assert_eq!(imbalance_fee_bps(4), 2);
        assert_eq!(imbalance_fee_bps(5), 3);
    }

    #[test]
    fn virtual_price_starts_at_one_and_rises() {
        assert_eq!(virtual_price(R, R, 2 * R, AMP).unwrap(), ONE_Q64);
        let out = amount_out(10_000_000, R, R, AMP, FEE).unwrap();
        assert!(virtual_price(R + 10_000_000, R - out, 2 * R, AMP).unwrap() > ONE_Q64);
        assert_eq!(get_d(R + 10_000_000, R - out, AMP).unwrap(), 2_000_004_001);
    }

    #[test]
    fn the_invariant_never_falls_across_a_swap() {
        for dx in [1_000u64, 1_000_000, 100_000_000, 400_000_000] {
            let before = get_d(R, R, AMP).unwrap();
            let out = amount_out(dx, R, R, AMP, FEE).unwrap();
            assert!(get_d(R + dx, R - out, AMP).unwrap() > before, "dx={dx}");
        }
    }

    #[test]
    fn errors_match_the_move_abort_codes() {
        assert_eq!(get_d(R, R, MIN_AMP - 1), Err(StableError::InvalidAmp));
        assert_eq!(get_d(R, R, MAX_AMP + 1), Err(StableError::InvalidAmp));
        assert_eq!(amount_out(0, R, R, AMP, FEE), Err(StableError::ZeroAmount));
        assert_eq!(
            amount_out(1000, R, R, AMP, MAX_FEE_BPS + 1),
            Err(StableError::InvalidFee)
        );
        assert_eq!(
            amount_out(1000, 0, R, AMP, FEE),
            Err(StableError::InsufficientLiquidity)
        );
        assert_eq!(StableError::NotConverged.abort_code(), 0);
        assert_eq!(StableError::Overflow.abort_code(), 5);
    }
}
