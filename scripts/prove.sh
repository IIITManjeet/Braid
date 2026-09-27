#!/usr/bin/env bash
# Run the Move Prover over the specified modules.
#
#   bash scripts/prove.sh
#
# The unit tests and the differential fuzzer check instances -- 3,029 generated
# cases, each a concrete triple of inputs and the answer the Rust replica
# computed. The prover checks the claim for every input the types allow,
# including the ones nobody generated. The two are complements, not substitutes:
# the fuzzer says "these two implementations agree", the prover says "this one
# cannot violate its invariant".
#
# Only the pure math modules are targeted. `pool.move` and the venues pull in
# the Aptos framework, and verifying that whole graph exhausts Boogie's memory
# before it reaches anything interesting; `-f` keeps each run to one module.
#
# Backends: boogie and z3, installed by `aptos update prover-dependencies`.
# On Windows that command downloads boogie and then panics before z3, so z3 may
# need fetching by hand from the Z3Prover/z3 releases page (4.11.2 is known
# good). Point BOOGIE_EXE and Z3_EXE at them if they are not on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.tools:$PATH"

APTOSCLI_BIN="${APTOSCLI_BIN:-$HOME/.aptoscli/bin}"
export BOOGIE_EXE="${BOOGIE_EXE:-$APTOSCLI_BIN/boogie.exe}"
export Z3_EXE="${Z3_EXE:-$APTOSCLI_BIN/z3.exe}"
[ -x "$BOOGIE_EXE" ] || BOOGIE_EXE="$(command -v boogie || true)"
[ -x "$Z3_EXE" ] || Z3_EXE="$(command -v z3 || true)"
export BOOGIE_EXE Z3_EXE

if [ -z "${BOOGIE_EXE:-}" ] || [ -z "${Z3_EXE:-}" ]; then
  echo "boogie or z3 not found -- run: aptos update prover-dependencies" >&2
  exit 1
fi

# package:module-filter
TARGETS="braid_math:full_math braid_math:q64 braid_cpmm:cpmm_math braid_stable:stable_math"

failed=0
for target in $TARGETS; do
  pkg="${target%%:*}"
  module="${target##*:}"
  echo "=== $pkg::$module ==="
  if ! (cd "$ROOT/move/aptos/$pkg" && aptos move prove --dev -f "$module"); then
    failed=1
  fi
  rm -f "$ROOT/move/aptos/$pkg/boogie.bpl"
  echo
done

exit "$failed"
