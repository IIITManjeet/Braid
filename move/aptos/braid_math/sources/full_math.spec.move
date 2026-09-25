/// Machine-checked specifications for `full_math`.
///
/// Kept in its own file rather than inline, because `full_math.move` and six
/// other modules are byte-identical to their `move/sui` twins and that property
/// is worth more than the convenience of one file. `diff` between the two trees
/// must stay empty.
///
/// The unit tests and the differential fuzzer check *instances*: 742 CPMM cases,
/// 3,029 formula cases in all, each a concrete triple of inputs and the answer
/// the Rust replica computed. These say something the fuzzer cannot -- that the
/// claim holds for every input, including the ones nobody generated. Run with:
///
///     aptos move prove --dev
///
/// Spec arithmetic is arbitrary-precision (`num`), so `a * b` below is the real
/// product, not a u128 one. That is exactly what makes these worth stating:
/// they pin the implementation's widened-and-then-narrowed arithmetic against
/// mathematics that cannot itself overflow.
spec braid_math::full_math {

    /// The whole point of widening: a `u128` product is always representable in
    /// `u256`, so this can never abort and never truncates.
    spec full_mul {
        aborts_if false;
        ensures result == a * b;
    }

    spec mul_div_floor {
        aborts_if denom == 0;
        aborts_if a * b / denom > MAX_U128;
        ensures result == a * b / denom;
    }

    spec mul_div_ceil {
        aborts_if denom == 0;
        aborts_if (a * b + denom - 1) / denom > MAX_U128;
        // Stated as the exact rounding rule rather than as `+ 1`, so the
        // remainder-zero case is part of what gets checked.
        ensures result == (a * b + denom - 1) / denom;
        // Rounding direction is not decoration: the ceiling is never below the
        // floor, and never more than one unit above it. That bound is what
        // lets a call site choose a direction knowing what the choice costs.
        ensures result >= a * b / denom;
        ensures result <= a * b / denom + 1;
    }

    spec mul_div_floor_u64 {
        aborts_if denom == 0;
        aborts_if a * b / denom > MAX_U64;
        ensures result == a * b / denom;
    }

    spec mul_div_ceil_u64 {
        aborts_if denom == 0;
        aborts_if (a * b + denom - 1) / denom > MAX_U64;
        ensures result == (a * b + denom - 1) / denom;
        ensures result >= a * b / denom;
        ensures result <= a * b / denom + 1;
    }

    spec min_u128 {
        aborts_if false;
        ensures result == (if (a < b) a else b);
        ensures result <= a && result <= b;
    }

    spec max_of_u128 {
        aborts_if false;
        ensures result == (if (a > b) a else b);
        ensures result >= a && result >= b;
    }

    spec min_u64 {
        aborts_if false;
        ensures result <= a && result <= b;
    }

    spec max_of_u64 {
        aborts_if false;
        ensures result >= a && result >= b;
    }

    spec abs_diff {
        aborts_if false;
        ensures result == (if (a > b) a - b else b - a);
    }
}
