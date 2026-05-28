#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/src/libressl"
BUILD="$ROOT/ThirdParty/build/libressl_macos15"
INSTALL="$ROOT/ThirdParty"

mkdir -p "$ROOT/ThirdParty/src" "$BUILD" "$INSTALL"

if [[ ! -d "$SRC" ]]; then
  git clone https://github.com/libressl/portable.git "$SRC"
else
  git -C "$SRC" pull --rebase
fi

# Ensure we are using version 4.3.2
git -C "$SRC" checkout v4.3.2

# LibreSSL from git requires autotools to generate configure scripts.
# If you have a tagged release tarball, you can skip autogen.sh.
if [[ -x "$SRC/autogen.sh" ]]; then
  (cd "$SRC" && ./autogen.sh)
fi

(cd "$BUILD" && "$SRC/configure" \
  --prefix="$INSTALL" \
  --disable-shared \
  --enable-static)

make -C "$BUILD" -j"$(sysctl -n hw.ncpu)"
make -C "$BUILD" install

echo "LibreSSL installed to $INSTALL"
