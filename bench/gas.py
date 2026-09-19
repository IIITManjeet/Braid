#!/usr/bin/env python3
"""Gas per venue, measured the same way on both chains.

    python bench/gas.py aptos [--network local] [amount]   # executes, on Aptos
    python bench/gas.py sui [amount]                       # dry-runs, on Sui testnet

Every measurement is a route through `braid_router`, so the chains are doing
the same work: an empty route (begin, finish, pay out -- the router's own
overhead), one single-leg route per venue, and one route splitting the amount
four ways. A venue's own cost is its single-leg row minus the empty one.

Aptos transactions really execute, against the venues `scripts/aptos.py seed`
built. Sui ones are dry runs of the PTB `scripts/route.py` would send, against
the live testnet pools: the chain computes the effects, charges nothing, and
changes nothing.

The two chains' units do not compare. Aptos reports gas units at a price in
octas; Sui reports MIST, split into computation, storage paid and storage
rebated, and the net of the three is the fee. The comparison worth making is
between rows of one table.

Results land in bench/results/gas-<chain>.json.
"""

import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
RESULTS = os.path.join(ROOT, "bench", "results")

VENUES = ["cpmm", "stable", "clmm", "clob"]


def shapes(amount):
    """(label, [cpmm, stable, clmm, clob]) for every route measured."""
    rows = [("empty route", [0, 0, 0, 0])]
    for i, venue in enumerate(VENUES):
        legs = [0, 0, 0, 0]
        legs[i] = amount
        rows.append((venue, legs))
    rows.append(("all four", [amount // 4] * 4))
    return rows


def save(chain, meta, rows):
    os.makedirs(RESULTS, exist_ok=True)
    path = os.path.join(RESULTS, f"gas-{chain}.json")
    with open(path, "w", newline="\n") as f:
        json.dump({**meta, "rows": rows}, f, indent=2)
        f.write("\n")
    print(f"\nwritten to {os.path.relpath(path, ROOT)}")


# ---------------------------------------------------------------------------- #
# Aptos                                                                        #
# ---------------------------------------------------------------------------- #

def aptos_gas(network, amount):
    import aptos as A
    A.NETWORK = network
    d = A.load_record()
    if "venues" not in d:
        raise SystemExit(f"no venues on {network} -- run: python scripts/aptos.py --network {network} all")
    addrs = {name: p["address"] for name, p in d["packages"].items()}
    venues = d["venues"]
    tusd, teth = A.coin_types(addrs)
    _, rest_url = A.publisher()
    A.ensure_trader(rest_url)
    script = A.compiled_script(addrs, "route_a_to_b")

    rows = []
    print(f"Aptos {network}, {amount} TUSD per measured route\n")
    print(f"| {'route':<12} | {'gas units':>9} | {'over empty':>10} | {'fee (octas)':>11} |")
    print(f"|{'-' * 14}|{'-' * 11}|{'-' * 12}|{'-' * 13}|")
    base = None
    for label, legs in shapes(amount):
        if sum(legs):
            A.run(A.trader_profile(), f"{addrs['braid_test_coins']}::tusd::mint_to_sender", f"u64:{sum(legs)}")
        r = A.run_script(
            A.trader_profile(), script,
            *(f"address:{venues[v]}" for v in VENUES),
            *(f"u64:{a}" for a in legs), "u64:0",
            type_args=(tusd, teth),
        )
        tx, _ = A.tx_events(rest_url, r["transaction_hash"])
        units, price = int(tx["gas_used"]), int(tx["gas_unit_price"])
        base = units if base is None else base
        rows.append({"route": label, "legs": legs, "gasUnits": units, "gasUnitPrice": price,
                     "tx": r["transaction_hash"]})
        print(f"| {label:<12} | {units:>9} | {units - base:>10} | {units * price:>11} |")
    save(f"aptos-{network}", {"chain": "aptos", "network": network, "amount": amount}, rows)


# ---------------------------------------------------------------------------- #
# Sui                                                                          #
# ---------------------------------------------------------------------------- #

def sui_dry_run(args, label):
    """`(computation, storage, rebate)` in MIST from a dry run's report.

    CLI 1.78 ignores `--json` on a dry run and prints only the rendered
    report -- the same gap the README notes for `--dev-inspect` -- so the gas
    summary is read off the text.
    """
    path = os.path.join(ROOT, ".tools") + os.pathsep + os.environ.get("PATH", "")
    exe = shutil.which("sui", path=path)
    out = subprocess.run([exe, *map(str, args)], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout
    if "execution status: success" not in out:
        raise SystemExit(f"{label}: dry run failed\n{out[-2000:]}")
    cost = lambda what: int(re.search(rf"{what}: (\d+) MIST", out).group(1))
    return cost("Computation Cost"), cost("Storage Cost"), cost("Storage Rebate")


def sui_gas(amount):
    import route as R
    d = R.deployments()
    pools = d["pools"]
    coins = d["braid_test_coins"]["packageId"]
    router = d["braid_router"]["packageId"]
    treasury = d["testCoinTreasuries"]["TUSD"]
    tusd, teth = f"{coins}::tusd::TUSD", f"{coins}::teth::TETH"
    taker = R.taker_address()
    legs_by_venue = [
        ("cpmm_a_to_b", f"<{tusd},{teth}>", pools["cpmm_TUSD_TETH"]["poolId"]),
        ("stable_a_to_b", f"<{tusd},{teth}>", pools["stable_TUSD_TETH"]["poolId"]),
        ("clmm_a_to_b", f"<{tusd},{teth}>", pools["clmm_TUSD_TETH"]["poolId"]),
        ("clob_quote_to_base", f"<{teth},{tusd}>", pools["clob_TETH_TUSD"]["marketId"]),
    ]

    rows = []
    print(f"Sui testnet (dry run), {amount} TUSD per measured route\n")
    # Computation is charged in buckets, and a swap never leaves the smallest
    # one; what differs between venues is storage -- the objects a leg writes
    # are re-stored and their previous deposit rebated. So the column that
    # means something is net: computation + storage - rebate.
    print(f"| {'route':<12} | {'computation':>11} | {'storage':>9} | {'rebate':>9} | {'net':>9} | {'over empty':>10} |")
    print(f"|{'-' * 14}|{'-' * 13}|{'-' * 11}|{'-' * 11}|{'-' * 11}|{'-' * 12}|")
    base = None
    for label, legs in shapes(amount):
        # An empty route still needs a coin to open with; zero is a valid mint.
        args = [
            "client", "ptb", "--sender", f"@{taker}",
            "--move-call", f"{coins}::tusd::mint", f"@{treasury}", sum(legs), "--assign", "coin",
            "--move-call", f"{router}::route::begin", f"<{tusd},{teth}>", "coin", 0, "--assign", "route",
        ]
        for (fn, types, obj), a in zip(legs_by_venue, legs):
            if a:
                args += ["--move-call", f"{router}::route::{fn}", types, "route", f"@{obj}", a]
        args += [
            "--move-call", f"{router}::route::finish", f"<{tusd},{teth}>", "route", "--assign", "done",
            "--transfer-objects", "[done.0, done.1]", f"@{taker}",
            "--dry-run",
        ]
        comp, storage, rebate = sui_dry_run(args, label)
        net = comp + storage - rebate
        base = net if base is None else base
        rows.append({"route": label, "legs": legs, "computationCost": comp,
                     "storageCost": storage, "storageRebate": rebate, "net": net})
        print(f"| {label:<12} | {comp:>11} | {storage:>9} | {rebate:>9} | {net:>9} | {net - base:>10} |")
    save("sui-testnet", {"chain": "sui", "network": "testnet", "amount": amount, "dryRun": True}, rows)


def main():
    args = sys.argv[1:]
    network = "testnet"
    if "--network" in args:
        i = args.index("--network")
        network = args[i + 1]
        del args[i:i + 2]
    if not args or args[0] not in ("aptos", "sui"):
        print(__doc__)
        return 1
    amount = int(args[1]) if len(args) > 1 else 100_000
    if args[0] == "aptos":
        aptos_gas(network, amount)
    else:
        sui_gas(amount)
    return 0


if __name__ == "__main__":
    sys.exit(main())
