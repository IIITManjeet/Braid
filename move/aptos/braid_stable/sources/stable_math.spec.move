/// Machine-checked specifications for `stable_math`.
///
/// This module is where the prover stops being able to say much, and the
/// boundary is worth being explicit about rather than quietly specifying the
/// easy half.
///
/// `get_d` and `get_y` solve the Curve invariant by Newton-Raphson. Proving
/// anything about their *results* means supplying a loop invariant strong
/// enough to characterise the fixed point of an iteration that is not even
/// guaranteed to converge -- see `docs/stableswap-limit-cycles.md` for the
/// states where it orbits instead. That is a research exercise, not a
/// specification exercise, and pretending otherwise by writing a weak
/// postcondition that happens to discharge would be worse than saying so.
///
/// What is stated here is the part that is genuinely checkable: the
/// parameter guards and the fee, which is where the rounding decision lives
/// and where a mistake silently costs the pool money on every trade.
/// The solvers' behaviour is covered instead by the differential fuzzer --
/// 1,087 generated cases against both Move VMs -- and by a third
/// implementation in Python written from Curve's published reference rather
/// than from this code.
///
///     aptos move prove --dev -f stable_math
spec braid_stable::stable_math {

    spec assert_valid_amp {
        aborts_if amp < MIN_AMP;
        aborts_if amp > MAX_AMP;
    }

    /// Rounded up, so a dust trade still pays a fee rather than rounding to
    /// nothing. The cap is 1% here, an order of magnitude below the CPMM's,
    /// because a stable pair trading near parity cannot absorb more.
    spec fee_on_output {
        aborts_if fee_bps > MAX_FEE_BPS;
        ensures result == (dy_gross * fee_bps + BPS_DENOM - 1) / BPS_DENOM;
        // Never rounds down: the pool is never short-changed.
        ensures result * BPS_DENOM >= dy_gross * fee_bps;
        // And never eats the whole output, because the cap is far below 100%.
        ensures result <= dy_gross;
    }

    spec min_amp {
        aborts_if false;
        ensures result == MIN_AMP;
    }

    spec max_amp {
        aborts_if false;
        ensures result == MAX_AMP;
        ensures result > MIN_AMP;
    }

    spec max_fee_bps {
        aborts_if false;
        ensures result == MAX_FEE_BPS;
        // What makes `fee_on_output`'s `result <= dy_gross` hold.
        ensures result < BPS_DENOM;
    }

    spec minimum_liquidity {
        aborts_if false;
        ensures result == MINIMUM_LIQUIDITY;
    }

    spec a_precision {
        aborts_if false;
        ensures result == A_PRECISION;
    }

    // `get_d`, `get_y`, `amount_out`, `amount_in` and the liquidity functions
    // all run or depend on the solver, and are left to the fuzzer. Turning
    // `pragma verify = false` on them is not needed -- an unspecified public
    // function is only checked against the implicit arithmetic-abort
    // conditions, which is the right amount of attention for code whose real
    // contract is "it agrees with Curve".
}
