//! Plan a route against a snapshot.
//!
//!   cargo run -p braid-route -- <snapshot.json> <amount_in> [slippage_bps] [plan.json]
//!
//! Prints the split and, if a path is given, writes the plan that
//! `scripts/route.py execute` turns into one PTB.

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        eprintln!("usage: braid-route <snapshot.json> <amount_in> [slippage_bps] [plan.json]");
        return ExitCode::FAILURE;
    }
    let text = match std::fs::read_to_string(&args[0]) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("{}: {e}", args[0]);
            return ExitCode::FAILURE;
        }
    };
    let snapshot = match braid_route::snapshot::parse(&text) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("bad snapshot: {e}");
            return ExitCode::FAILURE;
        }
    };
    let Ok(amount_in) = args[1].parse::<u64>() else {
        eprintln!("amount_in must be a u64");
        return ExitCode::FAILURE;
    };
    let slippage_bps = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(50);

    let plan = braid_route::optimize(&snapshot.venues, amount_in);

    println!("route {amount_in} through {} venues", snapshot.venues.len());
    println!("{:<8} {:>14} {:>14} {:>14}", "venue", "amount", "spent", "out");
    for leg in &plan.legs {
        println!(
            "{:<8} {:>14} {:>14} {:>14}",
            snapshot.refs[leg.venue].kind, leg.amount, leg.spent, leg.out
        );
    }
    println!("{:<8} {:>14} {:>14} {:>14}", "total", amount_in, amount_in - plan.unspent, plan.total_out);
    println!("unspent  {}", plan.unspent);
    println!("min_out  {} ({slippage_bps} bps)", braid_route::min_out(plan.total_out, slippage_bps));
    for (i, venue) in snapshot.venues.iter().enumerate() {
        let (out, spent) = venue.quote(amount_in);
        println!("  all-in {:<8} out {out:>14}  spent {spent:>14}", snapshot.refs[i].kind);
    }
    // Compare only against venues that take the whole order. One that runs
    // out of depth pays less *and* hands input back, and setting the split's
    // output against its output alone would flatter the split.
    let filling = snapshot
        .venues
        .iter()
        .enumerate()
        .map(|(i, v)| (i, v.quote(amount_in)))
        .filter(|&(_, (_, spent))| spent == amount_in)
        .max_by_key(|&(_, (out, _))| out);
    match filling {
        Some((i, (single, _))) if single > 0 && plan.unspent == 0 => {
            let gain = plan.total_out as f64 / single as f64 - 1.0;
            println!(
                "split vs best venue that fills the whole order ({}): +{} ({:+.3}%)",
                snapshot.refs[i].kind,
                plan.total_out - single,
                gain * 100.0
            );
        }
        Some(_) => println!("the split leaves input unspent; no like-for-like single-venue comparison"),
        None => println!("no single venue can fill the whole order"),
    }

    if let Some(path) = args.get(3) {
        let json = snapshot.plan_json(&plan, slippage_bps);
        if let Err(e) = std::fs::write(path, serde_json::to_string_pretty(&json).unwrap() + "\n") {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
        println!("plan written to {path}");
    }
    ExitCode::SUCCESS
}
