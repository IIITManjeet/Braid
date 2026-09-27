/// Machine-checked specifications for `q64`.
///
/// Q64.64 is a `u128` read as an integer scaled by `2^64`. Almost everything
/// here is a shift or a mask, which is exactly the kind of code that looks
/// obviously right and is worth checking anyway: the two masks are 39-digit
/// constants, and a wrong bit in either is invisible to inspection.
///
/// Spec arithmetic is arbitrary precision, so `v / Q64` below is real division
/// rather than the shift the implementation performs. Stating it that way is
/// the point -- it pins the bit manipulation against the arithmetic it is
/// supposed to mean.
///
///     aptos move prove --dev -f q64
spec braid_math::q64 {

    spec one {
        aborts_if false;
        ensures result == Q64;
    }

    spec zero {
        aborts_if false;
        ensures result == 0;
    }

    /// `(2^64 - 1) * 2^64 < 2^128`, so widening an integer into Q64.64 can
    /// never leave the type.
    spec from_u64 {
        aborts_if false;
        ensures result == x * Q64;
        // A whole number carries no fraction.
        ensures result % Q64 == 0;
    }

    spec to_u64_floor {
        aborts_if false;
        ensures result == v / Q64;
    }

    // `to_u64_ceil`, `fract` and `floor` are deliberately left unspecified.
    //
    // All three reach their answer with a mask, and the prover will not reason
    // about one value through both bitwise and arithmetic operators. Saying
    // `fract` is `v % Q64` fails outright with "cannot appear in both
    // arithmetic and bitwise operation"; `to_u64_ceil`, which mixes a shift and
    // a mask, instead runs past the solver's timeout. The alternative is to
    // restate the mask, which proves only that the code is the code.
    //
    // So the claim actually worth making -- that FRACT_MASK and INT_MASK are
    // complementary, the thing a 20- and a 39-digit literal could plausibly get
    // wrong -- is out of reach here, and `q64_tests` carries it instead. Worth
    // knowing before reaching for the prover on bit-twiddling code: it is at
    // its best on arithmetic and close to useless on masks.

    spec add {
        aborts_if a + b > MAX_U128;
        ensures result == a + b;
    }

    /// An explicit code rather than a native arithmetic abort, so a caller can
    /// tell an underflow from any other failure.
    spec sub {
        aborts_if a < b;
        ensures result == a - b;
    }
}
