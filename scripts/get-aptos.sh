#!/usr/bin/env bash
# Download the Aptos CLI into ./.tools, alongside the Sui one.
# Same reasoning as get-sui.sh: the repo pins one exact compiler version per
# chain, and nothing depends on what happens to be on your global PATH. It
# matters more here than there -- the whole point of move/aptos is to compare
# two dialects, so both compilers have to be the versions this repo claims.
set -euo pipefail

VERSION="${APTOS_VERSION:-7.2.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"

# Aptos ships a zip per platform, named by the OS it was built on.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ASSET="aptos-cli-${VERSION}-Windows-x86_64.zip" ;;
  Darwin)
    case "$(uname -m)" in
      arm64) ASSET="aptos-cli-${VERSION}-macOS-arm64.zip" ;;
      *)     ASSET="aptos-cli-${VERSION}-macOS-x86_64.zip" ;;
    esac ;;
  Linux)                ASSET="aptos-cli-${VERSION}-Linux-x86_64.zip" ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

URL="https://github.com/aptos-labs/aptos-core/releases/download/aptos-cli-v${VERSION}/${ASSET}"

mkdir -p "$TOOLS"
echo "Downloading $URL"
curl -fsSL -o "$TOOLS/aptos.zip" "$URL"

# The archive is flat -- just the binary -- so extract straight into .tools.
if command -v unzip >/dev/null 2>&1; then
  unzip -oq "$TOOLS/aptos.zip" -d "$TOOLS"
else
  # Windows without unzip: PowerShell can do it.
  powershell -NoProfile -Command \
    "Expand-Archive -Force -Path '$(cygpath -w "$TOOLS/aptos.zip" 2>/dev/null || echo "$TOOLS/aptos.zip")' -DestinationPath '$(cygpath -w "$TOOLS" 2>/dev/null || echo "$TOOLS")'"
fi
rm -f "$TOOLS/aptos.zip"
chmod +x "$TOOLS"/aptos* 2>/dev/null || true

echo
echo "Installed to $TOOLS"
"$TOOLS/aptos" --version
echo
echo "Add it to your PATH for this shell:"
echo "  export PATH=\"$TOOLS:\$PATH\""
