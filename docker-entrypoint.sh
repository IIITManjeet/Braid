#!/bin/sh
# Run the API and the page together, and treat either one dying as the
# container dying. A half-running Braid serves pages whose every number is an
# error, which is worse than being down and getting restarted.
#
# POSIX sh on purpose: the image is Alpine, whose /bin/sh is busybox ash, so
# `wait -n` is not available to notice which child exited first.
set -eu

braid-server --root /app --port "${BRAID_API_PORT:-8080}" &
api=$!

node server.js &
web=$!

stop() {
  kill "$api" "$web" 2>/dev/null || true
  exit 0
}
trap stop TERM INT

while kill -0 "$api" 2>/dev/null && kill -0 "$web" 2>/dev/null; do
  sleep 1
done

echo "one of the two processes exited; stopping the other" >&2
kill "$api" "$web" 2>/dev/null || true
exit 1
