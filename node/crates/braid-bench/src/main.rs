//! Quote latency: how long the replica takes to price a leg, and to plan a
//! whole route, per venue.
//!
//!   cargo run --release -p braid-bench              # from node/
//!   cargo run --release -p braid-bench -- 200000    # samples per venue
//!
//! Two worlds. `router_test_world` is what the Move route tests and the Aptos
//! deployment trade. The testnet snapshot is the real Sui state the first live
//! route was planned against (`deployments/routes/first-route-snapshot.json`):
//! its concentrated pool has every tick it had on chain.
//!
//! Each sample is timed on its own, so the tail is the tail of single quotes
//! rather than an average smeared over a batch. Amounts are log-uniform from
//! one unit to 16M, because a quote's cost follows its size -- a book walks
//! more levels and a concentrated pool crosses more ticks the bigger the leg --
//! and a uniform draw would almost never ask for a small one.

use std::hint::black_box;
use std::time::{Duration, Instant};

use braid_route::{Venue, fixtures, optimize, snapshot};

/// xorshift64*: seeded, so two runs ask for the same amounts.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Log-uniform in `[1, 2^24)`.
    fn amount(&mut self) -> u64 {
        let bits = 1 + self.next() % 24;
        (1 << (bits - 1)) | (self.next() & ((1 << (bits - 1)) - 1))
    }
}

struct Stats {
    p50: Duration,
    p99: Duration,
    p999: Duration,
    max: Duration,
}

fn stats(mut samples: Vec<Duration>) -> Stats {
    samples.sort_unstable();
    let at = |q: f64| samples[((samples.len() as f64 * q) as usize).min(samples.len() - 1)];
    Stats { p50: at(0.50), p99: at(0.99), p999: at(0.999), max: *samples.last().unwrap() }
}

fn time<F: FnMut(u64)>(rng: &mut Rng, n: usize, mut f: F) -> Stats {
    // Warm the caches and the branch predictors before anything counts.
    for _ in 0..n / 10 {
        f(rng.amount());
    }
    let samples = (0..n)
        .map(|_| {
            let amount = rng.amount();
            let t = Instant::now();
            f(amount);
            t.elapsed()
        })
        .collect();
    stats(samples)
}

fn us(d: Duration) -> String {
    format!("{:.2}", d.as_nanos() as f64 / 1000.0)
}

fn row(name: &str, s: &Stats) {
    println!("| {name:<14} | {:>8} | {:>8} | {:>8} | {:>8} |", us(s.p50), us(s.p99), us(s.p999), us(s.max));
}

fn bench(title: &str, venues: &[Venue], n: usize) {
    println!("\n### {title}\n");
    println!("| {:<14} | {:>8} | {:>8} | {:>8} | {:>8} |", "quote (us)", "p50", "p99", "p99.9", "max");
    println!("|{:-<16}|{:->10}|{:->10}|{:->10}|{:->10}|", "", "", "", "", "");
    let mut rng = Rng(0xB4A1D_2007E);
    for venue in venues {
        let s = time(&mut rng, n, |a| {
            black_box(venue.quote(black_box(a)));
        });
        row(venue.kind(), &s);
    }
    // A plan quotes every venue hundreds of times, so far fewer samples.
    let s = time(&mut rng, (n / 100).max(200), |a| {
        black_box(optimize(black_box(venues), black_box(a)));
    });
    row("optimize", &s);
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(100_000);
    if cfg!(debug_assertions) {
        eprintln!("warning: debug build -- run with --release for numbers worth reading");
    }

    println!("{n} samples per venue, amounts log-uniform in [1, 16M)");
    bench("router test world", &fixtures::router_test_world(), n);

    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../deployments/routes/first-route-snapshot.json");
    match std::fs::read_to_string(path).map_err(|e| e.to_string()).and_then(|t| snapshot::parse(&t)) {
        Ok(snap) => bench("Sui testnet snapshot", &snap.venues, n),
        Err(e) => eprintln!("skipping the testnet snapshot: {e}"),
    }
}
