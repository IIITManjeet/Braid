/// Machine-checked specifications for `cpmm_math`.
///
/// In its own file because `cpmm_math.move` is byte-identical to its
/// `move/sui` twin, and that property is worth more than the convenience of
/// putting specs inline. `diff` between the two must stay empty.
///
/// The interesting one is `amount_out`. The module's doc comment claims two
/// things in prose -- that `k` never decreases, and that no finite input can
/// drain the pool -- and the fuzzer checks them on 742 generated cases. These
/// specs make the same claims about *every* input a `u64` can hold. Run with:
///
///     aptos move prove --dev
///
/// Spec arithmetic is arbitrary precision, so the products below are the real
/// ones. That matters: the implementation reaches its answer through widened
/// `u256` intermediates narrowed back to `u64`, and these say the round trip
/// agrees with mathematics that never overflows in the first place.
spec braid_cpmm::cpmm_math {

    /// Rounded up, so a dust trade pays one unit rather than nothing. The
    /// grind this closes is splitting one trade into many sub-unit-fee ones.
    spec fee_amount {
        aborts_if fee_bps > MAX_FEE_BPS;
        aborts_if (amount_in * fee_bps + BPS_DENOM - 1) / BPS_DENOM > MAX_U64;
        ensures result == (amount_in * fee_bps + BPS_DENOM - 1) / BPS_DENOM;
        // Never rounds down, so the pool is never short-changed.
        ensures result * BPS_DENOM >= amount_in * fee_bps;
        // The fee cap is 10%, so a fee can never eat the trade it is charged on.
        ensures result <= amount_in;
    }

    /// The two claims the module doc makes in prose, checked for every input.
    spec amount_out {
        pragma aborts_if_is_partial = true;

        aborts_if fee_bps > MAX_FEE_BPS;
        aborts_if amount_in == 0;
        aborts_if reserve_in == 0;
        aborts_if reserve_out == 0;

        /// **The pool cannot be drained.** The quotient's denominator is
        /// strictly larger than its numerator's `net` factor, so no finite
        /// input takes the whole of `reserve_out` -- and the result therefore
        /// always fits the `u64` it is cast back into.
        ensures result < reserve_out;

        /// **`k` never decreases.** A swap moves the reserves to
        /// `(reserve_in + amount_in, reserve_out - result)`, and the product of
        /// those is at least the product before. Output is floored and the fee
        /// stays in the pool, so in practice it strictly grows -- that growth
        /// is the LP's return.
        ensures (reserve_in + amount_in) * (reserve_out - result)
                >= reserve_in * reserve_out;
    }

    /// Widened to `u256` so the invariant itself can never be the thing that
    /// wraps. It is the last line of defence, checked by the pool on every
    /// state change that is not a liquidity event.
    spec k {
        aborts_if false;
        ensures result == reserve_a * reserve_b;
    }

    spec spot_price {
        aborts_if reserve_a == 0;
        aborts_if (reserve_b << 64) / reserve_a > MAX_U128;
    }

    spec bps_denom {
        aborts_if false;
        ensures result == BPS_DENOM;
    }

    spec max_fee_bps {
        aborts_if false;
        ensures result == MAX_FEE_BPS;
        // The cap is what makes `fee_amount`'s `result <= amount_in` hold.
        ensures result < BPS_DENOM;
    }

    spec minimum_liquidity {
        aborts_if false;
        ensures result == MINIMUM_LIQUIDITY;
    }
}
