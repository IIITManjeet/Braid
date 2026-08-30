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

exit "$failed"
