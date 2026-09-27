//! End-to-end tests over the HTTP surface.
//!
//! Each one drives the real `Router` with `oneshot`, so there is no socket, no
//! port and no ordering between tests -- but every layer below the transport is
//! the one that runs in production, including the state construction that reads
//! the checkout off disk.
//!
//! They run against the actual repository rather than fixtures. That is
//! deliberate: several of these endpoints exist to report what is *in* the
//! repository -- how many generated cases there are, which deployments were
//! recorded -- and a fixture would let those drift from the thing they describe
//! without anything noticing.

use std::path::PathBuf;
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::Value;
use tower::ServiceExt;

use crate::api::{AppState, router};
use crate::repo;

/// The checkout this crate lives in.
fn root() -> PathBuf {
    let here = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    repo::find_root(&here).expect("tests run from inside the Braid checkout")
}

async fn get(path: &str) -> (StatusCode, Value) {
    send(Request::builder().uri(path).body(Body::empty()).unwrap()).await
}

async fn post(path: &str, body: Value) -> (StatusCode, Value) {
    send(
        Request::builder()
            .method("POST")
            .uri(path)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap(),
    )
    .await
}

async fn send(req: Request<Body>) -> (StatusCode, Value) {
    let app = router(Arc::new(AppState::new(root())));
    let res = app.oneshot(req).await.expect("router responded");
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX).await.expect("body");
    let json = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, json)
}

// -------------------------------------------------------------------------- //
// The two worlds                                                             //
// -------------------------------------------------------------------------- //

#[tokio::test]
async fn both_worlds_are_served_and_only_one_is_executable() {
    let (status, body) = get("/api/worlds").await;
    assert_eq!(status, StatusCode::OK);

    let worlds = body["worlds"].as_array().expect("worlds array");
    assert_eq!(worlds.len(), 2);

    let fixture = &worlds[0];
    assert_eq!(fixture["id"], "test-world");
    // There is no object to point a transaction at, so the page must not offer
    // to send one.
    assert_eq!(fixture["executable"], false);
    assert_eq!(fixture["live"], false);

    let testnet = &worlds[1];
    assert_eq!(testnet["id"], "sui-testnet");
    assert_eq!(testnet["executable"], true);
    // Served from the committed snapshot until something reads the chain.
    assert_eq!(testnet["live"], false);
}

#[tokio::test]
async fn every_world_carries_four_venues_in_leg_order() {
    let (_, body) = get("/api/worlds").await;
    for world in body["worlds"].as_array().unwrap() {
        let kinds: Vec<&str> =
            world["venues"].as_array().unwrap().iter().map(|v| v["kind"].as_str().unwrap()).collect();
        // The order `buy_eth` takes, which the plan's leg indices are relative to.
        assert_eq!(kinds, ["cpmm", "stable", "clmm", "clob"], "world {}", world["id"]);
    }
}

// -------------------------------------------------------------------------- //
// Routing                                                                    //
// -------------------------------------------------------------------------- //

/// The number four other implementations produce for this order: the Rust
/// optimizer, both Move VMs through the generated route tests, and the Aptos
/// testnet transaction recorded in `deployments/aptos-testnet.json`.
const TEST_WORLD_8M_OUT: u64 = 7_986_004;

#[tokio::test]
async fn the_fixture_route_pays_what_the_chain_paid() {
    let (status, plan) =
        post("/api/route", serde_json::json!({ "world": "test-world", "amountIn": 8_000_000 })).await;
    assert_eq!(status, StatusCode::OK);

    assert_eq!(plan["totalOut"].as_u64().unwrap(), TEST_WORLD_8M_OUT);
    assert_eq!(plan["unspent"].as_u64().unwrap(), 0);
    // Zero slippage by default, so min_out is the prediction itself.
    assert_eq!(plan["minOut"].as_u64().unwrap(), TEST_WORLD_8M_OUT);

    let legs = plan["legs"].as_array().unwrap();
    assert_eq!(legs.len(), 4, "all four venues take part at this size");
    let summed: u64 = legs.iter().map(|l| l["out"].as_u64().unwrap()).sum();
    // Venues share no state, which is the whole premise of the router.
    assert_eq!(summed, TEST_WORLD_8M_OUT);
}

#[tokio::test]
async fn slippage_lowers_min_out_and_nothing_else() {
    let order = |bps| serde_json::json!({ "world": "test-world", "amountIn": 8_000_000, "slippageBps": bps });
    let (_, tight) = post("/api/route", order(0)).await;
    let (_, loose) = post("/api/route", order(50)).await;

    assert_eq!(tight["totalOut"], loose["totalOut"], "the plan itself does not move");
    assert!(loose["minOut"].as_u64().unwrap() < tight["minOut"].as_u64().unwrap());
    assert_eq!(loose["minOut"].as_u64().unwrap(), TEST_WORLD_8M_OUT * 9_950 / 10_000);
}

#[tokio::test]
async fn an_order_too_small_for_a_lot_leaves_the_book_out() {
    let (_, plan) =
        post("/api/route", serde_json::json!({ "world": "test-world", "amountIn": 5_000 })).await;

    let used: Vec<&str> =
        plan["legs"].as_array().unwrap().iter().map(|l| l["venue"].as_str().unwrap()).collect();
    assert!(!used.contains(&"clob"), "5,000 buys no whole 10,000-unit lot");

    // And it is reported as idle rather than silently omitted, because the page
    // shows what an unused venue would have paid.
    let idle: Vec<&str> =
        plan["idleVenues"].as_array().unwrap().iter().map(|v| v["venue"].as_str().unwrap()).collect();
    assert!(idle.contains(&"clob"));
}

#[tokio::test]
async fn the_split_beats_the_best_venue_that_can_fill_the_whole_order() {
    let (_, plan) =
        post("/api/route", serde_json::json!({ "world": "test-world", "amountIn": 8_000_000 })).await;

    let best = &plan["bestFillingWholeOrder"];
    assert!(!best.is_null(), "some venue can take 8,000,000 alone");
    assert!(plan["totalOut"].as_u64().unwrap() > best["out"].as_u64().unwrap());
    assert!(best["gainPct"].as_f64().unwrap() > 0.0);
}

#[tokio::test]
async fn a_fixture_plan_carries_no_call_and_a_testnet_plan_does() {
    let (_, fixture) =
        post("/api/route", serde_json::json!({ "world": "test-world", "amountIn": 1_000_000 })).await;
    assert!(fixture["call"].is_null(), "nothing to send a transaction to");

    let (_, testnet) =
        post("/api/route", serde_json::json!({ "world": "sui-testnet", "amountIn": 1_000_000 })).await;
    let call = &testnet["call"];
    assert!(!call.is_null());
    assert!(call["router_package"].as_str().unwrap().starts_with("0x"));
    // Without a treasury the page could not mint the input it spends.
    assert_eq!(call["mint_symbol"], "TUSD");
    assert!(call["mint_treasury"].as_str().unwrap().starts_with("0x"));

    for leg in call["legs"].as_array().unwrap() {
        assert!(leg["object"].as_str().unwrap().starts_with("0x"));
        assert_eq!(leg["type_args"].as_array().unwrap().len(), 2);
    }
}

// -------------------------------------------------------------------------- //
// Input the page should never send, and a caller might                       //
// -------------------------------------------------------------------------- //

#[tokio::test]
async fn a_zero_order_is_refused_rather_than_planned() {
    let (status, body) =
        post("/api/route", serde_json::json!({ "world": "test-world", "amountIn": 0 })).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("amountIn"));
}

#[tokio::test]
async fn slippage_past_a_hundred_percent_is_refused() {
    let (status, body) = post(
        "/api/route",
        serde_json::json!({ "world": "test-world", "amountIn": 1_000, "slippageBps": 10_001 }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("slippageBps"));
}

#[tokio::test]
async fn an_unknown_world_names_itself_in_the_error() {
    let (status, body) =
        post("/api/route", serde_json::json!({ "world": "mainnet", "amountIn": 1_000 })).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("mainnet"));
}

// -------------------------------------------------------------------------- //
// Curves                                                                     //
// -------------------------------------------------------------------------- //

#[tokio::test]
async fn the_curve_samples_every_venue_and_the_split_at_the_same_sizes() {
    let (status, body) = get("/api/curve?world=test-world&max=1000000&points=12").await;
    assert_eq!(status, StatusCode::OK);

    let sizes = body["sizes"].as_array().unwrap();
    assert!(sizes.len() > 1 && sizes.len() <= 12);
    // Log-spaced and strictly increasing, which the chart's x scale assumes.
    let xs: Vec<u64> = sizes.iter().map(|s| s.as_u64().unwrap()).collect();
    assert!(xs.windows(2).all(|w| w[0] < w[1]), "sizes ascend: {xs:?}");

    for series in body["venues"].as_array().unwrap() {
        assert_eq!(series["points"].as_array().unwrap().len(), xs.len());
    }
    // One index serves every series in the tooltip, so the route must line up.
    assert_eq!(body["route"].as_array().unwrap().len(), xs.len());
}

// -------------------------------------------------------------------------- //
// What the repository says about itself                                      //
// -------------------------------------------------------------------------- //

#[tokio::test]
async fn the_corpus_counts_come_from_the_committed_files() {
    let (status, body) = get("/api/difftest").await;
    assert_eq!(status, StatusCode::OK);

    // The numbers the README quotes. Counted at request time, so if a corpus is
    // regenerated smaller this fails rather than the page quietly disagreeing
    // with the prose.
    assert_eq!(body["formulaCases"].as_u64().unwrap(), 3_029);
    assert_eq!(body["scenarios"].as_u64().unwrap(), 150);
    assert_eq!(body["plans"].as_u64().unwrap(), 25);

    // A formula suite packs many checks into one test function; a scenario
    // suite is one test per pool or book. Conflating them is the bug this
    // endpoint had once.
    for suite in body["suites"].as_array().unwrap() {
        let sui = &suite["sui"];
        match suite["kind"].as_str().unwrap() {
            "formula" => assert_eq!(sui["cases"], sui["asserts"]),
            _ => assert_eq!(sui["cases"], sui["tests"]),
        }
    }
}

#[tokio::test]
async fn the_formula_corpora_are_byte_identical_across_the_two_trees() {
    let (_, body) = get("/api/difftest").await;
    for suite in body["suites"].as_array().unwrap() {
        if suite["kind"] == "formula" {
            assert_eq!(
                suite["identical"], true,
                "{} is emitted once and written to both trees",
                suite["venue"]
            );
        }
    }
}

#[tokio::test]
async fn both_chains_deployments_are_reported() {
    let (status, body) = get("/api/deployments").await;
    assert_eq!(status, StatusCode::OK);

    assert!(!body["sui"]["testnet"].is_null());
    assert!(!body["aptos"]["testnet"].is_null(), "the Aptos testnet run is recorded");

    // Aptos Explorer shows mainnet unless the network is named, so this suffix
    // is what stops every Aptos link pointing at the wrong chain.
    assert_eq!(body["explorers"]["aptosSuffix"], "?network=testnet");
}

#[tokio::test]
async fn health_reports_whether_this_deployment_can_read_the_chain() {
    let (status, body) = get("/api/health").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["ok"], true);
    // Whatever the answer is here, it has to agree with what refresh would do;
    // the page hides its refresh control on the strength of this field.
    assert_eq!(body["canRefresh"].as_bool().unwrap(), repo::can_refresh(&root()));
}
