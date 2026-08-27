#!/usr/bin/env bash
# Download the Sui CLI into ./.tools instead of installing it system-wide.
# Vendoring the toolchain means the repo pins one exact compiler version, and
# nothing here depends on what happens to be on your global PATH.
set -euo pipefail

VERSION="${SUI_VERSION:-mainnet-v1.78.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-x86_64" ;;
  Darwin)               PLATFORM="macos-$(uname -m | sed 's/x86_64/x86_64/;s/arm64/arm64/')" ;;
  Linux)                PLATFORM="ubuntu-x86_64" ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

URL="https://github.com/MystenLabs/sui/releases/download/${VERSION}/sui-${VERSION}-${PLATFORM}.tgz"

mkdir -p "$TOOLS"
echo "Downloading $URL"
curl -fsSL -o "$TOOLS/sui.tgz" "$URL"
tar -xzf "$TOOLS/sui.tgz" -C "$TOOLS"
rm -f "$TOOLS/sui.tgz"          # the archive is ~274MB and redundant once extracted
chmod +x "$TOOLS"/* 2>/dev/null || true

echo
echo "Installed to $TOOLS"
"$TOOLS/sui" --version
echo
echo "Add it to your PATH for this shell:"
echo "  export PATH=\"$TOOLS:\$PATH\""
