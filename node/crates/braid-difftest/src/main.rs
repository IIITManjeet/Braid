//! Differential test generator.
//!
//! Generates random pricing cases, computes each answer with the Rust replica in
//! `braid-quote`, and writes them out as Move test files. `sui move test` then
//! runs every case through the real Move VM against the real Move source. Any
//! disagreement between the two implementations fails the build.
//!
//! # What this proves, and what it doesn't
//!
//! It catches **divergence** between the two implementations: a mis-transliterated
//! operation order, a floor where the other has a ceil, a `u128` intermediate
//! where the other widened to `u256`, a platform difference in shift or
//! remainder semantics. That is the class of bug that would otherwise show up as
//! the off-chain quote engine promising a price the chain won't honour.
//!
//! It does **not** prove either side is economically correct. Two
//! implementations can agree and both be wrong. That is covered separately: the
//! hand-derived fixtures in the Move suites, the invariant properties (`k` and
//! `D` never decrease), and — for StableSwap — a third implementation in Python
//! written from Curve's published reference rather than from this code.
//!
//! # Why the output is committed
//!
//! The generated files are checked in on purpose. The RNG is seeded, so
//! regenerating produces an identical file unless a *value* changed — and then
//! the diff shows exactly which case moved and by how much. A silent repricing
//! becomes a reviewable line in a pull request.
//!
//!   cargo run -p braid-difftest

use braid_quote::{cpmm, stable};
use std::fmt::Write as _;
use std::fs;
use std::path::Path;

/// Fixed seed. Regenerating must be reproducible or the committed output is
/// noise rather than a diff.
const SEED: u64 = 0x8Ea1_C0FF_EE_u64;
/// Asserts per generated `#[test]` function, to keep each one small.
const BATCH: usize = 60;

/// xorshift64*. Deliberately hand-rolled: a dependency could change its
/// sequence between versions and silently invalidate every committed value.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Uniform in `[lo, hi]`.
    fn range(&mut self, lo: u64, hi: u64) -> u64 {
        if hi <= lo {
            return lo;
        }
        lo + self.next() % (hi - lo + 1)
    }

    /// A magnitude-biased draw: picks an exponent first, so small pools and
    /// enormous pools are sampled about equally rather than the range being
    /// dominated by huge values.
    fn magnitude(&mut self, min_pow: u32, max_pow: u32) -> u64 {
        let p = self.range(min_pow as u64, max_pow as u64) as u32;
        let base = 10u64.saturating_pow(p);
        self.range(base, base.saturating_mul(10).saturating_sub(1)).max(1)
    }
}

fn header(module: &str, uses: &str) -> String {
    format!(
        "#[test_only]\n\
         /// GENERATED FILE -- do not edit by hand.\n\
         ///\n\
         /// Every expected value here was produced by the Rust replica in\n\
         /// `node/crates/braid-quote`, then checked against this Move code by the\n\
         /// Move VM. A failure means the two implementations disagree, which is\n\
         /// exactly what this file exists to detect.\n\
         ///\n\
         /// Regenerate with:  cargo run -p braid-difftest\n\
         /// The RNG is seeded, so an unchanged implementation regenerates an\n\
         /// identical file.\n\
         module {module} {{\n\
         {uses}\n"
    )
}

/// Write `lines` as a series of batched `#[test]` functions.
fn batched(out: &mut String, name: &str, lines: &[String]) {
    for (i, chunk) in lines.chunks(BATCH).enumerate() {
        let _ = write!(out, "\n    #[test]\n    fun {name}_{i}() {{\n");
        for (j, l) in chunk.iter().enumerate() {
            let _ = writeln!(out, "        assert!({l}, {j});");
        }
        let _ = write!(out, "    }}\n");
    }
}

fn gen_cpmm(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_cpmm::generated_diff_tests",
        "    use braid_cpmm::cpmm_math;\n",
    );

    let mut amount_out = Vec::new();
    let mut amount_in = Vec::new();

    let mut made = 0usize;
    let mut guard = 0usize;
    while made < n && guard < n * 50 {
        guard += 1;
        let reserve_in = rng.magnitude(3, 18);
        let reserve_out = rng.magnitude(3, 18);
        let fee_bps = match rng.range(0, 4) {
            0 => 0,
            1 => 1,
            2 => 30,
            3 => 100,
            _ => rng.range(0, cpmm::MAX_FEE_BPS),
        };
        // Trade sizes from dust up to several times the pool.
        let dx = rng.magnitude(0, 18).min(u64::MAX / 4).max(1);

        if let Ok(v) = cpmm::amount_out(dx, reserve_in, reserve_out, fee_bps) {
            amount_out.push(format!(
                "cpmm_math::amount_out({dx}, {reserve_in}, {reserve_out}, {fee_bps}) == {v}"
            ));
            made += 1;

            // Feed the forward result back through the reverse direction, so the
            // exact-out path is exercised on values that are actually reachable.
            if v > 0 {
                if let Ok(back) = cpmm::amount_in(v, reserve_in, reserve_out, fee_bps) {
                    amount_in.push(format!(
                        "cpmm_math::amount_in({v}, {reserve_in}, {reserve_out}, {fee_bps}) == {back}"
                    ));
                }
            }
        }
    }

    batched(&mut out, "amount_out_agrees_with_the_rust_replica", &amount_out);
    batched(&mut out, "amount_in_agrees_with_the_rust_replica", &amount_in);
    out.push_str("}\n");
    out
}

fn gen_stable(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_stable::generated_diff_tests",
        "    use braid_stable::stable_math;\n",
    );

    let mut get_d = Vec::new();
    let mut amount_out = Vec::new();
    let mut amount_in = Vec::new();

    // Amplifications spanning the whole permitted range, including the low end
    // where the solver is most likely to hit a limit cycle.
    let amps = [100u64, 250, 1_000, 10_000, 100_000, 1_000_000, 100_000_000];

    let mut made = 0usize;
    let mut guard = 0usize;
    while made < n && guard < n * 50 {
        guard += 1;
        let amp = amps[(rng.next() % amps.len() as u64) as usize];
        let r0 = rng.magnitude(3, 17);
        // Skew the pair deliberately: a pegged pool is the easy case, and the
        // interesting numerical behaviour lives at wide ratios.
        let r1 = match rng.range(0, 3) {
            0 => r0,                                    // balanced
            1 => rng.range(r0 / 2, r0.saturating_mul(2).max(r0)), // near peg
            _ => rng.magnitude(3, 17),                  // anything
        }
        .max(1);
        let fee_bps = match rng.range(0, 3) {
            0 => 0,
            1 => 1,
            2 => 4,
            _ => rng.range(0, stable::MAX_FEE_BPS),
        };

        if let Ok(d) = stable::get_d(r0, r1, amp) {
            get_d.push(format!("stable_math::get_d({r0}, {r1}, {amp}) == {d}"));
            made += 1;
        } else {
            continue;
        }

        let dx = rng.magnitude(0, 16).max(1);
        if let Ok(v) = stable::amount_out(dx, r0, r1, amp, fee_bps) {
            amount_out.push(format!(
                "stable_math::amount_out({dx}, {r0}, {r1}, {amp}, {fee_bps}) == {v}"
            ));
            if v > 0 {
                if let Ok(back) = stable::amount_in(v, r0, r1, amp, fee_bps) {
                    amount_in.push(format!(
                        "stable_math::amount_in({v}, {r0}, {r1}, {amp}, {fee_bps}) == {back}"
                    ));
                }
            }
        }
    }

    batched(&mut out, "get_d_agrees_with_the_rust_replica", &get_d);
    batched(&mut out, "amount_out_agrees_with_the_rust_replica", &amount_out);
    batched(&mut out, "amount_in_agrees_with_the_rust_replica", &amount_in);
    out.push_str("}\n");
    out
}

fn write(path: &str, contents: &str) {
    let p = Path::new(path);
    if let Some(dir) = p.parent() {
        fs::create_dir_all(dir).expect("create test dir");
    }
    fs::write(p, contents).expect("write generated test");
    let asserts = contents.matches("assert!(").count();
    let tests = contents.matches("#[test]").count();
    println!("{path}: {asserts} cases in {tests} test functions");
}

fn main() {
    let n: usize = std::env::args()
        .nth(1)
        .and_then(|a| a.parse().ok())
        .unwrap_or(400);

    // Separate streams so changing one generator's count does not reshuffle the
    // other's cases and produce a misleading diff.
    let mut rng_cpmm = Rng(SEED);
    let mut rng_stable = Rng(SEED ^ 0x5DEE_CE66_D_u64);

    write(
        "../move/sui/braid_cpmm/tests/generated_diff_tests.move",
        &gen_cpmm(&mut rng_cpmm, n),
    );
    write(
        "../move/sui/braid_stable/tests/generated_diff_tests.move",
        &gen_stable(&mut rng_stable, n),
    );

    println!("\nNow run:  bash scripts/test.sh");
}
