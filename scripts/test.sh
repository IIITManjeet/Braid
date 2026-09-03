#!/usr/bin/env bash
# Run every Move package's test suite. Each move/sui/* directory is its own
# package, so there is no workspace-wide `test` to lean on.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.tools:$PATH"

if ! command -v sui >/dev/null 2>&1; then
  echo "sui not on PATH -- run scripts/get-sui.sh first" >&2
  exit 1
fi

failed=0
for pkg in "$ROOT"/move/sui/*/; do
  [ -f "$pkg/Move.toml" ] || continue
  name="$(basename "$pkg")"
  echo "=== $name ==="
  if ! sui move test --path "$pkg"; then
    failed=1
  fi
  echo
done

# The Rust replica: its own unit tests, and the source of the differential
# cases the Move suites above just ran.
if command -v cargo >/dev/null 2>&1; then
  echo "=== rust (braid-quote) ==="
  if ! (cd "$ROOT/node" && cargo test --quiet); then
    failed=1
  fi
  echo
else
  echo "cargo not found -- skipping the Rust replica tests" >&2
fi

exit "$failed"
