#!/usr/bin/env python3
"""Deploy Braid to Aptos and route one order across the four venues.

    python scripts/aptos.py publish        # every package, one address each
    python scripts/aptos.py seed           # mint test coins, build the venues
    python scripts/aptos.py route 8000000  # plan offline, execute, compare
    python scripts/aptos.py all 8000000    # the three in order

Add `--network local` to run the same thing against `aptos node run-localnet`;
the default is testnet. The publisher is the `braid-<network>` profile in
`.aptos/config.yaml` (`aptos init --profile braid-testnet --network testnet`).
On testnet it needs APT, which the faucet only hands out through a browser now:
https://aptos.dev/network/faucet. On a localnet, `aptos account fund-with-faucet`.

# One address per package

Aptos keys a module by `(address, name)`, and `braid_cpmm`, `braid_stable` and
`braid_clmm` each have a module called `pool`. Published under one account, the
second is refused with `EMODULE_NAME_CLASH`. So each package goes to its own
resource account, derived from the publisher with the package name as seed.
The publisher pays for all of them and nobody holds their keys -- the signer
capability is discarded at publish, which also makes the packages immutable.

That is the shape Sui gives for free, where every package gets its own id, and
it is the reason the manifests give every named address a distinct dev value.

# Why `route` is a check and not a demo

`seed` builds `braid_router::test_world` on chain with the `seed_world` script:
the same four venues, seeded the same way. `braid-route --test-world` plans
against its Rust copy of that world *before* anything is sent, the order goes
out with `min_out` equal to the predicted total, and every leg's `LegExecuted`
event is compared with the prediction. A one-unit shortfall aborts on chain.
Before sending, the venues' `#[view]` quotes are compared with the plan too.

The route is sent from a second profile, `braid-<network>-trader`, which `seed`
creates and funds. The book's only maker is the publisher, and a taker trading
against their own resting orders is a self-trade, which the book refuses.

Everything learned goes into deployments/aptos-<network>.json.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, ".tools")

# Dependency order: each package's imports are already on chain when it lands.
# The second field is a module that proves the package is published.
PACKAGES = [
    ("braid_math", "full_math"),
    ("braid_cpmm", "pool"),
    ("braid_stable", "pool"),
    ("braid_clmm", "pool"),
    ("braid_clob", "market"),
    ("braid_router", "route"),
    ("braid_test_coins", "tusd"),
]

VENUES = ["cpmm", "stable", "clmm", "clob"]

NETWORK = "testnet"


def publisher_profile():
    return f"braid-{NETWORK}"


def trader_profile():
    return f"braid-{NETWORK}-trader"


def record_path():
    return os.path.join(ROOT, "deployments", f"aptos-{NETWORK}.json")


# ---------------------------------------------------------------------------- #
# Plumbing                                                                     #
# ---------------------------------------------------------------------------- #

def aptos(*args, check=True):
    path = TOOLS + os.pathsep + os.environ.get("PATH", "")
    # Resolved explicitly: on Windows, subprocess looks the program up on the
    # parent's PATH, not the one handed to the child.
    exe = shutil.which("aptos", path=path)
    if exe is None:
        raise SystemExit("aptos not found -- run scripts/get-aptos.sh")
    out = subprocess.run(
        [exe, *map(str, args)], capture_output=True, text=True, cwd=ROOT,
        env=dict(os.environ, PATH=path), stdin=subprocess.DEVNULL,
    )
    raw = out.stdout
    i = raw.find("{")
    if i < 0:
        raise SystemExit(f"aptos {' '.join(map(str, args[:3]))} failed:\n{out.stdout}\n{out.stderr}")
    result = json.loads(raw[i:])
    if check and "Error" in result:
        raise SystemExit(f"aptos {' '.join(map(str, args[:3]))}: {result['Error']}")
    return result


def profile(name):
    """(address, rest_url) for a profile in .aptos/config.yaml, or None."""
    path = os.path.join(ROOT, ".aptos", "config.yaml")
    if not os.path.exists(path):
        return None
    text = open(path).read()
    m = re.search(rf"^  {re.escape(name)}:\n((?:    .*\n?)+)", text, re.M)
    if not m:
        return None
    body = m.group(1)
    account = re.search(r"account: (\w+)", body).group(1)
    rest_url = re.search(r'rest_url: "?([^"\n]+)', body).group(1).rstrip("/")
    if not rest_url.endswith("/v1"):
        rest_url += "/v1"
    return norm(account), rest_url


def publisher():
    p = profile(publisher_profile())
    if p is None:
        raise SystemExit(
            f"no `{publisher_profile()}` profile -- run: "
            f"aptos init --profile {publisher_profile()} --network {NETWORK}")
    return p


def norm(addr):
    """Long-form address. The REST API and the CLI disagree on leading zeros."""
    return "0x" + format(int(addr, 16), "064x")


def rest(url):
    for attempt in range(6):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 429 and attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise


def balance(address, rest_url):
    body = json.dumps({
        "function": "0x1::coin::balance",
        "type_arguments": ["0x1::aptos_coin::AptosCoin"],
        "arguments": [address],
    }).encode()
    req = urllib.request.Request(rest_url + "/view", data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return int(json.load(r)[0])
    except urllib.error.HTTPError:
        return 0   # no account yet


def sequence_number(account, rest_url):
    info = rest(f"{rest_url}/accounts/{account}")
    return int(info["sequence_number"]) if info else 0


def sent_at(account, rest_url, seq):
    """The committed transaction `account` sent with sequence number `seq`."""
    for _ in range(30):
        txs = rest(f"{rest_url}/accounts/{account}/transactions?start={seq}&limit=1")
        if txs:
            return txs[0]
        time.sleep(1)
    raise SystemExit(f"transaction {seq} from {account} never landed")


def load_record():
    try:
        with open(record_path()) as f:
            return json.load(f)
    except OSError:
        return {}


def save_record(d):
    os.makedirs(os.path.dirname(record_path()), exist_ok=True)
    with open(record_path(), "w", newline="\n") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")


def tx_events(rest_url, tx_hash):
    for _ in range(30):
        tx = rest(f"{rest_url}/transactions/by_hash/{tx_hash}")
        if tx and tx.get("type") != "pending_transaction":
            if not tx.get("success"):
                raise SystemExit(f"{tx_hash} failed: {tx.get('vm_status')}")
            return tx, tx["events"]
        time.sleep(1)
    raise SystemExit(f"{tx_hash} never landed")


def events_of(events, module_addr, suffix):
    """Event payloads of type `<module_addr>::<suffix>`."""
    out = []
    for e in events:
        addr, _, rest_of_type = e["type"].partition("::")
        if rest_of_type == suffix and norm(addr) == norm(module_addr):
            out.append(e["data"])
    return out


def run(profile_name, function_id, *args, type_args=()):
    cmd = ["move", "run", "--function-id", function_id, "--profile", profile_name, "--assume-yes"]
    if type_args:
        cmd += ["--type-args", *type_args]
    if args:
        cmd += ["--args", *args]
    return aptos(*cmd)["Result"]


def run_script(profile_name, script, *args, type_args=()):
    cmd = ["move", "run-script", "--compiled-script-path", script,
           "--profile", profile_name, "--assume-yes"]
    if type_args:
        cmd += ["--type-args", *type_args]
    if args:
        cmd += ["--args", *args]
    return aptos(*cmd)["Result"]


def view(function_id, *args, type_args=()):
    cmd = ["move", "view", "--function-id", function_id, "--profile", publisher_profile()]
    if type_args:
        cmd += ["--type-args", *type_args]
    if args:
        cmd += ["--args", *args]
    return aptos(*cmd)["Result"]


# ---------------------------------------------------------------------------- #
# Addresses                                                                    #
# ---------------------------------------------------------------------------- #

def package_addresses(account):
    """Each package's resource-account address, derived from the publisher."""
    out = {}
    for name, _ in PACKAGES:
        derived = aptos("account", "derive-resource-account-address",
                        "--address", account, "--seed", name, "--seed-encoding", "utf8")["Result"]
        out[name] = norm(derived)
    return out


def named_addresses(addrs, skip=None):
    return ",".join(f"{name}={a}" for name, a in addrs.items() if name != skip)


def coin_types(addrs):
    coins = addrs["braid_test_coins"]
    return f"{coins}::tusd::TUSD", f"{coins}::teth::TETH"


# ---------------------------------------------------------------------------- #
# publish                                                                      #
# ---------------------------------------------------------------------------- #

def publish():
    account, rest_url = publisher()
    have = balance(account, rest_url)
    print(f"network   : {NETWORK}")
    print(f"publisher : {account}")
    print(f"balance   : {have} octas")
    if have < 100_000_000:
        raise SystemExit(
            f"\nNot enough APT (have {have} octas, want >= 1 APT). Fund {account} at\n"
            f"  https://aptos.dev/network/faucet?address={account}\nthen re-run."
        )

    addrs = package_addresses(account)
    d = load_record()
    d["_network"] = NETWORK
    d["_publisher"] = account
    packages = d.setdefault("packages", {})
    for name, probe in PACKAGES:
        addr = addrs[name]
        if rest(f"{rest_url}/accounts/{addr}/module/{probe}"):
            print(f"== {name} : already published at {addr}")
            packages.setdefault(name, {"address": addr})
            continue
        print(f"== {name}")
        seq = sequence_number(account, rest_url)
        # This subcommand answers with a bare "Success", not the transaction,
        # so the transaction is looked up by the sequence number it used.
        aptos(
            "move", "create-resource-account-and-publish-package",
            "--seed", name, "--seed-encoding", "utf8",
            "--address-name", name,
            "--package-dir", os.path.join("move", "aptos", name),
            "--named-addresses", named_addresses(addrs, skip=name),
            "--skip-fetch-latest-git-deps",
            "--profile", publisher_profile(), "--assume-yes",
        )
        tx = sent_at(account, rest_url, seq)
        if not tx["success"]:
            raise SystemExit(f"   FAILED: {tx['vm_status']}")
        print(f"   address : {addr}")
        print(f"   tx      : {tx['hash']}")
        print(f"   gas     : {tx['gas_used']} units at {tx['gas_unit_price']}")
        packages[name] = {"address": addr, "tx": tx["hash"], "gasUsed": int(tx["gas_used"])}
        save_record(d)
    save_record(d)


# ---------------------------------------------------------------------------- #
# seed                                                                         #
# ---------------------------------------------------------------------------- #

def compiled_script(addrs, name):
    """Compile braid_router against the live addresses and find one script."""
    aptos(
        "move", "compile",
        "--package-dir", os.path.join("move", "aptos", "braid_router"),
        "--named-addresses", named_addresses(addrs),
        "--skip-fetch-latest-git-deps",
    )
    hits = glob.glob(os.path.join(
        ROOT, "move", "aptos", "braid_router", "build", "braid_router", "bytecode_scripts", f"{name}_*.mv"))
    if len(hits) != 1:
        raise SystemExit(f"expected one compiled {name} script, found {hits}")
    return hits[0]


def ensure_trader(rest_url):
    """The second key, funded by the publisher. Paying APT to an address with
    no account yet creates it, so this works on either network."""
    if profile(trader_profile()) is None:
        aptos("init", "--profile", trader_profile(), "--network", NETWORK, "--assume-yes", check=False)
    trader, _ = profile(trader_profile())
    if balance(trader, rest_url) < 20_000_000:
        r = run(publisher_profile(), "0x1::aptos_account::transfer", f"address:{trader}", "u64:50000000")
        print(f"funded trader {trader}: {r['transaction_hash']}")
    return trader


def seed():
    account, rest_url = publisher()
    d = load_record()
    addrs = {name: p["address"] for name, p in d.get("packages", {}).items()}
    if len(addrs) != len(PACKAGES):
        raise SystemExit("not every package is published -- run: python scripts/aptos.py publish")
    if "venues" in d:
        print("venues already seeded:", json.dumps(d["venues"], indent=2))
        return
    tusd, teth = coin_types(addrs)
    coins = addrs["braid_test_coins"]

    d["_trader"] = ensure_trader(rest_url)
    save_record(d)

    print("minting the publisher's seed coins")
    run(publisher_profile(), f"{coins}::tusd::mint_to_sender", "u64:29200000")
    run(publisher_profile(), f"{coins}::teth::mint_to_sender", "u64:31000000")

    print("seeding the four venues")
    r = run_script(publisher_profile(), compiled_script(addrs, "seed_world"), type_args=(tusd, teth))
    _, events = tx_events(rest_url, r["transaction_hash"])
    d["venues"] = {
        "pair": ["TUSD", "TETH"],
        "seededIn": r["transaction_hash"],
        "gasUsed": r["gas_used"],
        "cpmm": events_of(events, addrs["braid_cpmm"], "pool::PoolCreated")[0]["pool_id"],
        "stable": events_of(events, addrs["braid_stable"], "pool::StablePoolCreated")[0]["pool_id"],
        "clmm": events_of(events, addrs["braid_clmm"], "pool::PoolCreated")[0]["pool_id"],
        "clob": events_of(events, addrs["braid_clob"], "market::MarketCreated")[0]["market_id"],
        "note": "Seeded exactly as braid_router::test_world, so braid-route --test-world predicts this chain.",
    }
    save_record(d)
    print(json.dumps(d["venues"], indent=2))


# ---------------------------------------------------------------------------- #
# route                                                                        #
# ---------------------------------------------------------------------------- #

def plan(amount):
    out = subprocess.run(
        ["cargo", "run", "-q", "-p", "braid-route", "--", "--test-world", str(amount)],
        cwd=os.path.join(ROOT, "node"), capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


def check_views(addrs, venues, p):
    """Each venue's `#[view]` quote at its planned amount, against the replica.

    The concentrated pool has no quote view -- a quote there is the tick walk
    itself -- so its leg is checked only by executing it.
    """
    tusd, teth = coin_types(addrs)
    ok = True
    for name, fid, types in [
        ("cpmm", f"{addrs['braid_cpmm']}::pool::quote_a_for_b", (tusd, teth)),
        ("stable", f"{addrs['braid_stable']}::pool::quote_a_for_b", (tusd, teth)),
        ("clob", f"{addrs['braid_clob']}::market::quote_quote_for_base", (teth, tusd)),
    ]:
        leg = p["legs"].get(name)
        if not leg:
            continue
        got = int(view(fid, f"address:{venues[name]}", f"u64:{leg['amount']}", type_args=types)[0])
        match = got == leg["out"]
        ok &= match
        print(f"  view {name:<7} {leg['amount']:>10} in -> {got:>10} out  (plan {leg['out']})"
              f"  {'ok' if match else 'MISMATCH'}")
    return ok


def route(amount):
    account, rest_url = publisher()
    d = load_record()
    venues = d.get("venues")
    if not venues:
        raise SystemExit("no venues yet -- run: python scripts/aptos.py seed")
    addrs = {name: p["address"] for name, p in d["packages"].items()}
    tusd, teth = coin_types(addrs)
    trader = ensure_trader(rest_url)

    p = plan(amount)
    print(f"plan: {amount} TUSD -> {p['totalOut']} TETH, unspent {p['unspent']}")
    for name in VENUES:
        leg = p["legs"].get(name)
        if leg:
            print(f"  {name:<7} {leg['amount']:>10} in -> {leg['out']:>10} out")

    print("views, before sending:")
    views_ok = check_views(addrs, venues, p)

    run(trader_profile(), f"{addrs['braid_test_coins']}::tusd::mint_to_sender", f"u64:{amount}")
    r = run_script(
        trader_profile(), compiled_script(addrs, "route_a_to_b"),
        f"address:{venues['cpmm']}", f"address:{venues['stable']}",
        f"address:{venues['clmm']}", f"address:{venues['clob']}",
        *(f"u64:{a}" for a in p["amounts"]), f"u64:{p['totalOut']}",
        type_args=(tusd, teth),
    )
    tx_hash = r["transaction_hash"]
    _, events = tx_events(rest_url, tx_hash)
    legs = events_of(events, addrs["braid_router"], "route::LegExecuted")
    routed = events_of(events, addrs["braid_router"], "route::Routed")[0]

    print(f"\ntx {tx_hash}  gas {r['gas_used']}")
    print(f"{'venue':<8} {'in (plan)':>12} {'in (chain)':>12} {'out (plan)':>12} {'out (chain)':>12}")
    all_ok = views_ok
    chain_legs = {}
    for got in legs:
        name = VENUES[int(got["venue"])]
        want = p["legs"][name]
        match = want["spent"] == int(got["amount_in"]) and want["out"] == int(got["amount_out"])
        all_ok &= match
        chain_legs[name] = {"in": int(got["amount_in"]), "out": int(got["amount_out"])}
        print(f"{name:<8} {want['spent']:>12} {got['amount_in']:>12} {want['out']:>12} {got['amount_out']:>12}"
              f"  {'ok' if match else 'MISMATCH'}")
    total_ok = int(routed["amount_out"]) == p["totalOut"] and int(routed["unspent"]) == p["unspent"]
    all_ok &= total_ok and len(legs) == len(p["legs"])
    print(f"{'total':<8} {'':>12} {'':>12} {p['totalOut']:>12} {routed['amount_out']:>12}"
          f"  {'ok' if total_ok else 'MISMATCH'}")
    print("\nchain matches the plan exactly" if all_ok else "\nchain DIFFERS from the plan")

    d.setdefault("routes", []).append({
        "tx": tx_hash,
        "sender": trader,
        "amountIn": amount,
        "minOut": p["totalOut"],
        "amountOut": int(routed["amount_out"]),
        "unspent": int(routed["unspent"]),
        "legs": chain_legs,
        "gasUsed": r["gas_used"],
        "matchesPlan": all_ok,
    })
    save_record(d)
    return 0 if all_ok else 1


def main():
    global NETWORK
    args = sys.argv[1:]
    if "--network" in args:
        i = args.index("--network")
        NETWORK = args[i + 1]
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return 1
    cmd = args[0]
    if cmd == "publish":
        publish()
    elif cmd == "seed":
        seed()
    elif cmd == "route":
        return route(int(args[1]))
    elif cmd == "all":
        publish()
        seed()
        return route(int(args[1]) if len(args) > 1 else 8_000_000)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
