//! Where the server gets venue state from, and how it describes it.
//!
//! Two worlds, and the difference matters for what the UI may offer:
//!
//! * `test-world` is `braid_router::test_world`, the fixture the generated
//!   route tests run against. It is reproducible and always available, and the
//!   Aptos deployment seeds its venues to exactly it -- so a plan made here is
//!   a prediction of that chain. It is not a Sui object, so it cannot be executed.
//! * `sui-testnet` is the live deployment. It starts from the snapshot
//!   committed under `deployments/routes/`, which is the state the first route
//!   was planned against; that route moved the pools, so the committed copy is
//!   a historical record, not current state. `refresh` re-reads the chain
//!   through `scripts/route.py snapshot` and replaces it. Only a refreshed
//!   snapshot is safe to execute against.

use std::path::Path;

use braid_route::snapshot::{Snapshot, VenueRef, parse};
use braid_route::{Venue, fixtures};
use serde_json::{Value, json};

pub const TEST_WORLD: &str = "test-world";
pub const SUI_TESTNET: &str = "sui-testnet";

/// A set of venues one order can be split across, plus what is known about
/// where they came from.
pub struct World {
    pub id: String,
    pub label: String,
    pub description: String,
    pub snapshot: Snapshot,
    /// Whether the venues are real Sui objects a wallet could trade through.
    pub executable: bool,
    /// Whether the state was read from the chain during this process's life.
    pub live: bool,
    pub source: String,
}

impl World {
    pub fn summary(&self) -> Value {
        json!({
            "id": self.id,
            "label": self.label,
            "description": self.description,
            "executable": self.executable,
            "live": self.live,
            "source": self.source,
            "routerPackage": self.snapshot.router_package,
            "coinIn": self.snapshot.coin_in,
            "coinOut": self.snapshot.coin_out,
            "venues": self.snapshot
                .venues
                .iter()
                .zip(&self.snapshot.refs)
                .map(|(v, r)| venue_json(v, r))
                .collect::<Vec<_>>(),
        })
    }
}

/// `braid_router::test_world`, wrapped so it reads like a snapshot.
///
/// The refs carry no object ids: there is nothing on chain to point at. That
/// absence is what `executable: false` is derived from.
pub fn test_world() -> World {
    let venues = fixtures::router_test_world();
    let refs = venues
        .iter()
        .map(|v| VenueRef { kind: v.kind().to_string(), object: String::new(), forward: true })
        .collect();
    World {
        id: TEST_WORLD.into(),
        label: "Router test world".into(),
        description: "The fixture the generated route tests run against, and the state \
                      the Aptos deployment seeds its venues to. Reproducible, offline."
            .into(),
        snapshot: Snapshot {
            router_package: String::new(),
            coin_in: "TUSD".into(),
            coin_out: "TETH".into(),
            venues,
            refs,
        },
        executable: false,
        live: false,
        source: "braid_route::fixtures::router_test_world".into(),
    }
}

/// Load a snapshot written by `scripts/route.py snapshot`.
pub fn from_snapshot_file(path: &Path, live: bool, source: String) -> Result<World, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let snapshot = parse(&text)?;
    Ok(World {
        id: SUI_TESTNET.into(),
        label: "Sui testnet".into(),
        description: if live {
            "Live state, read from the chain just now. Safe to execute against.".into()
        } else {
            // No instruction to refresh here: whether that is even possible
            // depends on the deployment, and the page says so where it knows.
            "The snapshot the first four-venue route was planned against. That route \
             moved these pools, so this is a record rather than current state."
                .into()
        },
        snapshot,
        executable: true,
        live,
        source,
    })
}

/// Everything the UI needs to draw a venue, including the state it prices from.
///
/// The tick list and the book's levels are included in full: they are what make
/// the concentrated pool's and the book's curves step the way they do, and a
/// chart of those curves is not explicable without them.
pub fn venue_json(venue: &Venue, r: &VenueRef) -> Value {
    let mut v = match venue {
        Venue::Cpmm { reserve_in, reserve_out, fee_bps } => json!({
            "reserveIn": reserve_in,
            "reserveOut": reserve_out,
            "feeBps": fee_bps,
            "invariant": (*reserve_in as u128) * (*reserve_out as u128),
        }),
        Venue::Stable { reserve_in, reserve_out, amp, fee_bps } => json!({
            "reserveIn": reserve_in,
            "reserveOut": reserve_out,
            "amp": amp,
            "feeBps": fee_bps,
        }),
        Venue::Clmm { pool, zero_for_one } => json!({
            "sqrtPrice": pool.sqrt_price.to_string(),
            "tick": pool.tick,
            "liquidity": pool.liquidity.to_string(),
            "feeBps": pool.fee_bps,
            "tickSpacing": pool.tick_spacing,
            "zeroForOne": zero_for_one,
            "ticks": pool.ticks.iter().map(|(t, s)| json!({
                "tick": t,
                "liquidityGross": s.liquidity_gross.to_string(),
                "liquidityNet": s.liquidity_net.to_string(),
            })).collect::<Vec<_>>(),
        }),
        Venue::ClobBuyBase { book } | Venue::ClobSellBase { book } => json!({
            "tickSize": book.tick_size,
            "lotSize": book.lot_size,
            "takerFeeBps": book.taker_fee_bps,
            "buyBase": matches!(venue, Venue::ClobBuyBase { .. }),
            // Asks ascending, bids descending: the order each side is consumed in.
            "asks": book.asks.iter().map(|(p, q)| json!([p, q])).collect::<Vec<_>>(),
            "bids": book.bids.iter().map(|(p, q)| json!([p, q])).collect::<Vec<_>>(),
        }),
    };
    let o = v.as_object_mut().expect("venue json is an object");
    o.insert("kind".into(), json!(r.kind));
    o.insert("object".into(), json!(r.object));
    o.insert("forward".into(), json!(r.forward));
    o.insert("label".into(), json!(label_for(&r.kind)));
    o.insert("blurb".into(), json!(blurb_for(&r.kind)));
    v
}

fn label_for(kind: &str) -> &'static str {
    match kind {
        "cpmm" => "Constant product",
        "stable" => "StableSwap",
        "clmm" => "Concentrated liquidity",
        "clob" => "Order book",
        _ => "Venue",
    }
}

fn blurb_for(kind: &str) -> &'static str {
    match kind {
        "cpmm" => "x * y = k. Fee on the input, rounding in favour of the pool.",
        "stable" => "The Curve invariant, solved by Newton-Raphson for D and y.",
        "clmm" => "Tick bitmap and 1.0001^tick sqrt-price math, stepping across initialized ticks.",
        "clob" => "Crit-bit book, price-time priority. Trades in whole lots, so it hands dust back.",
        _ => "",
    }
}
