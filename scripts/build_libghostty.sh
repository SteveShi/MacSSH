#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/src/ghostty"
OUT_DIR="$ROOT/ThirdParty/lib"

mkdir -p "$ROOT/ThirdParty/src" "$OUT_DIR"

if [[ ! -d "$SRC" ]]; then
  git clone https://github.com/ghostty-org/ghostty.git "$SRC"
else
  git -C "$SRC" pull --rebase
fi

ZIG_BIN="${ZIG_BIN:-}"
if [[ -z "$ZIG_BIN" && -x /opt/homebrew/opt/zig@0.15/bin/zig ]]; then
  ZIG_BIN="/opt/homebrew/opt/zig@0.15/bin/zig"
fi
if [[ -z "$ZIG_BIN" ]]; then
  ZIG_BIN="$(command -v zig || true)"
fi
if [[ -z "$ZIG_BIN" ]]; then
  echo "Zig is required to build Ghostty. Please install Homebrew zig@0.15 or set ZIG_BIN."
  exit 1
fi

ZIG_VERSION="$("$ZIG_BIN" version)"
if [[ "$ZIG_VERSION" != 0.15.2* ]]; then
  echo "Ghostty requires Zig 0.15.2 (found $ZIG_VERSION at $ZIG_BIN)."
  exit 1
fi

(
  cd "$SRC"
  "$ZIG_BIN" build -Dapp-runtime=none -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=native
)

rm -rf "$OUT_DIR/GhosttyKit.xcframework"
cp -R "$SRC/macos/GhosttyKit.xcframework" "$OUT_DIR/GhosttyKit.xcframework"
cp -L "$SRC/zig-out/lib/libghostty-vt.dylib" "$OUT_DIR/libghostty-vt.dylib"

echo "GhosttyKit.xcframework and libghostty-vt.dylib installed to $OUT_DIR"
