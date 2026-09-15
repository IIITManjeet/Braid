//! The on-chain state a route is planned against, and the plan handed back.
//!
//! `scripts/route.py snapshot` reads the venues from the network and writes a
//! snapshot; this module turns it into `Venue`s, and turns a `Plan` into the
//! exact Move calls `braid_router::route` needs. Numbers may be JSON numbers or
//! strings -- `u128` and `u64` values past 2^53 have to be strings to survive
//! a JSON parser that reads doubles.

use braid_quote::{clmm, clob};
use serde_json::{Value, json};

use crate::{Plan, Venue, min_out};

#[derive(Debug, Clone)]
pub struct VenueRef {
    pub kind: String,
    pub object: String,
    /// For pools: the order trades the pool's A for B. For a book: it buys base.
    pub forward: bool,
}

#[derive(Debug, Clone)]
pub struct Snapshot {
    pub router_package: String,
    pub coin_in: String,
    pub coin_out: String,
    pub venues: Vec<Venue>,
    pub refs: Vec<VenueRef>,
}

fn uint(v: &Value, field: &str) -> Result<u128, String> {
    let x = v.get(field).ok_or_else(|| format!("missing `{field}`"))?;
    match x {
        Value::String(s) => s.parse().map_err(|e| format!("`{field}`: {e}")),
        Value::Number(n) => n.as_u64().map(u128::from).ok_or_else(|| format!("`{field}` is not a u64")),
        _ => Err(format!("`{field}` is not a number")),
    }
}

fn u64_of(v: &Value, field: &str) -> Result<u64, String> {
    u64::try_from(uint(v, field)?).map_err(|_| format!("`{field}` exceeds u64"))
}

fn int_of(v: &Value) -> Result<i128, String> {
    match v {
        Value::String(s) => s.parse().map_err(|e| format!("{e}")),
        Value::Number(n) => n.as_i64().map(i128::from).ok_or_else(|| "not an integer".into()),
        _ => Err("not an integer".into()),
    }
}

fn str_of(v: &Value, field: &str) -> Result<String, String> {
    v.get(field).and_then(Value::as_str).map(str::to_owned).ok_or_else(|| format!("missing `{field}`"))
}

fn bool_of(v: &Value, field: &str) -> Result<bool, String> {
    v.get(field).and_then(Value::as_bool).ok_or_else(|| format!("missing `{field}`"))
}

fn levels(v: &Value, field: &str) -> Result<Vec<(u64, u64)>, String> {
    let arr = v.get(field).and_then(Value::as_array).ok_or_else(|| format!("missing `{field}`"))?;
    arr.iter()
        .map(|pair| {
            let p = pair.as_array().filter(|p| p.len() == 2).ok_or("level is not [price, total]")?;
            Ok((int_of(&p[0])? as u64, int_of(&p[1])? as u64))
        })
        .collect()
}

pub fn parse(text: &str) -> Result<Snapshot, String> {
    let root: Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
    let mut venues = Vec::new();
    let mut refs = Vec::new();

    for v in root.get("venues").and_then(Value::as_array).ok_or("missing `venues`")? {
        let kind = str_of(v, "kind")?;
        let object = str_of(v, "object")?;
        let (venue, forward) = match kind.as_str() {
            "cpmm" => (
                Venue::Cpmm {
                    reserve_in: u64_of(v, "reserve_in")?,
                    reserve_out: u64_of(v, "reserve_out")?,
                    fee_bps: u64_of(v, "fee_bps")?,
                },
                bool_of(v, "a_to_b")?,
            ),
            "stable" => (
                Venue::Stable {
                    reserve_in: u64_of(v, "reserve_in")?,
                    reserve_out: u64_of(v, "reserve_out")?,
                    amp: u64_of(v, "amp")?,
                    fee_bps: u64_of(v, "fee_bps")?,
                },
                bool_of(v, "a_to_b")?,
            ),
            "clmm" => {
                let a_to_b = bool_of(v, "a_to_b")?;
                let ticks = v
                    .get("ticks")
                    .and_then(Value::as_array)
                    .ok_or("missing `ticks`")?
                    .iter()
                    .map(|t| {
                        let t = t.as_array().filter(|t| t.len() == 3).ok_or("tick is not [tick, gross, net]")?;
                        Ok((
                            int_of(&t[0])? as i32,
                            clmm::TickState {
                                liquidity_gross: int_of(&t[1])? as u128,
                                liquidity_net: int_of(&t[2])?,
                            },
                        ))
                    })
                    .collect::<Result<Vec<_>, String>>()?;
                let tick = int_of(v.get("tick").ok_or("missing `tick`")?)? as i32;
                let pool = clmm::Pool::from_snapshot(
                    uint(v, "sqrt_price")?,
                    tick,
                    uint(v, "liquidity")?,
                    u64_of(v, "fee_bps")?,
                    u64_of(v, "tick_spacing")? as u32,
                    ticks,
                );
                (Venue::Clmm { pool, zero_for_one: a_to_b }, a_to_b)
            }
            "clob" => {
                let buy_base = bool_of(v, "buy_base")?;
                let mut book =
                    clob::Book::new(u64_of(v, "tick_size")?, u64_of(v, "lot_size")?, u64_of(v, "taker_fee_bps")?);
                for (p, q) in levels(v, "asks")? {
                    book.rest(p, q, false);
                }
                for (p, q) in levels(v, "bids")? {
                    book.rest(p, q, true);
                }
                let venue = if buy_base { Venue::ClobBuyBase { book } } else { Venue::ClobSellBase { book } };
                (venue, buy_base)
            }
            other => return Err(format!("unknown venue kind `{other}`")),
        };
        venues.push(venue);
        refs.push(VenueRef { kind, object, forward });
    }

    Ok(Snapshot {
        router_package: str_of(&root, "router_package")?,
        coin_in: str_of(&root, "coin_in")?,
        coin_out: str_of(&root, "coin_out")?,
        venues,
        refs,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{fixtures::router_test_world, optimize};

    /// The router test world, written the way `scripts/route.py snapshot`
    /// writes the live one -- big numbers as strings, ticks as raw triples.
    const WORLD: &str = r#"{
      "router_package": "0xR",
      "coin_in": "0xC::usd::USD",
      "coin_out": "0xC::eth::ETH",
      "venues": [
        {"kind": "cpmm", "object": "0x1", "a_to_b": true,
         "reserve_in": 10000000, "reserve_out": "10000000", "fee_bps": 30},
        {"kind": "stable", "object": "0x2", "a_to_b": true,
         "reserve_in": 10000000, "reserve_out": 10000000, "amp": 10000, "fee_bps": 4},
        {"kind": "clmm", "object": "0x3", "a_to_b": true,
         "sqrt_price": "18446744073709551616", "tick": 0, "liquidity": "169187499",
         "fee_bps": 30, "tick_spacing": 60,
         "ticks": [[-600, "169187499", "169187499"], [600, "169187499", "-169187499"]]},
        {"kind": "clob", "object": "0x4", "buy_base": true,
         "tick_size": 100000, "lot_size": 10000, "taker_fee_bps": 10,
         "asks": [[1000100000, 2000000], [1000500000, 2000000], [1001000000, 2000000]],
         "bids": [[999900000, 2000000], [999500000, 2000000]]}
      ]
    }"#;

    #[test]
    fn a_parsed_snapshot_prices_exactly_like_the_fixture() {
        let snap = parse(WORLD).unwrap();
        let fixture = router_test_world();
        for amount in [1_000u64, 250_000, 3_000_000, 20_000_000] {
            for (a, b) in snap.venues.iter().zip(&fixture) {
                assert_eq!(a.quote(amount), b.quote(amount), "{} at {amount}", a.kind());
            }
            assert_eq!(optimize(&snap.venues, amount), optimize(&fixture, amount));
        }
    }

    #[test]
    fn legs_name_the_router_function_and_the_venues_type_order() {
        let snap = parse(WORLD).unwrap();
        let usd = "0xC::usd::USD".to_string();
        let eth = "0xC::eth::ETH".to_string();
        assert_eq!(snap.leg_call(0), ("cpmm_a_to_b".into(), [usd.clone(), eth.clone()]));
        assert_eq!(snap.leg_call(2), ("clmm_a_to_b".into(), [usd.clone(), eth.clone()]));
        // The book is Market<ETH, USD>: buying ETH with USD is quote -> base.
        assert_eq!(snap.leg_call(3), ("clob_quote_to_base".into(), [eth, usd]));
    }
}

impl Snapshot {
    /// The router function and type arguments for a leg through `venue`.
    ///
    /// Every venue fixes its own type order, so the same USD -> ETH order is
    /// `<USD, ETH>` through a `Pool<USD, ETH>` and `<ETH, USD>` through a
    /// `Market<ETH, USD>`.
    pub fn leg_call(&self, venue: usize) -> (String, [String; 2]) {
        let r = &self.refs[venue];
        let forward_types = [self.coin_in.clone(), self.coin_out.clone()];
        let reverse_types = [self.coin_out.clone(), self.coin_in.clone()];
        match (r.kind.as_str(), r.forward) {
            ("clob", true) => ("clob_quote_to_base".into(), reverse_types),
            ("clob", false) => ("clob_base_to_quote".into(), forward_types),
            (kind, true) => (format!("{kind}_a_to_b"), forward_types),
            (kind, false) => (format!("{kind}_b_to_a"), reverse_types),
        }
    }

    pub fn plan_json(&self, plan: &Plan, slippage_bps: u64) -> Value {
        let legs: Vec<Value> = plan
            .legs
            .iter()
            .map(|leg| {
                let (function, types) = self.leg_call(leg.venue);
                json!({
                    "venue": self.refs[leg.venue].kind,
                    "object": self.refs[leg.venue].object,
                    "function": function,
                    "type_args": types,
                    "amount": leg.amount.to_string(),
                    "expected_spent": leg.spent.to_string(),
                    "expected_out": leg.out.to_string(),
                })
            })
            .collect();
        json!({
            "router_package": self.router_package,
            "coin_in": self.coin_in,
            "coin_out": self.coin_out,
            "amount_in": plan.amount_in.to_string(),
            "expected_out": plan.total_out.to_string(),
            "expected_unspent": plan.unspent.to_string(),
            "slippage_bps": slippage_bps,
            "min_out": min_out(plan.total_out, slippage_bps).to_string(),
            "best_single_venue": plan.best_single.map(|(i, out)| json!({
                "venue": self.refs[i].kind,
                "out": out.to_string(),
            })),
            "legs": legs,
        })
    }
}
