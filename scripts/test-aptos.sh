#!/usr/bin/env bash
# Run every Aptos Move package's test suite -- the phase-2 port of move/sui.
#
# Kept separate from scripts/test.sh rather than folded into it: the two chains
# need different compilers, and a machine set up for one is not necessarily set
# up for the other. `bash scripts/test.sh && bash scripts/test-aptos.sh` is the
# full sweep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.tools:$PATH"

if ! command -v aptos >/dev/null 2>&1; then
  echo "aptos not on PATH -- run scripts/get-aptos.sh first" >&2
  exit 1
fi

failed=0
for pkg in "$ROOT"/move/aptos/*/; do
  [ -f "$pkg/Move.toml" ] || continue
  name="$(basename "$pkg")"
  echo "=== $name ==="
  # `--dev` is not optional: every package addresses itself as `_`, which only
  # [dev-addresses] resolves. Without it the compiler refuses the package.
  if ! (cd "$pkg" && aptos move test --dev --skip-fetch-latest-git-deps); then
    failed=1
  fi
  echo
done

exit "$failed"
