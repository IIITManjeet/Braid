#!/usr/bin/env bash
# Serve Braid's web front end.
#
#   bash scripts/web.sh           # API on :8080, page on http://localhost:3000
#   bash scripts/web.sh --dev     # same, but with Next's hot reloading
#
# Two processes, because they are two different things: `braid-server` is the
# Rust API wrapping `braid-quote` and `braid-route`, and `web/` is the Next.js
# app that draws it. Next proxies /api/* to the API, so the page is
# same-origin and no CORS is involved. Both are stopped together on ctrl-c.
#
# The API is built in release by default: the route explorer's curve chart
# plans an order at ~44 sizes per request, and an unoptimised `optimize` turns
# a fifth of a second into several. Pass --debug for a faster rebuild while
# editing the Rust.
#
# `Refresh chain` in the page shells out to `scripts/route.py snapshot`, which
# needs the Sui CLI on PATH -- `scripts/get-sui.sh` vendors it into .tools/.
# Without it the page still works against the committed snapshot and the
# offline router test world.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.tools:$PATH"

API_PORT="${BRAID_API_PORT:-8080}"
profile=(--release)
next_cmd=start

for arg in "$@"; do
  case "$arg" in
    --debug) profile=() ;;
    --dev)   next_cmd=dev ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

for tool in cargo npm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool not on PATH" >&2; exit 1; }
done

if [ ! -d "$ROOT/web/node_modules" ]; then
  echo "installing web dependencies..."
  (cd "$ROOT/web" && npm install --no-audit --no-fund)
fi

# `next start` serves a build; `next dev` compiles on demand.
#
# The /api/* rewrite is baked into the build, not read at runtime, so a build
# made against one API port keeps pointing at it. Record which port a build was
# made for and rebuild when it changes, or a stale .next silently proxies
# somewhere nothing is listening.
stamp="$ROOT/web/.next/.braid-api-port"
if [ "$next_cmd" = start ]; then
  if [ ! -d "$ROOT/web/.next" ] || [ "$(cat "$stamp" 2>/dev/null || true)" != "$API_PORT" ]; then
    echo "building the page for API port $API_PORT..."
    (cd "$ROOT/web" && BRAID_API="http://127.0.0.1:$API_PORT" npm run build)
    echo "$API_PORT" > "$stamp"
  fi
fi

echo "building braid-server..."
(cd "$ROOT/node" && cargo build "${profile[@]}" -q -p braid-server)

api_pid=""
cleanup() {
  [ -n "$api_pid" ] && kill "$api_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(cd "$ROOT/node" && cargo run "${profile[@]}" -q -p braid-server -- --root "$ROOT" --port "$API_PORT") &
api_pid=$!

# Give the API a moment so the first page load does not race it.
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$API_PORT/api/health" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

echo
echo "  API   http://127.0.0.1:$API_PORT"
echo "  page  http://localhost:3000"
echo

cd "$ROOT/web"
BRAID_API="http://127.0.0.1:$API_PORT" npm run "$next_cmd"
