//! Reading the repository's own artifacts: deployments, benchmarks, and the
//! size of the generated differential-fuzz corpora.
//!
//! Nothing here is a fixture. The counts the dashboard shows are counted from
//! the committed `generated_*.move` files at request time, so a page that
//! claims 1,200 CLMM cases is claiming it about the files on disk.

use std::path::{Path, PathBuf};

use serde_json::{Value, json};

/// Walk up from `start` until a directory looks like the Braid checkout.
pub fn find_root(start: &Path) -> Option<PathBuf> {
    let mut dir = Some(start);
    while let Some(d) = dir {
        if d.join("deployments").is_dir() && d.join("move").is_dir() && d.join("node").is_dir() {
            return Some(d.to_path_buf());
        }
        dir = d.parent();
    }
    None
}

fn read_json(path: &Path) -> Option<Value> {
    serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()
}

/// Every deployment record the checkout has, keyed by network.
///
/// `aptos-testnet.json` only exists once that run has happened; its absence is
/// reported rather than hidden, because it is the project's last open item.
pub fn deployments(root: &Path) -> Value {
    let d = root.join("deployments");
    json!({
        "sui": {
            "testnet": read_json(&d.join("testnet.json")),
            "firstRoutePlan": read_json(&d.join("routes").join("first-route-plan.json")),
            "firstRouteSnapshot": read_json(&d.join("routes").join("first-route-snapshot.json")),
        },
        "aptos": {
            "local": read_json(&d.join("aptos-local.json")),
            "testnet": read_json(&d.join("aptos-testnet.json")),
        },
        // Suiscan puts the network in the path; Aptos Explorer wants it as a
        // query parameter and silently shows mainnet without one, so the
        // suffix travels with the bases rather than being assumed downstream.
        "explorers": {
            "suiTx": "https://suiscan.xyz/testnet/tx/",
            "suiObject": "https://suiscan.xyz/testnet/object/",
            "aptosTx": "https://explorer.aptoslabs.com/txn/",
            "aptosAccount": "https://explorer.aptoslabs.com/account/",
            "aptosSuffix": "?network=testnet",
        },
    })
}

/// The shared `TreasuryCap` for a test coin, if the Sui deployment records one.
///
/// These caps are shared on purpose -- testnet faucet behaviour, documented as
/// deliberately unsafe in `braid_test_coins`. It is what lets a visitor's own
/// wallet mint the input coin for a route in the same transaction that spends
/// it, exactly as `scripts/route.py execute` does.
pub fn test_coin_treasury(root: &Path, symbol: &str) -> Option<String> {
    read_json(&root.join("deployments").join("testnet.json"))?
        .get("testCoinTreasuries")?
        .get(symbol)?
        .as_str()
        .map(str::to_owned)
}

/// Gas per venue on both chains, and the replica's quote latency.
pub fn bench(root: &Path) -> Value {
    let b = root.join("bench").join("results");
    json!({
        "sui": read_json(&b.join("gas-sui-testnet.json")),
        "aptos": read_json(&b.join("gas-aptos-local.json")),
        "latency": std::fs::read_to_string(b.join("latency.md")).ok(),
    })
}

/// One generated corpus: where it lives, and how much is in it.
///
/// Two counts, because a "case" means different things in the two kinds of
/// suite, and `braid-difftest` prints both for exactly that reason. A formula
/// suite packs many independent checks into one test function, so its cases are
/// the `assert!`s. A scenario suite builds chain state, so one `#[test]` is one
/// pool or one book, and its asserts are the several things checked about it.
fn corpus(root: &Path, chain: &str, package: &str, file: &str, kind: &str) -> Option<Value> {
    let rel = format!("move/{chain}/{package}/tests/{file}");
    let text = std::fs::read_to_string(root.join(&rel)).ok()?;
    let asserts = text.matches("assert!(").count();
    let tests = text.matches("#[test]").count();
    let cases = if kind == "formula" { asserts } else { tests };
    Some(json!({
        "path": rel,
        "cases": cases,
        "asserts": asserts,
        "tests": tests,
        "bytes": text.len(),
    }))
}

/// The differential fuzzer's footprint, counted from the files on disk.
///
/// The `identical` flag is the claim the README makes about the formula
/// corpora -- that the Sui and Aptos files are byte-for-byte the same -- and it
/// is recomputed here rather than asserted.
pub fn difftest(root: &Path) -> Value {
    let suites = [
        ("cpmm", "braid_cpmm", "generated_diff_tests.move", "formula"),
        ("stable", "braid_stable", "generated_diff_tests.move", "formula"),
        ("clmm", "braid_clmm", "generated_diff_tests.move", "formula"),
        ("clmm-pool", "braid_clmm", "generated_pool_diff_tests.move", "scenario"),
        ("clob", "braid_clob", "generated_market_diff_tests.move", "scenario"),
        // 25 optimizer plans, each executed at a min_out equal to its
        // prediction -- one plan per test, so these count like scenarios.
        ("router", "braid_router", "generated_route_diff_tests.move", "plan"),
    ];
    let rows: Vec<Value> = suites
        .iter()
        .filter_map(|(name, package, file, kind)| {
            let sui = corpus(root, "sui", package, file, kind);
            let aptos = corpus(root, "aptos", package, file, kind);
            let identical = match (&sui, &aptos) {
                (Some(_), Some(_)) => {
                    let a = std::fs::read(root.join(format!("move/sui/{package}/tests/{file}"))).ok();
                    let b = std::fs::read(root.join(format!("move/aptos/{package}/tests/{file}"))).ok();
                    a.is_some() && a == b
                }
                _ => false,
            };
            if sui.is_none() && aptos.is_none() {
                return None;
            }
            Some(json!({
                "venue": name,
                "package": package,
                "kind": kind,
                "sui": sui,
                "aptos": aptos,
                "identical": identical,
            }))
        })
        .collect();
    // Split the headline the way the README does: the formula corpora are one
    // number ("3,029 formula cases"), the scenario suites are counted as
    // scenarios, and adding the two together would be comparing unlike things.
    let sum = |kind: &str| -> u64 {
        rows.iter()
            .filter(|r| r.get("kind").and_then(Value::as_str) == Some(kind))
            .filter_map(|r| r.pointer("/sui/cases").and_then(Value::as_u64))
            .sum()
    };
    let asserts: u64 = rows
        .iter()
        .filter_map(|r| r.pointer("/sui/asserts").and_then(Value::as_u64))
        .sum();
    json!({
        "suites": rows,
        "formulaCases": sum("formula"),
        "scenarios": sum("scenario"),
        "plans": sum("plan"),
        "totalAsserts": asserts,
    })
}

/// Whether this deployment can read live Sui state.
///
/// Reading it means running `scripts/route.py snapshot`, which needs Python and
/// the Sui CLI. The CLI is ~800MB and vendored rather than installed, so it
/// does not travel into a container: a deployed build serves the committed
/// snapshot and says so, rather than offering a button that fails.
pub fn can_refresh(root: &Path) -> bool {
    if !root.join("scripts").join("route.py").is_file() {
        return false;
    }
    on_path(&python()) && (on_path("sui") || root.join(".tools").join(SUI_EXE).is_file())
}

#[cfg(windows)]
const SUI_EXE: &str = "sui.exe";
#[cfg(not(windows))]
const SUI_EXE: &str = "sui";

/// `--version` is the cheapest question every one of these answers.
fn on_path(program: &str) -> bool {
    std::process::Command::new(program)
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// Re-read live Sui venue state by running `scripts/route.py snapshot`.
///
/// Shelling out rather than reimplementing: that script already decodes the
/// dynamic fields -- every initialized tick, every book level -- out of the BCS
/// the Sui CLI hands back, and it is the code the committed snapshot came from.
/// A second implementation here would be a second thing to keep correct.
pub fn refresh_sui_snapshot(root: &Path, out: &Path) -> Result<(), String> {
    let script = root.join("scripts").join("route.py");
    let tools = root.join(".tools");
    let path = match std::env::var("PATH") {
        Ok(p) => format!("{}{}{}", tools.display(), PATH_SEP, p),
        Err(_) => tools.display().to_string(),
    };
    let output = std::process::Command::new(python())
        .arg(&script)
        .arg("snapshot")
        .arg(out)
        .current_dir(root)
        .env("PATH", path)
        .output()
        .map_err(|e| format!("could not run {}: {e}", script.display()))?;
    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        let out = String::from_utf8_lossy(&output.stdout);
        return Err(format!("route.py snapshot failed:\n{out}\n{err}").trim().to_string());
    }
    Ok(())
}

#[cfg(windows)]
const PATH_SEP: char = ';';
#[cfg(not(windows))]
const PATH_SEP: char = ':';

fn python() -> String {
    std::env::var("BRAID_PYTHON").unwrap_or_else(|_| {
        if cfg!(windows) { "python".into() } else { "python3".into() }
    })
}
