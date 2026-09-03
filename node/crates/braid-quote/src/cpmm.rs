//! Rust mirror of `braid_cpmm::cpmm_math`.
//!
//! Same rule as `full_math`: transliteration, not reimplementation. Rounding
//! direction and operation order are part of the specification.

use crate::full_math as fm;

/// Mirrors the abort codes in the Move module.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CpmmError {
    /// `EZeroAmount` — 0.
    ZeroAmount,
    /// `EInsufficientLiquidity` — 1.
    InsufficientLiquidity,
    /// `EInvalidFee` — 2.
    InvalidFee,
    /// `EOverflow` — 3.
    Overflow,
    /// `EZeroLiquidityMinted` — 4.
    ZeroLiquidityMinted,
    /// An abort raised inside `full_math` rather than here. Carries the inner
    /// error, because the Move abort would name `braid_math::full_math`.
    Math(fm::MathError),
}

impl From<fm::MathError> for CpmmError {
    fn from(e: fm::MathError) -> Self {
        CpmmError::Math(e)
    }
}

impl CpmmError {
    pub fn abort_code(self) -> u64 {
        match self {
            CpmmError::ZeroAmount => 0,
            CpmmError::InsufficientLiquidity => 1,
            CpmmError::InvalidFee => 2,
            CpmmError::Overflow => 3,
            CpmmError::ZeroLiquidityMinted => 4,
            CpmmError::Math(e) => e.abort_code(),
        }
    }
}

pub type Result<T> = core::result::Result<T, CpmmError>;

pub const BPS_DENOM: u64 = 10_000;
pub const MAX_FEE_BPS: u64 = 1_000;
pub const MINIMUM_LIQUIDITY: u64 = 1_000;

const MAX_U64: u128 = u64::MAX as u128;

// ---------------------------------------------------------------------------
// Fees
// ---------------------------------------------------------------------------

/// `ceil(amount_in * fee_bps / 10000)` — rounded up, so dust still pays.
pub fn fee_amount(amount_in: u64, fee_bps: u64) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(CpmmError::InvalidFee);
    }
    Ok(fm::mul_div_ceil_u64(amount_in, fee_bps, BPS_DENOM)?)
}

// ---------------------------------------------------------------------------
// Exact-in / exact-out
// ---------------------------------------------------------------------------

pub fn amount_out(amount_in: u64, reserve_in: u64, reserve_out: u64, fee_bps: u64) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(CpmmError::InvalidFee);
    }
    if amount_in == 0 {
        return Err(CpmmError::ZeroAmount);
    }
    if reserve_in == 0 || reserve_out == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }

    let net = (amount_in - fee_amount(amount_in, fee_bps)?) as u128;
    if net == 0 {
        return Ok(0);
    }

    // Fits a u64 by construction: strictly below `reserve_out`.
    let out = fm::mul_div_floor(net, reserve_out as u128, reserve_in as u128 + net)?;
    Ok(out as u64)
}

pub fn amount_in(amount_out: u64, reserve_in: u64, reserve_out: u64, fee_bps: u64) -> Result<u64> {
    if fee_bps > MAX_FEE_BPS {
        return Err(CpmmError::InvalidFee);
    }
    if amount_out == 0 {
        return Err(CpmmError::ZeroAmount);
    }
    if reserve_in == 0 || reserve_out == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    if amount_out >= reserve_out {
        return Err(CpmmError::InsufficientLiquidity);
    }

    let net = fm::mul_div_ceil(
        amount_out as u128,
        reserve_in as u128,
        (reserve_out - amount_out) as u128,
    )?;
    let gross = fm::mul_div_ceil(net, BPS_DENOM as u128, (BPS_DENOM - fee_bps) as u128)?;
    if gross > MAX_U64 {
        return Err(CpmmError::Overflow);
    }
    Ok(gross as u64)
}

/// `x * y` at 256-bit width, so it never wraps.
pub fn k(reserve_a: u64, reserve_b: u64) -> ethnum::U256 {
    fm::full_mul(reserve_a as u128, reserve_b as u128)
}

// ---------------------------------------------------------------------------
// Liquidity
// ---------------------------------------------------------------------------

pub fn initial_lp(amount_a: u64, amount_b: u64) -> Result<u64> {
    let total = fm::sqrt_mul(amount_a as u128, amount_b as u128)?;
    if total <= MINIMUM_LIQUIDITY as u128 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    Ok(total as u64 - MINIMUM_LIQUIDITY)
}

pub fn lp_for_deposit(
    amount_a: u64,
    amount_b: u64,
    reserve_a: u64,
    reserve_b: u64,
    lp_supply: u64,
) -> Result<u64> {
    if reserve_a == 0 || reserve_b == 0 || lp_supply == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    let from_a = fm::mul_div_floor_u64(amount_a, lp_supply, reserve_a)?;
    let from_b = fm::mul_div_floor_u64(amount_b, lp_supply, reserve_b)?;
    let minted = fm::min_u64(from_a, from_b);
    if minted == 0 {
        return Err(CpmmError::ZeroLiquidityMinted);
    }
    Ok(minted)
}

pub fn optimal_deposit(
    amount_a_desired: u64,
    amount_b_desired: u64,
    reserve_a: u64,
    reserve_b: u64,
) -> Result<(u64, u64)> {
    if reserve_a == 0 || reserve_b == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    let b_needed = fm::mul_div_ceil_u64(amount_a_desired, reserve_b, reserve_a)?;
    if b_needed <= amount_b_desired {
        Ok((amount_a_desired, b_needed))
    } else {
        let a_needed = fm::mul_div_ceil_u64(amount_b_desired, reserve_a, reserve_b)?;
        Ok((a_needed, amount_b_desired))
    }
}

pub fn withdraw_amounts(
    lp_amount: u64,
    reserve_a: u64,
    reserve_b: u64,
    lp_supply: u64,
) -> Result<(u64, u64)> {
    if lp_supply == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    if lp_amount == 0 {
        return Err(CpmmError::ZeroAmount);
    }
    if lp_amount > lp_supply {
        return Err(CpmmError::InsufficientLiquidity);
    }
    Ok((
        fm::mul_div_floor_u64(lp_amount, reserve_a, lp_supply)?,
        fm::mul_div_floor_u64(lp_amount, reserve_b, lp_supply)?,
    ))
}

/// Spot price of `a` in units of `b`, as Q64.64. Display only, never a fill.
pub fn spot_price(reserve_a: u64, reserve_b: u64) -> Result<u128> {
    if reserve_a == 0 {
        return Err(CpmmError::InsufficientLiquidity);
    }
    Ok(fm::shl_div(reserve_b as u128, reserve_a as u128, 64)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    const R: u64 = 1_000_000;
    const FEE: u64 = 30;

    #[test]
    fn matches_the_move_fixtures() {
        // The exact values asserted in cpmm_math_tests.move.
        assert_eq!(amount_out(1000, R, R, FEE).unwrap(), 996);
        assert_eq!(amount_out(1000, R, R, 0).unwrap(), 999);
        assert_eq!(amount_in(996, R, R, FEE).unwrap(), 1000);
        assert_eq!(fee_amount(1000, FEE).unwrap(), 3);
        assert_eq!(fee_amount(1, FEE).unwrap(), 1);
        assert_eq!(fee_amount(333, FEE).unwrap(), 1);
    }

    #[test]
    fn a_trade_too_small_to_survive_the_fee_returns_nothing() {
        assert_eq!(amount_out(1, R, R, MAX_FEE_BPS).unwrap(), 0);
    }

    #[test]
    fn the_two_directions_are_a_conservative_inverse() {
        let mut amount = 1u64;
        while amount < 100_000 {
            let out = amount_out(amount, R, R, FEE).unwrap();
            if out > 0 {
                let back = amount_in(out, R, R, FEE).unwrap();
                assert!(back <= amount, "in({out}) = {back} > {amount}");
                assert!(amount_out(back, R, R, FEE).unwrap() >= out);
            }
            amount = amount * 3 + 1;
        }
    }

    #[test]
    fn k_never_decreases_across_a_swap() {
        let mut amount = 1u64;
        while amount < 500_000 {
            let out = amount_out(amount, R, R, FEE).unwrap();
            assert!(k(R + amount, R - out) >= k(R, R));
            amount = amount * 7 + 1;
        }
    }

    #[test]
    fn liquidity_matches_the_move_fixtures() {
        assert_eq!(initial_lp(R, R).unwrap(), R - MINIMUM_LIQUIDITY);
        assert_eq!(initial_lp(R, 4 * R).unwrap(), 2 * R - MINIMUM_LIQUIDITY);
        assert_eq!(lp_for_deposit(1000, 1000, R, R, R).unwrap(), 1000);
        assert_eq!(lp_for_deposit(1000, 5000, R, R, R).unwrap(), 1000);
        assert_eq!(optimal_deposit(1000, 5000, R, 2 * R).unwrap(), (1000, 2000));
        assert_eq!(optimal_deposit(5000, 2000, R, 2 * R).unwrap(), (1000, 2000));
        assert_eq!(withdraw_amounts(1000, R, 2 * R, R).unwrap(), (1000, 2000));
    }

    #[test]
    fn errors_match_the_move_abort_codes() {
        assert_eq!(amount_out(0, R, R, FEE), Err(CpmmError::ZeroAmount));
        assert_eq!(amount_out(1000, 0, R, FEE), Err(CpmmError::InsufficientLiquidity));
        assert_eq!(fee_amount(1000, MAX_FEE_BPS + 1), Err(CpmmError::InvalidFee));
        assert_eq!(amount_in(R, R, R, FEE), Err(CpmmError::InsufficientLiquidity));
        assert_eq!(
            initial_lp(MINIMUM_LIQUIDITY, MINIMUM_LIQUIDITY),
            Err(CpmmError::InsufficientLiquidity)
        );
        assert_eq!(CpmmError::ZeroAmount.abort_code(), 0);
        assert_eq!(CpmmError::ZeroLiquidityMinted.abort_code(), 4);
    }

    #[test]
    fn spot_price_is_q64_64() {
        assert_eq!(spot_price(R, 2 * R).unwrap(), 2u128 << 64);
        assert_eq!(spot_price(R, R).unwrap(), 1u128 << 64);
        assert_eq!(spot_price(2 * R, R).unwrap(), 1u128 << 63);
    }
}
