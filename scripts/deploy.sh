#!/usr/bin/env bash
# Publish the Braid packages, in dependency order, to whatever network the Sui
# client is currently pointed at.
#
#   bash scripts/deploy.sh              # publish anything not yet published
#   bash scripts/deploy.sh --dry-run    # build only, no transactions
#
# Sui 1.78 tracks publications itself, in each package's Published.toml, and
# resolves a dependency's on-chain address from there. So this script does not
# rewrite any Move.toml -- it publishes in the right order and lets the
# toolchain do the linking. Published.toml is committed; deployments/<env>.json
# is a flat summary for humans and for the Rust node to read.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.tools:$PATH"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# braid_math is unverifiable on chain until it is itself published, so the
# dependants need this on their first publish.
PUBLISH_FLAGS="--skip-dependency-verification"

command -v sui >/dev/null 2>&1 || { echo "sui not on PATH -- run scripts/get-sui.sh" >&2; exit 1; }

ENV_ALIAS="$(sui client active-env)"
ADDRESS="$(sui client active-address)"
OUT_DIR="$ROOT/deployments"
OUT="$OUT_DIR/$ENV_ALIAS.json"
mkdir -p "$OUT_DIR"
[ -f "$OUT" ] || echo '{}' > "$OUT"

echo "network : $ENV_ALIAS"
echo "sender  : $ADDRESS"
echo "record  : $OUT"

if [ "$DRY_RUN" = 0 ]; then
  # `sui client gas --json` returns {"gasCoins":[...]} on 1.78 and a bare list
  # on older releases. Accept either rather than pinning to one CLI version.
  GAS_TOTAL="$(sui client gas --json 2>/dev/null | python -c '
import sys, json
d = json.load(sys.stdin)
coins = d.get("gasCoins", []) if isinstance(d, dict) else d
print(sum(int(c["mistBalance"]) for c in coins))
' 2>/dev/null || echo 0)"
  if [ "${GAS_TOTAL:-0}" -lt 200000000 ]; then
    echo
    echo "Not enough gas (have ${GAS_TOTAL:-0} MIST, want >= 200000000 = 0.2 SUI)." >&2
    echo "Fund $ADDRESS then re-run:" >&2
    echo "  https://faucet.sui.io/?address=$ADDRESS" >&2
    exit 1
  fi
  echo "gas     : $GAS_TOTAL MIST"
fi
echo

# ---------------------------------------------------------------------------- #
# Helpers. Each python block takes its inputs as argv and reads files by path --
# never from stdin, because `python -` with a heredoc consumes stdin for the
# script itself and any piped data is silently lost.
# ---------------------------------------------------------------------------- #

# The address Sui recorded for this package on this network, or empty.
published_at() {
  local toml="$ROOT/move/sui/$1/Published.toml"
  [ -f "$toml" ] || { echo ""; return 0; }
  python - "$toml" "$ENV_ALIAS" <<'PY'
import re, sys
path, env = sys.argv[1], sys.argv[2]
try: s = open(path, encoding="utf-8").read()
except OSError: print(""); raise SystemExit
m = re.search(rf'\[published\.{re.escape(env)}\](.*?)(?=\n\[|\Z)', s, re.S)
if not m: print(""); raise SystemExit
a = re.search(r'published-at\s*=\s*"([^"]+)"', m.group(1))
print(a.group(1) if a else "")
PY
}

record() {
  python - "$OUT" "$1" "$2" "$3" <<'PY'
import json, sys
path, name, pkg, digest = sys.argv[1:5]
try: d = json.load(open(path))
except Exception: d = {}
entry = {"packageId": pkg}
if digest: entry["digest"] = digest
d[name] = entry
with open(path, "w", newline="\n") as f:
    json.dump(d, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

# Pull packageId + digest out of a saved `sui client publish --json` response.
parse_publish() {
  python - "$1" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
i = raw.find("{")
if i < 0:
    print("ERR", " ".join(raw.split())[:300] or "no JSON in response"); raise SystemExit
try:
    d = json.loads(raw[i:])
except Exception as e:
    print("ERR", f"unparseable response: {e}"); raise SystemExit
status = d.get("effects", {}).get("status", {})
if status.get("status") != "success":
    print("ERR", status.get("error", "publish failed")); raise SystemExit
pub = [c for c in d.get("objectChanges", []) if c.get("type") == "published"]
if not pub:
    print("ERR", "no published object in response"); raise SystemExit
print("OK", pub[0]["packageId"], d.get("digest", ""))
PY
}

publish() {
  local name="$1"
  local dir="$ROOT/move/sui/$name"

  if [ "$DRY_RUN" = 1 ]; then
    sui move build --path "$dir" >/dev/null 2>&1
    echo "== $name : builds clean"
    return 0
  fi

  # Published.toml is the source of truth; a re-publish would be refused anyway.
  local existing; existing="$(published_at "$name")"
  if [ -n "$existing" ]; then
    echo "== $name : already published"
    echo "   package : $existing"
    record "$name" "$existing" ""
    echo
    return 0
  fi

  echo "== $name"
  local tmp; tmp="$(mktemp)"
  sui client publish "$dir" $PUBLISH_FLAGS --json >"$tmp" 2>&1 || true

  local parsed; parsed="$(parse_publish "$tmp")"
  rm -f "$tmp"

  if [ "${parsed%% *}" != "OK" ]; then
    echo "   FAILED: ${parsed#ERR }" >&2
    exit 1
  fi

  local pkg digest
  pkg="$(printf '%s' "$parsed" | awk '{print $2}')"
  digest="$(printf '%s' "$parsed" | awk '{print $3}')"

  echo "   package : $pkg"
  echo "   digest  : $digest"
  record "$name" "$pkg" "$digest"
  echo
}

# braid_math is imported by both venues, so it goes first. braid_test_coins is
# independent -- concrete coin types so the generic pools can actually be called.
publish braid_math
publish braid_cpmm
publish braid_stable
publish braid_test_coins

echo "----------------------------------------------------------------"
if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run complete -- every package builds."
else
  cat "$OUT"
  echo
  echo "Explorer: https://suiscan.xyz/$ENV_ALIAS/home"
fi
