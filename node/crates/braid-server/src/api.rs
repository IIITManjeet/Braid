//! The HTTP surface.
//!
//! Every number the UI shows comes from `braid-quote` and `braid-route` --
//! the same code the differential fuzzer checks against both Move VMs. The
//! server adds no pricing of its own; where it derives something (a share, a
//! marginal rate) it derives it from replica quotes and says so.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use axum::Json;
use axum::Router;
use axum::extract::{Query, State};
use axum::routing::{get, post};
use tower_http::cors::CorsLayer;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use braid_route::{Plan, Venue, min_out, optimize};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::repo;
use crate::world::{self, SUI_TESTNET, TEST_WORLD, World};

pub struct AppState {
    pub root: PathBuf,
    pub worlds: RwLock<HashMap<String, Arc<World>>>,
}

impl AppState {
    pub fn new(root: PathBuf) -> AppState {
        let mut worlds: HashMap<String, Arc<World>> = HashMap::new();
        worlds.insert(TEST_WORLD.into(), Arc::new(world::test_world()));
        // The committed snapshot is a historical record; `refresh` replaces it
        // with live state. Loading it here means the page has something real to
        // draw before anyone asks the chain for anything.
        let committed = root.join("deployments").join("routes").join("first-route-snapshot.json");
        if let Ok(w) = world::from_snapshot_file(
            &committed,
            false,
            "deployments/routes/first-route-snapshot.json".into(),
        ) {
            worlds.insert(SUI_TESTNET.into(), Arc::new(w));
        }
        AppState { root, worlds: RwLock::new(worlds) }
    }

    fn world(&self, id: &str) -> Option<Arc<World>> {
        self.worlds.read().expect("worlds lock").get(id).cloned()
    }
}

type Res = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn bad(msg: impl Into<String>) -> (StatusCode, Json<Value>) {
    (StatusCode::BAD_REQUEST, Json(json!({ "error": msg.into() })))
}

fn pick(state: &AppState, id: &str) -> Result<Arc<World>, (StatusCode, Json<Value>)> {
    state.world(id).ok_or_else(|| bad(format!("no world `{id}`")))
}

// -------------------------------------------------------------------------- //
// Worlds                                                                     //
// -------------------------------------------------------------------------- //

pub async fn worlds(State(s): State<Arc<AppState>>) -> Json<Value> {
    let ids = [TEST_WORLD, SUI_TESTNET];
    let list: Vec<Value> = ids.iter().filter_map(|id| s.world(id).map(|w| w.summary())).collect();
    Json(json!({ "worlds": list }))
}

#[derive(Deserialize)]
pub struct WorldQuery {
    #[serde(default = "default_world")]
    world: String,
}

fn default_world() -> String {
    TEST_WORLD.into()
}

pub async fn venues(State(s): State<Arc<AppState>>, Query(q): Query<WorldQuery>) -> Res {
    Ok(Json(pick(&s, &q.world)?.summary()))
}

// -------------------------------------------------------------------------- //
// Quoting and routing                                                        //
// -------------------------------------------------------------------------- //

/// What every venue pays for the *whole* order, each on its own.
///
/// This is the split's honest comparison set, and the one the CLI prints.
fn all_in(venues: &[Venue], kinds: &[String], amount_in: u64) -> Vec<Value> {
    venues
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let (out, spent) = v.quote(amount_in);
            json!({
                "index": i,
                "venue": kinds[i],
                "out": out,
                "spent": spent,
                // A venue that cannot take the whole order is not a
                // like-for-like alternative to a split that can.
                "fillsWholeOrder": spent == amount_in && out > 0,
            })
        })
        .collect()
}

/// Output for one more unit at the current allocation, per unit consumed.
///
/// The optimizer's stopping condition is that these are as equal as an integer
/// staircase lets them be, so showing them is showing the argument. Probed with
/// a finite difference because the curves are not differentiable: a book is flat
/// inside a level and jumps at its edge.
fn marginal(venue: &Venue, amount: u64, probe: u64) -> Option<f64> {
    let (out0, spent0) = venue.quote(amount);
    let (out1, spent1) = venue.quote(amount.saturating_add(probe));
    if spent1 <= spent0 || out1 < out0 {
        return None;
    }
    Some((out1 - out0) as f64 / (spent1 - spent0) as f64)
}

fn plan_json(w: &World, plan: &Plan, amount_in: u64, slippage_bps: u64) -> Value {
    let kinds: Vec<String> = w.snapshot.refs.iter().map(|r| r.kind.clone()).collect();
    let venues = &w.snapshot.venues;
    // Big enough to cross a lot boundary on the book, small enough to be a
    // local slope: a thousandth of the order.
    let probe = (amount_in / 1000).max(1);

    let legs: Vec<Value> = plan
        .legs
        .iter()
        .map(|l| {
            json!({
                "index": l.venue,
                "venue": kinds[l.venue],
                "amount": l.amount,
                "spent": l.spent,
                "out": l.out,
                "share": if amount_in == 0 { 0.0 } else { l.spent as f64 / amount_in as f64 },
                "effectivePrice": if l.spent == 0 { 0.0 } else { l.out as f64 / l.spent as f64 },
                "marginal": marginal(&venues[l.venue], l.amount, probe),
            })
        })
        .collect();

    // Venues the plan left out, with the rate they would pay for the next
    // unit. If one of these is above every leg's marginal, the split is wrong.
    let idle: Vec<Value> = (0..venues.len())
        .filter(|i| !plan.legs.iter().any(|l| l.venue == *i))
        .map(|i| {
            json!({
                "index": i,
                "venue": kinds[i],
                "marginal": marginal(&venues[i], 0, probe),
            })
        })
        .collect();

    let best_single =
        plan.best_single.map(|(i, out)| json!({ "index": i, "venue": kinds[i], "out": out }));
    // Only venues that take the whole order are a fair comparison; one that
    // runs out of depth pays less and hands input back.
    let filling = venues
        .iter()
        .enumerate()
        .map(|(i, v)| (i, v.quote(amount_in)))
        .filter(|&(_, (out, spent))| spent == amount_in && out > 0)
        .max_by_key(|&(_, (out, _))| out);

    json!({
        "world": w.id,
        "executable": w.executable,
        "live": w.live,
        "amountIn": amount_in,
        "slippageBps": slippage_bps,
        "totalOut": plan.total_out,
        "unspent": plan.unspent,
        "minOut": min_out(plan.total_out, slippage_bps),
        "legs": legs,
        "idleVenues": idle,
        "allIn": all_in(venues, &kinds, amount_in),
        "bestSingle": best_single,
        "bestFillingWholeOrder": filling.map(|(i, (out, _))| json!({
            "index": i,
            "venue": kinds[i],
            "out": out,
            "gain": plan.total_out.saturating_sub(out),
            "gainPct": if out == 0 { 0.0 } else { plan.total_out as f64 / out as f64 - 1.0 },
        })),
        // The exact Move calls, if there is a chain to send them to.
        "call": if w.executable { w.snapshot.plan_json(plan, slippage_bps) } else { Value::Null },
    })
}

#[derive(Deserialize)]
pub struct RouteBody {
    #[serde(default = "default_world")]
    world: String,
    #[serde(rename = "amountIn")]
    amount_in: u64,
    #[serde(rename = "slippageBps", default)]
    slippage_bps: u64,
}

pub async fn route(State(s): State<Arc<AppState>>, Json(b): Json<RouteBody>) -> Res {
    if b.amount_in == 0 {
        return Err(bad("amountIn must be greater than zero"));
    }
    if b.slippage_bps > 10_000 {
        return Err(bad("slippageBps must be at most 10000"));
    }
    let w = pick(&s, &b.world)?;
    let plan = optimize(&w.snapshot.venues, b.amount_in);
    let mut out = plan_json(&w, &plan, b.amount_in, b.slippage_bps);

    // A wallet needs somewhere to get the input coin. The test coins' treasury
    // caps are shared, so the same transaction can mint what it spends.
    if w.executable {
        let symbol = w.snapshot.coin_in.rsplit("::").next().unwrap_or_default().to_uppercase();
        if let Some(t) = repo::test_coin_treasury(&s.root, &symbol) {
            if let Some(call) = out.get_mut("call").and_then(Value::as_object_mut) {
                call.insert("mint_treasury".into(), json!(t));
                call.insert("mint_symbol".into(), json!(symbol));
            }
        }
    }
    Ok(Json(out))
}

#[derive(Deserialize)]
pub struct QuoteBody {
    #[serde(default = "default_world")]
    world: String,
    #[serde(rename = "amountIn")]
    amount_in: u64,
}

/// Each venue priced on its own, with no split. The comparison, not the product.
pub async fn quote(State(s): State<Arc<AppState>>, Json(b): Json<QuoteBody>) -> Res {
    let w = pick(&s, &b.world)?;
    let kinds: Vec<String> = w.snapshot.refs.iter().map(|r| r.kind.clone()).collect();
    Ok(Json(json!({
        "world": w.id,
        "amountIn": b.amount_in,
        "venues": all_in(&w.snapshot.venues, &kinds, b.amount_in),
    })))
}

// -------------------------------------------------------------------------- //
// Curves                                                                     //
// -------------------------------------------------------------------------- //

#[derive(Deserialize)]
pub struct CurveQuery {
    #[serde(default = "default_world")]
    world: String,
    #[serde(default)]
    max: Option<u64>,
    #[serde(default)]
    points: Option<usize>,
    /// Include the routed total at each size. Costs one `optimize` per point.
    #[serde(default)]
    route: Option<bool>,
}

/// Output against order size, per venue and (optionally) for the split.
///
/// Sampled on a log scale: the interesting structure -- a book's lot steps, a
/// concentrated pool running out of range -- is spread over orders of
/// magnitude, and a linear sweep spends every point in the last decade.
pub async fn curve(State(s): State<Arc<AppState>>, Query(q): Query<CurveQuery>) -> Res {
    let w = pick(&s, &q.world)?;
    let points = q.points.unwrap_or(48).clamp(2, 200);
    let max = q.max.unwrap_or(16_000_000).max(2);
    let want_route = q.route.unwrap_or(true);

    let sizes: Vec<u64> = (0..points)
        .map(|i| {
            let t = i as f64 / (points - 1) as f64;
            (max as f64).powf(t).round().max(1.0) as u64
        })
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect();

    let kinds: Vec<String> = w.snapshot.refs.iter().map(|r| r.kind.clone()).collect();
    let series: Vec<Value> = w
        .snapshot
        .venues
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let pts: Vec<Value> = sizes
                .iter()
                .map(|&x| {
                    let (out, spent) = v.quote(x);
                    json!({ "in": x, "out": out, "spent": spent })
                })
                .collect();
            json!({ "venue": kinds[i], "index": i, "points": pts })
        })
        .collect();

    let route_pts = want_route.then(|| {
        sizes
            .iter()
            .map(|&x| {
                let p = optimize(&w.snapshot.venues, x);
                json!({ "in": x, "out": p.total_out, "spent": x - p.unspent })
            })
            .collect::<Vec<Value>>()
    });

    Ok(Json(json!({
        "world": w.id,
        "sizes": sizes,
        "venues": series,
        "route": route_pts,
    })))
}

// -------------------------------------------------------------------------- //
// Repository artifacts                                                       //
// -------------------------------------------------------------------------- //

pub async fn deployments(State(s): State<Arc<AppState>>) -> Json<Value> {
    Json(repo::deployments(&s.root))
}

pub async fn bench(State(s): State<Arc<AppState>>) -> Json<Value> {
    Json(repo::bench(&s.root))
}

pub async fn difftest(State(s): State<Arc<AppState>>) -> Json<Value> {
    Json(repo::difftest(&s.root))
}

// -------------------------------------------------------------------------- //
// Refresh                                                                    //
// -------------------------------------------------------------------------- //

/// Re-read live Sui venue state, and replace the `sui-testnet` world with it.
///
/// This is the only thing the server does that touches the network, and it is
/// what makes execution safe: a plan built against the committed snapshot would
/// name a `min_out` the pools have since moved away from.
pub async fn refresh(State(s): State<Arc<AppState>>) -> Res {
    if !repo::can_refresh(&s.root) {
        return Err(bad(
            "this deployment cannot read live chain state: it needs Python and the Sui CLI, neither of which is installed here",
        ));
    }
    let root = s.root.clone();
    let out = root.join("deployments").join("routes").join(".live-snapshot.json");
    let target = out.clone();
    let done = tokio::task::spawn_blocking(move || repo::refresh_sui_snapshot(&root, &target))
        .await
        .map_err(|e| bad(format!("refresh task failed: {e}")))?;
    done.map_err(|e| (StatusCode::BAD_GATEWAY, Json(json!({ "error": e }))))?;

    let w = world::from_snapshot_file(&out, true, "scripts/route.py snapshot (live)".into())
        .map_err(bad)?;
    let summary = w.summary();
    s.worlds.write().expect("worlds lock").insert(SUI_TESTNET.into(), Arc::new(w));
    Ok(Json(summary))
}

/// Every route the server answers, assembled over one shared state.
///
/// Built here rather than in `main` so a test can drive it with
/// `tower::ServiceExt::oneshot` -- no socket, no port, no ordering between
/// tests.
pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/api/health", get(health))
        .route("/api/worlds", get(worlds))
        .route("/api/venues", get(venues))
        .route("/api/curve", get(curve))
        .route("/api/quote", post(quote))
        .route("/api/route", post(route))
        .route("/api/refresh", post(refresh))
        .route("/api/deployments", get(deployments))
        .route("/api/bench", get(bench))
        .route("/api/difftest", get(difftest))
        // The front end normally reaches this through Next's dev proxy, which
        // makes it same-origin. Permissive CORS is for the case where it is
        // served from somewhere else.
        .layer(CorsLayer::permissive())
        .with_state(state)
}

pub async fn health(State(s): State<Arc<AppState>>) -> impl IntoResponse {
    Json(json!({
        "ok": true,
        "root": s.root.display().to_string(),
        // The page hides its refresh control when this is false, rather than
        // offering one that cannot work.
        "canRefresh": repo::can_refresh(&s.root),
    }))
}
