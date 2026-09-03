/// The StableSwap invariant, for a two-coin pool.
///
/// ```text
///   A n^n Sum(x) + D = A D n^n + D^(n+1) / (n^n Prod(x))
/// ```
///
/// A blend of constant-sum (perfect pricing, drainable) and constant-product
/// (poor pricing, undrainable), weighted by an amplification term that decays
/// as the pool skews -- so the curve degrades into the one that cannot be
/// drained exactly when it needs to.
///
/// Neither D nor the post-trade balance y can be isolated, so both are solved
/// by Newton-Raphson. The iteration matches Curve's reference operation for
/// operation, including where each intermediate floor-divides: the Rust replica
/// has to reproduce these values exactly, and floor division does not
/// reassociate.
///
/// Over the integers it does not always terminate. Floor division makes each
/// step a map on the integers, and such a map need not have a fixed point -- at
/// extreme skew the iterate falls into a short orbit and `|x - x_prev| <= 1`
/// never fires. Curve's implementation exhausts its budget and reverts;
/// `resolve_cycle` detects the orbit instead.
///
/// A is stored pre-multiplied by A_PRECISION. Every intermediate runs at u256,
/// because D^3 for reserves near u64::MAX needs ~195 bits.
module braid_stable::stable_math {

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    /// Newton-Raphson neither converged nor closed a detectable orbit within
    /// `MAX_ITER`. Not reached by any state in a 60,000-case sweep; an abort is
    /// still better than a wrong price.
    const ENotConverged: u64 = 0;
    /// An amount that must be positive was zero.
    const EZeroAmount: u64 = 1;
    /// Amplification coefficient outside the permitted range.
    const EInvalidAmp: u64 = 2;
    /// A reserve was empty, or the trade asks for more than the pool holds.
    const EInsufficientLiquidity: u64 = 3;
    /// Fee outside the permitted range.
    const EInvalidFee: u64 = 4;
    /// A `u256` intermediate did not fit the target width.
    const EOverflow: u64 = 5;

    // ------------------------------------------------------------------ //
    // Constants                                                          //
    // ------------------------------------------------------------------ //

    /// Two coins. Written out rather than generalised: `n = 2` collapses the
    /// product and sum loops into straight-line code, and a stable pair is the
    /// only shape this venue is for.
    const N_COINS: u256 = 2;

    /// `A` is stored as `A * A_PRECISION`, so `amp = 8500` means `A = 85`.
    const A_PRECISION: u256 = 100;

    /// `A = 1`. Below this the curve is barely distinguishable from constant
    /// product, and the solver's seed stops being reliable.
    const MIN_AMP: u64 = 100;
    /// `A = 1_000_000`. Above this the pool is effectively constant-sum and one
    /// side can be drained on a depeg.
    const MAX_AMP: u64 = 100000000;

    /// Newton is allowed this many steps before the transaction aborts. It has
    /// never been observed to need more than ~9 when it converges at all.
    const MAX_ITER: u64 = 255;

    /// How many past iterates to keep for limit-cycle detection.
    ///
    /// Floor division makes the iteration a map on the integers, and an integer
    /// map need not have a fixed point -- at extreme skew it can settle into a
    /// short orbit instead, stepping between a handful of adjacent values
    /// forever. The plain `|d - d_prev| <= 1` rule never fires there and the
    /// reference implementation simply runs out of iterations and reverts.
    ///
    /// A sweep of 60,000 random states found orbits of length 2 and 5; eight
    /// slots covers those with room to spare.
    const CYCLE_WINDOW: u64 = 8;

    const BPS_DENOM: u256 = 10000;
    /// 1% -- far above what a stable pool should charge.
    const MAX_FEE_BPS: u64 = 100;

    /// LP burned on first deposit and never recoverable, for the same reason
    /// as in the CPMM: it stops the first-depositor donation attack.
    const MINIMUM_LIQUIDITY: u64 = 1000;

    const MAX_U64: u256 = 18446744073709551615;

    public fun min_amp(): u64 { MIN_AMP }

    public fun max_amp(): u64 { MAX_AMP }

    public fun max_fee_bps(): u64 { MAX_FEE_BPS }

    public fun a_precision(): u64 { 100 }

    public fun minimum_liquidity(): u64 { MINIMUM_LIQUIDITY }

    /// Amp must be in range for any pool operation to be meaningful.
    public fun assert_valid_amp(amp: u64) {
        assert!(amp >= MIN_AMP && amp <= MAX_AMP, EInvalidAmp);
    }

    // ------------------------------------------------------------------ //
    // D -- the invariant                                                 //
    // ------------------------------------------------------------------ //

    /// Solve the invariant for `D`, the pool's virtual total.
    ///
    /// `D` is what the reserves would sum to if the pool were perfectly
    /// balanced, and it is the quantity LP shares are denominated in. For a
    /// balanced pool `D == x0 + x1` exactly; skew pushes it below the sum.
    ///
    /// The iteration is
    ///
    /// ```text
    ///   D <- (Ann·S/AP + n·D_P) · D  /  ((Ann - AP)·D/AP + (n+1)·D_P)
    /// ```
    ///
    /// with `D_P = D^(n+1) / (n^n Πx)`, seeded at `D = S`. From that seed the
    /// sequence descends towards the root, so `|D - D_prev| <= 1` is a sound
    /// stopping rule wherever it fires -- and where it never fires, the orbit
    /// detector does.
    public fun get_d(x0: u64, x1: u64, amp: u64): u128 {
        assert_valid_amp(amp);

        let s = (x0 as u256) + (x1 as u256);
        if (s == 0) return 0;

        let xp0 = (x0 as u256);
        let xp1 = (x1 as u256);
        assert!(xp0 > 0 && xp1 > 0, EInsufficientLiquidity);

        let ann = (amp as u256) * N_COINS;

        let mut d = s;
        let mut history = vector<u256>[];
        let mut i = 0;
        while (i < MAX_ITER) {
            // D_P = D^3 / (4 x0 x1), accumulated one coin at a time so the
            // floor divisions land exactly where Curve's do.
            let mut d_p = d;
            d_p = d_p * d / (xp0 * N_COINS);
            d_p = d_p * d / (xp1 * N_COINS);

            let d_prev = d;
            let next = (ann * s / A_PRECISION + d_p * N_COINS) * d
                / ((ann - A_PRECISION) * d / A_PRECISION + (N_COINS + 1) * d_p);

            if (abs_diff_u256(next, d_prev) <= 1) return narrow(next);

            let (cycled, resolved) = resolve_cycle(&history, next);
            if (cycled) return narrow(resolved);

            push_bounded(&mut history, next);
            d = next;
            i = i + 1;
        };
        abort ENotConverged
    }

    // ------------------------------------------------------------------ //
    // y -- the post-trade balance                                        //
    // ------------------------------------------------------------------ //

    /// Given the invariant `d` and the *new* balance of one coin, solve for the
    /// balance the other coin must hold.
    ///
    /// Newton on `y^2 + (b - D)·y - c = 0`, seeded at `y = D`. `D` is above the
    /// root whenever the pool is solvent, and the iteration decreases from
    /// there, so the same `<= 1` stopping rule applies.
    ///
    /// `x_new` is the balance of the coin being paid *in*, after the deposit.
    public fun get_y(x_new: u128, d: u128, amp: u64): u128 {
        assert_valid_amp(amp);
        assert!(x_new > 0, EZeroAmount);
        if (d == 0) return 0;

        let x = (x_new as u256);
        let dd = (d as u256);
        let ann = (amp as u256) * N_COINS;

        // c = D^3 · AP / (4 · x · Ann); b = x + D·AP/Ann.
        // Again: same order of operations as the reference.
        let mut c = dd;
        c = c * dd / (x * N_COINS);
        c = c * dd * A_PRECISION / (ann * N_COINS);
        let b = x + dd * A_PRECISION / ann;

        let mut y = dd;
        let mut history = vector<u256>[];
        let mut i = 0;
        while (i < MAX_ITER) {
            let y_prev = y;
            // b + 2y > D holds for every solvent state, so this cannot wrap.
            let next = (y * y + c) / (N_COINS * y + b - dd);

            if (abs_diff_u256(next, y_prev) <= 1) return narrow(next);

            let (cycled, resolved) = resolve_cycle(&history, next);
            if (cycled) return narrow(resolved);

            push_bounded(&mut history, next);
            y = next;
            i = i + 1;
        };
        abort ENotConverged
    }

    // ------------------------------------------------------------------ //
    // Swaps                                                              //
    // ------------------------------------------------------------------ //

    /// Exact-in quote. Returns the amount of the output coin paid to the
    /// trader, net of fee.
    ///
    /// Unlike the CPMM, the fee here is taken from the *output*. That is what
    /// Curve does, and for a pair trading near parity the two are almost
    /// indistinguishable -- but matching the reference is what lets the Rust
    /// replica be checked against a known-good implementation rather than only
    /// against itself.
    public fun amount_out(
        dx: u64,
        reserve_in: u64,
        reserve_out: u64,
        amp: u64,
        fee_bps: u64,
    ): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(dx > 0, EZeroAmount);
        assert!(reserve_in > 0 && reserve_out > 0, EInsufficientLiquidity);

        let d = get_d(reserve_in, reserve_out, amp);
        let x_new = (reserve_in as u128) + (dx as u128);
        let y = get_y(x_new, d, amp);

        // The solver lands on or just above the true root; subtracting one unit
        // guarantees the pool never pays out more than the curve allows.
        assert!((y as u256) < (reserve_out as u256), EInsufficientLiquidity);
        let dy_gross = (reserve_out as u256) - (y as u256) - 1;
        if (dy_gross == 0) return 0;

        let fee = ceil_div(dy_gross * (fee_bps as u256), BPS_DENOM);
        let dy = dy_gross - fee;
        assert!(dy <= MAX_U64, EOverflow);
        (dy as u64)
    }

    /// The fee a given gross output would pay. Rounded up, so dust still pays.
    public fun fee_on_output(dy_gross: u64, fee_bps: u64): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        (ceil_div((dy_gross as u256) * (fee_bps as u256), BPS_DENOM) as u64)
    }

    /// Exact-out quote: the input needed to receive exactly `dy` net.
    ///
    /// Runs the curve backwards -- gross the output up through the fee, solve
    /// for the input-side balance that leaves the pool at that output balance,
    /// and add one unit so rounding lands against the trader.
    public fun amount_in(
        dy: u64,
        reserve_in: u64,
        reserve_out: u64,
        amp: u64,
        fee_bps: u64,
    ): u64 {
        assert!(fee_bps <= MAX_FEE_BPS, EInvalidFee);
        assert!(dy > 0, EZeroAmount);
        assert!(reserve_in > 0 && reserve_out > 0, EInsufficientLiquidity);

        // Gross up: after the fee is taken from `dy_gross`, `dy` must remain.
        let dy_gross = ceil_div(
            (dy as u256) * BPS_DENOM,
            BPS_DENOM - (fee_bps as u256),
        );
        assert!(dy_gross + 1 < (reserve_out as u256), EInsufficientLiquidity);

        let d = get_d(reserve_in, reserve_out, amp);
        // Undo the `- 1` that `amount_out` applies.
        let y_target = (reserve_out as u256) - dy_gross - 1;
        let x_new = get_y((y_target as u128), d, amp);

        assert!((x_new as u256) > (reserve_in as u256), EInsufficientLiquidity);
        let dx = (x_new as u256) - (reserve_in as u256) + 1;
        assert!(dx <= MAX_U64, EOverflow);
        (dx as u64)
    }

    // ------------------------------------------------------------------ //
    // Liquidity                                                          //
    // ------------------------------------------------------------------ //

    /// LP minted for the first deposit: `D` itself.
    ///
    /// Denominating shares in `D` rather than in `sqrt(xy)` is what makes a
    /// stable pool's share price stay at ~1.0 -- the number LPs actually watch.
    public fun initial_lp(x0: u64, x1: u64, amp: u64): u64 {
        let d = get_d(x0, x1, amp);
        assert!(d > 0, EZeroAmount);
        assert!((d as u256) <= MAX_U64, EOverflow);
        (d as u64)
    }

    /// The imbalance fee on a deposit, per coin.
    ///
    /// A deposit that shifts the pool's ratio is a trade wearing a deposit's
    /// clothes: without a charge, an attacker deposits entirely into the cheap
    /// side, withdraws proportionally, and pockets the difference for free.
    /// Curve's correction charges the swap fee on each coin's distance from the
    /// ideal balanced deposit, scaled by `n / (4(n-1))` -- which for two coins
    /// is exactly half the swap fee.
    public fun imbalance_fee_bps(fee_bps: u64): u64 {
        // n / (4(n-1)) with n = 2  ->  2/4  ->  fee/2, rounded up so the pool
        // is never short.
        (ceil_div((fee_bps as u256), 2) as u64)
    }

    /// LP minted for a deposit into a pool that already holds liquidity, and
    /// the per-coin imbalance fees withheld from it.
    ///
    /// Returns `(lp_minted, fee_0, fee_1)`. The fees stay in the pool, so they
    /// accrue to existing LPs rather than being paid out anywhere.
    public fun lp_for_deposit(
        deposit_0: u64,
        deposit_1: u64,
        reserve_0: u64,
        reserve_1: u64,
        lp_supply: u64,
        amp: u64,
        fee_bps: u64,
    ): (u64, u64, u64) {
        assert!(lp_supply > 0, EInsufficientLiquidity);
        assert!(deposit_0 > 0 || deposit_1 > 0, EZeroAmount);

        let d0 = (get_d(reserve_0, reserve_1, amp) as u256);
        let new_0 = (reserve_0 as u256) + (deposit_0 as u256);
        let new_1 = (reserve_1 as u256) + (deposit_1 as u256);
        assert!(new_0 <= MAX_U64 && new_1 <= MAX_U64, EOverflow);
        let d1 = (get_d((new_0 as u64), (new_1 as u64), amp) as u256);
        assert!(d1 > d0, EZeroAmount);

        let imb_bps = (imbalance_fee_bps(fee_bps) as u256);

        // Each coin is charged on how far it lands from the balanced deposit.
        let ideal_0 = d1 * (reserve_0 as u256) / d0;
        let ideal_1 = d1 * (reserve_1 as u256) / d0;
        let fee_0 = ceil_div(abs_diff_u256(ideal_0, new_0) * imb_bps, BPS_DENOM);
        let fee_1 = ceil_div(abs_diff_u256(ideal_1, new_1) * imb_bps, BPS_DENOM);

        // Shares are priced off the post-fee balances, so the fee stays behind.
        let adj_0 = new_0 - fee_0;
        let adj_1 = new_1 - fee_1;
        let d2 = (get_d((adj_0 as u64), (adj_1 as u64), amp) as u256);

        let minted = (lp_supply as u256) * (d2 - d0) / d0;
        assert!(minted > 0, EZeroAmount);
        assert!(minted <= MAX_U64, EOverflow);
        ((minted as u64), (fee_0 as u64), (fee_1 as u64))
    }

    /// Proportional withdrawal. No fee: taking out the ratio you are entitled
    /// to does not move the pool's balance, so there is nothing to charge for.
    public fun withdraw_amounts(
        lp_amount: u64,
        reserve_0: u64,
        reserve_1: u64,
        lp_supply: u64,
    ): (u64, u64) {
        assert!(lp_supply > 0, EInsufficientLiquidity);
        assert!(lp_amount > 0, EZeroAmount);
        assert!(lp_amount <= lp_supply, EInsufficientLiquidity);
        let lp = (lp_amount as u256);
        let supply = (lp_supply as u256);
        (
            ((lp * (reserve_0 as u256) / supply) as u64),
            ((lp * (reserve_1 as u256) / supply) as u64),
        )
    }

    // ------------------------------------------------------------------ //
    // Views                                                              //
    // ------------------------------------------------------------------ //

    /// `D / total_supply` in Q64.64 -- the price of one LP share.
    ///
    /// Starts at 1.0 and only ever rises, since every fee raises `D` without
    /// minting. A share price that ever falls means the pool lost value.
    public fun virtual_price(
        reserve_0: u64,
        reserve_1: u64,
        lp_supply: u64,
        amp: u64,
    ): u128 {
        assert!(lp_supply > 0, EInsufficientLiquidity);
        let d = (get_d(reserve_0, reserve_1, amp) as u256);
        (((d << 64) / (lp_supply as u256)) as u128)
    }

    // ------------------------------------------------------------------ //
    // Internal                                                           //
    // ------------------------------------------------------------------ //

    fun abs_diff_u256(a: u256, b: u256): u256 {
        if (a > b) a - b else b - a
    }

    /// `D` and `y` are both bounded by the sum of two `u64` reserves.
    fun narrow(v: u256): u128 {
        assert!(v <= MAX_U64 * 2, EOverflow);
        (v as u128)
    }

    /// Detect a limit cycle and pick a representative from it.
    ///
    /// If `next` repeats a value still in the window, the iterate has closed an
    /// orbit and will circle forever. Everything from that earlier occurrence
    /// onwards is a member of the orbit, so the maximum over that span is the
    /// answer -- and it is the *maximum* rather than the minimum on purpose:
    /// the orbit's members straddle the true root within a few units, and
    /// overstating `D` makes the pool solve for a larger `y`, which pays the
    /// trader less. Erring the other way would pay out units the curve does not
    /// have.
    ///
    /// Values seen *before* the orbit was entered are larger still (the
    /// sequence descends to the root), which is why the scan starts at the
    /// match instead of covering the whole window.
    fun resolve_cycle(history: &vector<u256>, next: u256): (bool, u256) {
        let n = vector::length(history);
        let mut i = 0;
        let mut found = false;
        let mut best = next;
        while (i < n) {
            let v = *vector::borrow(history, i);
            if (v == next) found = true;
            if (found && v > best) best = v;
            i = i + 1;
        };
        (found, best)
    }

    /// Append, dropping the oldest entry once the window is full.
    fun push_bounded(history: &mut vector<u256>, v: u256) {
        vector::push_back(history, v);
        if (vector::length(history) > CYCLE_WINDOW) {
            vector::remove(history, 0);
        };
    }

    fun ceil_div(n: u256, d: u256): u256 {
        let q = n / d;
        if (n % d == 0) q else q + 1
    }
}
