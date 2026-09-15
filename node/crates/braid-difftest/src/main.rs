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
//! `D` never decrease), and -- for StableSwap -- a third implementation in Python
//! written from Curve's published reference rather than from this code.
//!
//! # Why the output is committed
//!
//! The generated files are checked in on purpose. The RNG is seeded, so
//! regenerating produces an identical file unless a *value* changed -- and then
//! the diff shows exactly which case moved and by how much. A silent repricing
//! becomes a reviewable line in a pull request.
//!
//!   cargo run -p braid-difftest

use braid_quote::{clmm, clob, cpmm, stable};
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

// ---------------------------------------------------------------------------
// Concentrated liquidity: the math
// ---------------------------------------------------------------------------

fn gen_clmm_math(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_clmm::generated_diff_tests",
        "    use braid_clmm::i32::{Self, I32};\n    \
             use braid_clmm::swap_math;\n    \
             use braid_clmm::tick_math;\n\n    \
             fun t(magnitude: u32, negative: bool): I32 {\n        \
                 if (negative) { i32::neg_from(magnitude) } else { i32::from_u32(magnitude) }\n    \
             }\n\n    \
             fun step(c: u128, target: u128, l: u128, r: u64, f: u64, p: u128, i: u64, o: u64, fee: u64): bool {\n        \
                 let (p2, i2, o2, fee2) = swap_math::compute_swap_step(c, target, l, r, f);\n        \
                 p2 == p && i2 == i && o2 == o && fee2 == fee\n    \
             }\n",
    );

    let mut price_at_tick = Vec::new();
    let mut tick_at_price = Vec::new();
    let mut steps = Vec::new();

    for _ in 0..n {
        // Half near zero, where real pools live; half anywhere in range.
        let tick = if rng.range(0, 1) == 0 {
            rng.range(0, 20_000) as i32 - 10_000
        } else {
            rng.range(0, 2 * clmm::MAX_TICK as u64) as i32 - clmm::MAX_TICK
        };
        let p = clmm::sqrt_price_at_tick(tick).unwrap();
        price_at_tick.push(format!(
            "tick_math::sqrt_price_at_tick(t({}, {})) == {p}",
            tick.unsigned_abs(),
            tick < 0
        ));

        // A price strictly between two ticks, and exactly on one.
        let probe = if tick < clmm::MAX_TICK && rng.range(0, 3) != 0 {
            let next = clmm::sqrt_price_at_tick(tick + 1).unwrap();
            p + (rng.next() as u128) % (next - p)
        } else {
            p
        };
        let back = clmm::tick_at_sqrt_price(probe).unwrap();
        tick_at_price.push(format!(
            "i32::bits(tick_math::tick_at_sqrt_price({probe})) == {}",
            back as u32
        ));
    }

    let mut guard = 0;
    while steps.len() < n && guard < n * 50 {
        guard += 1;
        let a = rng.range(0, 40_000) as i32 - 20_000;
        let b = a + rng.range(1, 3_000) as i32 * if rng.range(0, 1) == 0 { 1 } else { -1 };
        let (Ok(pa), Ok(pb)) = (clmm::sqrt_price_at_tick(a), clmm::sqrt_price_at_tick(b)) else {
            continue;
        };
        let liquidity = rng.magnitude(3, 18) as u128 * rng.range(1, 1_000) as u128;
        let remaining = rng.magnitude(0, 17);
        let fee = [0, 1, 5, 30, 100, 1_000][rng.range(0, 5) as usize];
        if let Ok((np, i, o, f)) = clmm::compute_swap_step(pa, pb, liquidity, remaining, fee) {
            steps.push(format!("step({pa}, {pb}, {liquidity}, {remaining}, {fee}, {np}, {i}, {o}, {f})"));
        }
    }

    batched(&mut out, "sqrt_price_at_tick_agrees_with_the_rust_replica", &price_at_tick);
    batched(&mut out, "tick_at_sqrt_price_agrees_with_the_rust_replica", &tick_at_price);
    batched(&mut out, "compute_swap_step_agrees_with_the_rust_replica", &steps);
    out.push_str("}\n");
    out
}

// ---------------------------------------------------------------------------
// Concentrated liquidity: whole pools
// ---------------------------------------------------------------------------
//
// The math cases check each formula. These check the loop around them: a real
// pool, real positions, and swaps long enough to cross initialized ticks and
// the empty word boundaries between them. One `#[test]` per case, because the
// test runtime keeps dynamic fields across scenarios within one function and
// a second pool would inherit the first one's table ids.

fn gen_clmm_pools(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_clmm::generated_pool_diff_tests",
        "    use sui::coin;\n    \
             use sui::test_scenario::{Self as ts, Scenario};\n    \
             use braid_clmm::i32;\n    \
             use braid_clmm::pool::{Self, Pool};\n\n    \
             public struct A has drop {}\n    \
             public struct B has drop {}\n\n    \
             fun add(sc: &mut Scenario, p: &mut Pool<A, B>, lm: u32, ln: bool, um: u32, un: bool, a0: u64, a1: u64, c0: u64, c1: u64) {\n        \
                 let ca = coin::mint_for_testing<A>(a0, sc.ctx());\n        \
                 let cb = coin::mint_for_testing<B>(a1, sc.ctx());\n        \
                 let (ra, rb) = pool::add_liquidity_at(p, lm, ln, um, un, ca, cb, sc.ctx());\n        \
                 assert!(ra.value() == c0 && rb.value() == c1, 100);\n        \
                 coin::burn_for_testing(ra);\n        \
                 coin::burn_for_testing(rb);\n    \
             }\n\n    \
             fun swap(sc: &mut Scenario, p: &mut Pool<A, B>, a_to_b: bool, amount: u64, limit: u128, want_out: u64, want_change: u64) {\n        \
                 if (a_to_b) {\n            \
                     let c = coin::mint_for_testing<A>(amount, sc.ctx());\n            \
                     let (o, ch) = pool::swap_a_for_b(p, c, 0, limit, sc.ctx());\n            \
                     assert!(o.value() == want_out, 101);\n            \
                     assert!(ch.value() == want_change, 102);\n            \
                     coin::burn_for_testing(o);\n            \
                     coin::burn_for_testing(ch);\n        \
                 } else {\n            \
                     let c = coin::mint_for_testing<B>(amount, sc.ctx());\n            \
                     let (o, ch) = pool::swap_b_for_a(p, c, 0, limit, sc.ctx());\n            \
                     assert!(o.value() == want_out, 101);\n            \
                     assert!(ch.value() == want_change, 102);\n            \
                     coin::burn_for_testing(o);\n            \
                     coin::burn_for_testing(ch);\n        \
                 }\n    \
             }\n",
    );

    let mut made = 0;
    let mut guard = 0;
    while made < n && guard < n * 50 {
        guard += 1;
        if let Some(body) = clmm_case(rng, made) {
            out.push_str(&body);
            made += 1;
        }
    }
    out.push_str("}\n");
    out
}

/// One pool scenario, or `None` if the replica rejects any step of it -- the
/// generator only emits cases the chain is expected to accept.
fn clmm_case(rng: &mut Rng, index: usize) -> Option<String> {
    let spacing = [1u32, 10, 60, 200][rng.range(0, 3) as usize];
    let fee = [0u64, 5, 30, 100][rng.range(0, 3) as usize];

    let start_tick = match rng.range(0, 2) {
        0 => rng.range(0, 2_000) as i32 - 1_000,
        1 => rng.range(0, 200_000) as i32 - 100_000,
        _ => rng.range(0, 1_200_000) as i32 - 600_000,
    };
    let lo = clmm::sqrt_price_at_tick(start_tick).ok()?;
    let hi = clmm::sqrt_price_at_tick(start_tick + 1).ok()?;
    let sqrt_price = if rng.range(0, 2) == 0 { lo } else { lo + (rng.next() as u128) % (hi - lo) };

    let mut pool = clmm::Pool::new(sqrt_price, fee, spacing).ok()?;
    let mut body = String::new();
    let _ = writeln!(body, "\n    #[test]\n    fun pool_case_{index}() {{");
    let _ = writeln!(body, "        let mut sc = ts::begin(@0xA);");
    let _ = writeln!(body, "        pool::create_pool<A, B>({sqrt_price}, {fee}, {spacing}, sc.ctx());");
    let _ = writeln!(body, "        sc.next_tx(@0xA);");
    let _ = writeln!(body, "        let mut p = sc.take_shared<Pool<A, B>>();");

    // Ranges wide enough, in words, that swaps cross empty word boundaries as
    // well as initialized ticks. A word is 256 * spacing ticks.
    let word = 256 * spacing as i32;
    let aligned = |t: i32| t.div_euclid(spacing as i32) * spacing as i32;
    for _ in 0..rng.range(1, 4) {
        let below = rng.range(0, 3 * word as u64) as i32;
        let above = rng.range(0, 3 * word as u64) as i32;
        let lower = aligned(pool.tick - below).max(aligned(clmm::MIN_TICK) + spacing as i32);
        let upper = (aligned(pool.tick + above) + spacing as i32).min(aligned(clmm::MAX_TICK));
        let a0 = rng.magnitude(3, 15);
        let a1 = rng.magnitude(3, 15);
        let (_, need0, need1) = pool.add_liquidity(lower, upper, a0, a1).ok()?;
        let _ = writeln!(
            body,
            "        add(&mut sc, &mut p, {}, {}, {}, {}, {a0}, {a1}, {}, {});",
            lower.unsigned_abs(),
            lower < 0,
            upper.unsigned_abs(),
            upper < 0,
            a0 - need0,
            a1 - need1,
        );
    }
    let _ = writeln!(body, "        assert!(pool::liquidity(&p) == {}, 0);", pool.liquidity);

    for _ in 0..rng.range(1, 3) {
        let a_to_b = rng.range(0, 1) == 0;
        let amount = rng.magnitude(1, 15);
        let limit = if rng.range(0, 2) == 0 {
            // A limit inside the pool's reach, so some swaps stop on it.
            let t = if a_to_b {
                pool.tick - rng.range(1, 2 * word as u64) as i32
            } else {
                pool.tick + rng.range(1, 2 * word as u64) as i32
            };
            clmm::sqrt_price_at_tick(t.clamp(clmm::MIN_TICK, clmm::MAX_TICK)).ok()?
        } else if a_to_b {
            clmm::MIN_SQRT_PRICE
        } else {
            clmm::MAX_SQRT_PRICE
        };
        let (spent, got) = pool.swap(amount, a_to_b, limit).ok()?;
        let _ = writeln!(
            body,
            "        swap(&mut sc, &mut p, {a_to_b}, {amount}, {limit}, {got}, {});",
            amount - spent
        );
    }

    let _ = writeln!(body, "        assert!(pool::sqrt_price(&p) == {}, 1);", pool.sqrt_price);
    let _ = writeln!(body, "        assert!(i32::bits(pool::current_tick(&p)) == {}, 2);", pool.tick as u32);
    let _ = writeln!(body, "        assert!(pool::liquidity(&p) == {}, 3);", pool.liquidity);
    let _ = writeln!(body, "        ts::return_shared(p);\n        sc.end();\n    }}");
    Some(body)
}

// ---------------------------------------------------------------------------
// The order book
// ---------------------------------------------------------------------------

fn gen_clob(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_clob::generated_market_diff_tests",
        "    use sui::coin;\n    \
             use sui::test_scenario::{Self as ts, Scenario};\n    \
             use braid_clob::book;\n    \
             use braid_clob::market::{Self, Market};\n\n    \
             public struct BASE has drop {}\n    \
             public struct QUOTE has drop {}\n\n    \
             const MAKER: address = @0xA;\n    \
             const TAKER: address = @0xB;\n\n    \
             fun rest(sc: &mut Scenario, m: &mut Market<BASE, QUOTE>, price: u64, qty: u64, is_bid: bool) {\n        \
                 if (is_bid) {\n            \
                     let pay = coin::mint_for_testing<QUOTE>(18446744073709551615, sc.ctx());\n            \
                     let (o, ch, _) = market::place_bid(m, price, qty, book::gtc(), pay, sc.ctx());\n            \
                     coin::burn_for_testing(o);\n            \
                     coin::burn_for_testing(ch);\n        \
                 } else {\n            \
                     let pay = coin::mint_for_testing<BASE>(qty, sc.ctx());\n            \
                     let (o, ch, _) = market::place_ask(m, price, qty, book::gtc(), pay, sc.ctx());\n            \
                     coin::burn_for_testing(o);\n            \
                     coin::burn_for_testing(ch);\n        \
                 }\n    \
             }\n",
    );

    for index in 0..n {
        let tick = [100_000u64, 1_000_000, 10_000_000][rng.range(0, 2) as usize];
        // Any lot with tick * lot a multiple of the scale.
        let lot = (clob::PRICE_SCALE / tick) * rng.range(1, 20);
        let fee = [0u64, 1, 10, 100][rng.range(0, 3) as usize];
        // 0.5 .. 2.0, in steps of the largest tick so it is aligned for all.
        let mid = rng.range(50, 200) * 10_000_000;
        let mut book = clob::Book::new(tick, lot, fee);

        let mut body = String::new();
        let _ = writeln!(body, "\n    #[test]\n    fun market_case_{index}() {{");
        let _ = writeln!(body, "        let mut sc = ts::begin(MAKER);");
        let _ = writeln!(
            body,
            "        let cap = market::create_market<BASE, QUOTE>({tick}, {lot}, {fee}, sc.ctx());"
        );
        let _ = writeln!(body, "        transfer::public_transfer(cap, MAKER);");
        let _ = writeln!(body, "        sc.next_tx(MAKER);");
        let _ = writeln!(body, "        let mut m = sc.take_shared<Market<BASE, QUOTE>>();");

        for _ in 0..rng.range(1, 12) {
            let is_bid = rng.range(0, 1) == 0;
            let offset = rng.range(1, 400) * tick;
            let price = if is_bid { mid - offset.min(mid - tick) } else { mid + offset };
            let qty = lot * rng.range(1, 5_000);
            book.rest(price, qty, is_bid);
            let _ = writeln!(body, "        rest(&mut sc, &mut m, {price}, {qty}, {is_bid});");
        }
        let _ = writeln!(body, "        ts::return_shared(m);");
        let _ = writeln!(body, "        sc.next_tx(TAKER);");
        let _ = writeln!(body, "        let mut m = sc.take_shared<Market<BASE, QUOTE>>();");

        // Budgets from dust to more than the whole side.
        let budget = rng.magnitude(2, 13);
        let sell = rng.magnitude(2, 13);
        let (buy_out, buy_used) = book.quote_quote_for_base(budget);
        let (sell_out, sell_used) = book.quote_base_for_quote(sell);
        let _ = writeln!(
            body,
            "        let (q, u) = market::quote_quote_for_base(&m, {budget});\n        \
                     assert!(q == {buy_out} && u == {buy_used}, 0);\n        \
                     let (q, u) = market::quote_base_for_quote(&m, {sell});\n        \
                     assert!(q == {sell_out} && u == {sell_used}, 1);"
        );

        // Then execute both, buying first: the sell reads bids only, so the
        // buy's consumption of the asks does not change it.
        book.take_quote_for_base(budget);
        let _ = writeln!(
            body,
            "        let c = coin::mint_for_testing<QUOTE>({budget}, sc.ctx());\n        \
                     let (o, ch) = market::swap_quote_for_base(&mut m, c, 0, sc.ctx());\n        \
                     assert!(o.value() == {buy_out} && ch.value() == {}, 2);\n        \
                     coin::burn_for_testing(o);\n        \
                     coin::burn_for_testing(ch);\n        \
                     let c = coin::mint_for_testing<BASE>({sell}, sc.ctx());\n        \
                     let (o, ch) = market::swap_base_for_quote(&mut m, c, 0, sc.ctx());\n        \
                     assert!(o.value() == {sell_out} && ch.value() == {}, 3);\n        \
                     coin::burn_for_testing(o);\n        \
                     coin::burn_for_testing(ch);\n        \
                     assert!(market::best_ask(&m) == {}, 4);",
            budget - buy_used,
            sell - sell_used,
            book.asks.first().map_or(u64::MAX, |l| l.0),
        );
        let _ = writeln!(body, "        ts::return_shared(m);\n        sc.end();\n    }}");
        out.push_str(&body);
    }

    out.push_str("}\n");
    out
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
//
// The end of the chain: the optimizer plans against the Rust copy of the
// router test world, and the plan runs through `braid_router` on the Move one
// with `min_out` set to exactly what the plan predicts. A route that pays one
// unit less aborts; one that pays more fails the equality check.

fn gen_routes(rng: &mut Rng, n: usize) -> String {
    let mut out = header(
        "braid_router::generated_route_diff_tests",
        "    use braid_router::test_world;\n",
    );
    let venues = braid_route::fixtures::router_test_world();

    // Sizes spanning dust to several times the world's depth, plus the
    // hand-split case from route_tests.
    let mut amounts = vec![8_000_000u64];
    while amounts.len() < n {
        amounts.push(rng.magnitude(4, 7));
    }

    for (index, amount) in amounts.into_iter().enumerate() {
        let plan = braid_route::optimize(&venues, amount);
        let mut alloc = [0u64; 4];
        for leg in &plan.legs {
            alloc[leg.venue] = leg.amount;
        }
        let _ = writeln!(
            out,
            "\n    #[test]\n    fun optimized_route_{index}() {{\n        \
                 // {amount} in: cpmm {}, stable {}, clmm {}, clob {}\n        \
                 let (got, unspent) = test_world::buy_eth({}, {amount}, vector[{}, {}, {}, {}], {});\n        \
                 assert!(got == {} && unspent == {}, 0);\n    }}",
            alloc[0], alloc[1], alloc[2], alloc[3],
            0,
            alloc[0], alloc[1], alloc[2], alloc[3],
            plan.total_out,
            plan.total_out,
            plan.unspent,
        );
    }
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
    let mut rng_clmm = Rng(SEED ^ 0xC1_4411_u64);
    let mut rng_pools = Rng(SEED ^ 0x9001_5EED_u64);
    let mut rng_clob = Rng(SEED ^ 0xC10B_u64);
    let mut rng_routes = Rng(SEED ^ 0x2007E_u64);

    write(
        "../move/sui/braid_cpmm/tests/generated_diff_tests.move",
        &gen_cpmm(&mut rng_cpmm, n),
    );
    write(
        "../move/sui/braid_stable/tests/generated_diff_tests.move",
        &gen_stable(&mut rng_stable, n),
    );
    write(
        "../move/sui/braid_clmm/tests/generated_diff_tests.move",
        &gen_clmm_math(&mut rng_clmm, n),
    );
    // Whole scenarios are far heavier than single formulas, so fewer of them.
    write(
        "../move/sui/braid_clmm/tests/generated_pool_diff_tests.move",
        &gen_clmm_pools(&mut rng_pools, n / 4),
    );
    write(
        "../move/sui/braid_clob/tests/generated_market_diff_tests.move",
        &gen_clob(&mut rng_clob, n / 8),
    );
    write(
        "../move/sui/braid_router/tests/generated_route_diff_tests.move",
        &gen_routes(&mut rng_routes, n / 16),
    );

    println!("\nNow run:  bash scripts/test.sh");
}
