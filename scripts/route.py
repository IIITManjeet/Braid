#!/usr/bin/env python3
"""Route one TUSD -> TETH order across all four live venues.

    python scripts/route.py snapshot out/snapshot.json
    cargo run -p braid-route -- out/snapshot.json 2000000 0 out/plan.json   (from node/)
    python scripts/route.py execute out/plan.json

or all three in one go:

    python scripts/route.py run 2000000 [slippage_bps]

The split is decided in Rust (`braid-route`), against a snapshot of exactly the
state each venue prices from: reserves for the two pools, the scalar fields and
every initialized tick for the concentrated pool, and each price level's total
for the book. This script only reads that state and executes the plan.

Dynamic fields -- ticks, book levels -- are decoded from the BCS the CLI
returns with its field listing, so a snapshot is a handful of calls however
many ticks or levels there are.

The route is sent from the `braid-taker` address, not the deployer. The book
leg trades as the transaction sender, and the deployer owns the resting asks:
routing from it would be a self-trade, which the book refuses.
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEPLOYMENTS = os.path.join(ROOT, "deployments", "testnet.json")
TOOLS = os.path.join(ROOT, ".tools")
TAKER_ALIAS = "braid-taker"


def sui(*args):
    path = TOOLS + os.pathsep + os.environ.get("PATH", "")
    # Resolved explicitly: on Windows, subprocess looks the program up on the
    # parent's PATH, not the one handed to the child.
    exe = shutil.which("sui", path=path)
    if exe is None:
        raise SystemExit("sui not found -- run scripts/get-sui.sh")
    out = subprocess.run([exe, *args], capture_output=True, text=True, env=dict(os.environ, PATH=path))
    raw = out.stdout
    i = raw.find("{")
    if i < 0:
        raise SystemExit(f"sui {' '.join(args[:3])} failed:\n{out.stdout}\n{out.stderr}")
    return json.loads(raw[i:])


def deployments():
    with open(DEPLOYMENTS) as f:
        return json.load(f)


def signed(bits, width):
    return bits - (1 << width) if bits >= 1 << (width - 1) else bits


def fields(table_id, size):
    """Every dynamic field under a table, as raw BCS bytes."""
    if int(size) == 0:
        return []
    listing = sui("client", "dynamic-field", table_id, "--limit", str(max(int(size), 1)), "--json")
    rows = listing["dynamicFields"]
    if len(rows) != int(size):
        raise SystemExit(f"table {table_id}: listed {len(rows)} of {size} fields")
    return [base64.b64decode(r["fieldObject"]["contents"]["value"]) for r in rows]


def le(b, offset, n):
    return int.from_bytes(b[offset:offset + n], "little")


# --------------------------------------------------------------------------- #
# Snapshot                                                                    #
# --------------------------------------------------------------------------- #

def snapshot():
    d = deployments()
    pools = d["pools"]
    coins = d["braid_test_coins"]["packageId"]
    tusd, teth = f"{coins}::tusd::TUSD", f"{coins}::teth::TETH"
    venues = []

    # Constant product, Pool<TUSD, TETH>: TUSD in is A -> B.
    c = sui("client", "object", pools["cpmm_TUSD_TETH"]["poolId"], "--json")["content"]
    venues.append({
        "kind": "cpmm", "object": c["id"], "a_to_b": True,
        "reserve_in": c["reserve_a"], "reserve_out": c["reserve_b"], "fee_bps": c["fee_bps"],
    })

    # StableSwap, StablePool<TUSD, TETH>.
    c = sui("client", "object", pools["stable_TUSD_TETH"]["poolId"], "--json")["content"]
    venues.append({
        "kind": "stable", "object": c["id"], "a_to_b": True,
        "reserve_in": c["reserve_a"], "reserve_out": c["reserve_b"],
        "amp": c["amp"], "fee_bps": c["fee_bps"],
    })

    # Concentrated, Pool<TUSD, TETH>. Field<u32, TickInfo>: 32 id, 4 name,
    # then liquidity_gross u128, liquidity_net bits u128, two u256, a bool.
    c = sui("client", "object", pools["clmm_TUSD_TETH"]["poolId"], "--json")["content"]
    ticks = []
    for b in fields(c["ticks"]["id"], c["ticks"]["size"]):
        ticks.append([signed(le(b, 32, 4), 32), str(le(b, 36, 16)), str(signed(le(b, 52, 16), 128))])
    venues.append({
        "kind": "clmm", "object": c["id"], "a_to_b": True,
        # The CLI renders some integers as floats; these fit a double exactly.
        "sqrt_price": c["sqrt_price"], "tick": signed(int(float(c["current_tick"]["bits"])), 32),
        "liquidity": c["liquidity"], "fee_bps": c["fee_bps"],
        "tick_spacing": int(float(c["tick_spacing"])), "ticks": ticks,
    })

    # The book, Market<TETH, TUSD>: TUSD in buys base. Each crit-bit leaf is
    # Field<u64, Leaf<Level>>: 32 id, 8 name, key u64, then Level's total u64.
    c = sui("client", "object", pools["clob_TETH_TUSD"]["marketId"], "--json")["content"]
    book = c["book"]
    level = lambda b: [le(b, 40, 8), le(b, 48, 8)]
    venues.append({
        "kind": "clob", "object": c["id"], "buy_base": True,
        "tick_size": c["tick_size"], "lot_size": c["lot_size"], "taker_fee_bps": c["taker_fee_bps"],
        "asks": [level(b) for b in fields(book["asks"]["leaves"]["id"], book["asks"]["leaves"]["size"])],
        "bids": [level(b) for b in fields(book["bids"]["leaves"]["id"], book["bids"]["leaves"]["size"])],
    })

    return {
        "router_package": d["braid_router"]["packageId"],
        "coin_in": tusd,
        "coin_out": teth,
        "venues": venues,
    }


# --------------------------------------------------------------------------- #
# Execute                                                                     #
# --------------------------------------------------------------------------- #

def taker_address():
    for row in sui("client", "addresses", "--json")["addresses"]:
        if row[0] == TAKER_ALIAS:
            return row[1]
    raise SystemExit(f"no `{TAKER_ALIAS}` key in the keystore")


def execute(plan):
    d = deployments()
    coins = d["braid_test_coins"]["packageId"]
    treasury = d["testCoinTreasuries"]["TUSD"]
    router = plan["router_package"]
    pair = f"<{plan['coin_in']},{plan['coin_out']}>"
    taker = taker_address()

    args = [
        "client", "ptb", "--sender", f"@{taker}",
        "--move-call", f"{coins}::tusd::mint", f"@{treasury}", plan["amount_in"], "--assign", "coin",
        "--move-call", f"{router}::route::begin", pair, "coin", plan["min_out"], "--assign", "route",
    ]
    for leg in plan["legs"]:
        types = f"<{leg['type_args'][0]},{leg['type_args'][1]}>"
        args += ["--move-call", f"{router}::route::{leg['function']}", types, "route", f"@{leg['object']}", leg["amount"]]
    args += [
        "--move-call", f"{router}::route::finish", pair, "route", "--assign", "done",
        "--transfer-objects", "[done.0, done.1]", f"@{taker}",
        "--json",
    ]
    result = sui(*args)

    status = result["effects"]["status"]
    print("status :", status)
    print("digest :", result.get("digest"))
    if status.get("status") != "success":
        raise SystemExit(1)

    legs = [e["parsedJson"] for e in result["events"] if e["type"].endswith("::route::LegExecuted")]
    routed = [e["parsedJson"] for e in result["events"] if e["type"].endswith("::route::Routed")][0]
    names = {0: "cpmm", 1: "stable", 2: "clmm", 3: "clob"}

    print(f"\n{'venue':<8} {'in (plan)':>12} {'in (chain)':>12} {'out (plan)':>12} {'out (chain)':>12}")
    all_match = True
    for want, got in zip(plan["legs"], legs):
        match = want["expected_spent"] == got["amount_in"] and want["expected_out"] == got["amount_out"]
        all_match &= match
        print(f"{names[int(got['venue'])]:<8} {want['expected_spent']:>12} {got['amount_in']:>12} "
              f"{want['expected_out']:>12} {got['amount_out']:>12}  {'ok' if match else 'MISMATCH'}")
    total_match = routed["amount_out"] == plan["expected_out"] and routed["unspent"] == plan["expected_unspent"]
    all_match &= total_match and len(legs) == len(plan["legs"])
    print(f"{'total':<8} {'':>12} {'':>12} {plan['expected_out']:>12} {routed['amount_out']:>12}  "
          f"{'ok' if total_match else 'MISMATCH'}")
    print(f"unspent  plan {plan['expected_unspent']}, chain {routed['unspent']}; min_out {routed['min_out']}")
    print("\nchain matches the plan exactly" if all_match else "\nchain DIFFERS from the plan")
    return result, legs, routed, all_match


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = sys.argv[1]
    if cmd == "snapshot":
        with open(sys.argv[2], "w", newline="\n") as f:
            json.dump(snapshot(), f, indent=2)
        print("snapshot written to", sys.argv[2])
    elif cmd == "execute":
        with open(sys.argv[2]) as f:
            execute(json.load(f))
    elif cmd == "run":
        amount = sys.argv[2]
        slippage = sys.argv[3] if len(sys.argv) > 3 else "0"
        work = tempfile.mkdtemp(prefix="braid-route-")
        snap, plan_path = os.path.join(work, "snapshot.json"), os.path.join(work, "plan.json")
        with open(snap, "w", newline="\n") as f:
            json.dump(snapshot(), f, indent=2)
        subprocess.run(
            ["cargo", "run", "-q", "-p", "braid-route", "--", snap, amount, slippage, plan_path],
            cwd=os.path.join(ROOT, "node"), check=True,
        )
        print()
        with open(plan_path) as f:
            plan = json.load(f)
        _, _, _, ok = execute(plan)
        print("\nsnapshot:", snap, "\nplan    :", plan_path)
        return 0 if ok else 1
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
