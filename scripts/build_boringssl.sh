#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/src/boringssl"
BUILD="$ROOT/ThirdParty/build/boringssl_macos15"
INSTALL="$ROOT/ThirdParty"

mkdir -p "$ROOT/ThirdParty/src" "$BUILD" "$INSTALL/lib" "$INSTALL/include"

if [[ ! -d "$SRC" ]]; then
  git clone https://github.com/google/boringssl.git "$SRC"
else
  git -C "$SRC" fetch --tags
fi

echo "Checking out BoringSSL version 0.20260526.0..."
git -C "$SRC" checkout 0.20260526.0

echo "Configuring BoringSSL with CMake..."
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

echo "Building BoringSSL..."
cmake --build "$BUILD" -j"$(sysctl -n hw.ncpu)"

echo "Installing BoringSSL static libraries to $INSTALL/lib..."
cp -f "$BUILD/libcrypto.a" "$INSTALL/lib/"
cp -f "$BUILD/libssl.a" "$INSTALL/lib/"

echo "Installing BoringSSL headers to $INSTALL/include..."
rm -rf "$INSTALL/include/openssl"
cp -R "$SRC/include/openssl" "$INSTALL/include/"

echo "BoringSSL installation completed."
