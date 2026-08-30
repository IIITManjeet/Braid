/// Constant-product pricing, as pure functions over amounts and reserves.
///
/// Nothing here touches an object or a `TxContext`. That is deliberate: this
/// module is the specification the Rust quote engine has to reproduce
/// bit-for-bit, and keeping it free of Sui types means the differential fuzzer
/// can reach every function through `sui client dev-inspect` without first
/// constructing a pool.
///
/// # The invariant
///
/// A pool holds reserves `x` and `y` and promises that `x * y` never decreases.
/// A swap that puts `dx` in and takes `dy` out must satisfy
/// `(x + dx)(y - dy) >= x * y`, which rearranges to
/// `dy <= dx * y / (x + dx)`. Taking that at equality and then rounding *down*
/// is `amount_out`.
///
/// # Fees
///
/// The fee is charged on the input, before the swap math sees it, and is
/// retained by the pool. So the fee both leaves the trader with less to swap
/// *and* stays in the reserve -- which is what makes `k` strictly increase on a
/// fee-bearing swap, and is why the LP share appreciates.
///
/// # Rounding
///
/// Per `braid_math::full_math`, every rounding decision goes the pool's way:
/// the fee rounds up, the output rounds down, the required input rounds up, LP
/// minted rounds down, LP burned pays out rounded down. The trader is never
/// handed a unit that came from a truncation.
module braid_cpmm::cpmm_math {
    use braid_math::full_math;

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// An amount that must be positive was zero.
    const EZeroAmount: u64 = 0;
    /// Reserves are empty, or the trade asks for more than the pool holds.
    const EInsufficientLiquidity: u64 = 1;
    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 2;
    /// A `u128` intermediate did not fit back into a `u64` amount.
    const EOverflow: u64 = 3;
    /// Deposit would mint no LP at all.
    const EZeroLiquidityMinted: u64 = 4;

    // ------------------------------------------------------------------ //
    // Constants                                                          //
    // ------------------------------------------------------------------ //

    /// Fees are quoted in basis points: 30 bps = 0.30%.
    const BPS_DENOM: u64 = 10000;
    /// 10% -- far above anything sane, but a pool is not allowed past it.
    const MAX_FEE_BPS: u64 = 1000;
    /// LP burned on first deposit and never recoverable.
    ///
    /// Without it, an attacker empties the pool down to 1 LP unit, donates a
    /// large amount directly to the reserves, and every later depositor rounds
    /// to zero LP. Locking a floor of shares makes that donation cost more than
    /// it can extract.
    const MINIMUM_LIQUIDITY: u64 = 1000;

    const MAX_U64: u256 = 18446744073709551615;

    public fun bps_denom(): u64 { BPS_DENOM }

    public fun max_fee_bps(): u64 { MAX_FEE_BPS }

    public fun minimum_liquidity(): u64 { MINIMUM_LIQUIDITY }

    // ------------------------------------------------------------------ //
    // Fees                                                               //
    // ------------------------------------------------------------------ //

    /// `ceil(amount_in * fee_bps / 10000)`.
    ///
    /// Rounded up, so a dust trade pays 1 unit rather than 0. That closes the
    /// obvious grind: splitting one trade into many sub-unit-fee trades.
    public fun fee_amount(amount_in: u64, fee_bps: u64): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        full_math::mul_div_ceil_u64(amount_in, fee_bps, BPS_DENOM)
    }

    // ------------------------------------------------------------------ //
    // Exact-in                                                           //
    // ------------------------------------------------------------------ //

    /// How much comes out for a given input. Rounded down.
    ///
    /// The result is always strictly below `reserve_out`: the quotient
    /// `net * reserve_out / (reserve_in + net)` has a denominator strictly
    /// larger than its numerator's `net` factor, so a constant-product pool
    /// cannot be drained by any finite input.
    public fun amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u64,
    ): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(amount_in > 0, EZeroAmount);
        assert!(reserve_in > 0 && reserve_out > 0, EInsufficientLiquidity);

        let net = ((amount_in - fee_amount(amount_in, fee_bps)) as u128);
        // A fee of 100% of a 1-unit trade leaves nothing to swap.
        if (net == 0) return 0;

        // Fits a u64 by construction: the quotient is strictly below
        // `reserve_out`, which is itself a u64.
        let out = full_math::mul_div_floor(
            net,
            (reserve_out as u128),
            (reserve_in as u128) + net,
        );
        (out as u64)
    }

    /// The input needed to receive exactly `amount_out`. Rounded up, twice:
    /// once on the swap math and once again when grossing up for the fee.
    ///
    /// `amount_in(amount_out(a)) <= a` and `amount_out(amount_in(b)) >= b` --
    /// the pair is a conservative inverse, never a lossy one.
    public fun amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u64,
    ): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(amount_out > 0, EZeroAmount);
        assert!(reserve_in > 0 && reserve_out > 0, EInsufficientLiquidity);
        // Draining the pool exactly would need infinite input.
        assert!(amount_out < reserve_out, EInsufficientLiquidity);

        let net = full_math::mul_div_ceil(
            (amount_out as u128),
            (reserve_in as u128),
            ((reserve_out - amount_out) as u128),
        );
        // Gross up so that after the fee is taken, `net` still remains.
        let gross = full_math::mul_div_ceil(
            net,
            (BPS_DENOM as u128),
            ((BPS_DENOM - fee_bps) as u128),
        );
        assert!((gross as u256) <= MAX_U64, EOverflow);
        (gross as u64)
    }

    // ------------------------------------------------------------------ //
    // The invariant itself                                               //
    // ------------------------------------------------------------------ //

    /// `x * y` at `u256` width, so it never wraps.
    ///
    /// The pool asserts this is non-decreasing across every state change that
    /// is not a liquidity event. It is the last line of defence: if the pricing
    /// math above is ever wrong in the trader's favour, this catches it before
    /// the transaction commits.
    public fun k(reserve_a: u64, reserve_b: u64): u256 {
        full_math::full_mul((reserve_a as u128), (reserve_b as u128))
    }

    // ------------------------------------------------------------------ //
    // Liquidity                                                          //
    // ------------------------------------------------------------------ //

    /// LP minted for the very first deposit: `sqrt(a * b)`, of which
    /// `MINIMUM_LIQUIDITY` is locked and the remainder goes to the depositor.
    ///
    /// The geometric mean is the natural choice because it is the only
    /// homogeneous-degree-1 function of the two reserves, i.e. doubling both
    /// reserves doubles the shares -- which is what makes a share's value
    /// independent of the price the pool was seeded at.
    public fun initial_lp(amount_a: u64, amount_b: u64): u64 {
        // `sqrt(a * b) <= max(a, b)`, so a u64 always holds the result.
        let total = full_math::sqrt_mul((amount_a as u128), (amount_b as u128));
        assert!(total > (MINIMUM_LIQUIDITY as u128), EInsufficientLiquidity);
        ((total as u64) - MINIMUM_LIQUIDITY)
    }

    /// LP minted for a deposit into a pool that already has liquidity.
    ///
    /// `min` of the two ratios, so depositing off-ratio mints against the
    /// scarcer side and the surplus is a donation to existing LPs. Rounded
    /// down on both sides.
    public fun lp_for_deposit(
        amount_a: u64,
        amount_b: u64,
        reserve_a: u64,
        reserve_b: u64,
        lp_supply: u64,
    ): u64 {
        assert!(reserve_a > 0 && reserve_b > 0 && lp_supply > 0, EInsufficientLiquidity);
        let from_a = full_math::mul_div_floor_u64(amount_a, lp_supply, reserve_a);
        let from_b = full_math::mul_div_floor_u64(amount_b, lp_supply, reserve_b);
        let minted = full_math::min_u64(from_a, from_b);
        assert!(minted > 0, EZeroLiquidityMinted);
        minted
    }

    /// The deposit pair that matches the current reserve ratio, given what the
    /// depositor is willing to put up on each side.
    ///
    /// Takes `amount_a_desired` in full if the matching `b` is affordable;
    /// otherwise pivots and takes `amount_b_desired` in full. The matching
    /// side rounds *up*, so the pool is never short-changed on ratio.
    public fun optimal_deposit(
        amount_a_desired: u64,
        amount_b_desired: u64,
        reserve_a: u64,
        reserve_b: u64,
    ): (u64, u64) {
        assert!(reserve_a > 0 && reserve_b > 0, EInsufficientLiquidity);
        let b_needed = full_math::mul_div_ceil_u64(amount_a_desired, reserve_b, reserve_a);
        if (b_needed <= amount_b_desired) {
            (amount_a_desired, b_needed)
        } else {
            let a_needed = full_math::mul_div_ceil_u64(amount_b_desired, reserve_a, reserve_b);
            (a_needed, amount_b_desired)
        }
    }

    /// What burning `lp_amount` pays out. Both sides rounded down, so burning
    /// and immediately re-depositing is never profitable.
    public fun withdraw_amounts(
        lp_amount: u64,
        reserve_a: u64,
        reserve_b: u64,
        lp_supply: u64,
    ): (u64, u64) {
        assert!(lp_supply > 0, EInsufficientLiquidity);
        assert!(lp_amount > 0, EZeroAmount);
        assert!(lp_amount <= lp_supply, EInsufficientLiquidity);
        (
            full_math::mul_div_floor_u64(lp_amount, reserve_a, lp_supply),
            full_math::mul_div_floor_u64(lp_amount, reserve_b, lp_supply),
        )
    }

    // ------------------------------------------------------------------ //
    // Quoting                                                            //
    // ------------------------------------------------------------------ //

    /// Spot price of `a` in units of `b`, as Q64.64, ignoring fees and depth.
    ///
    /// Only meaningful for display and for the router's marginal-price
    /// comparison at the start of its search. Never use it to price a fill.
    public fun spot_price(reserve_a: u64, reserve_b: u64): u128 {
        assert!(reserve_a > 0, EInsufficientLiquidity);
        full_math::shl_div((reserve_b as u128), (reserve_a as u128), 64)
    }
}
