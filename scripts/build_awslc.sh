#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v1.73.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/src/awslc"
BUILD="$ROOT/ThirdParty/build/awslc_macos15"
INSTALL="$ROOT/ThirdParty"

mkdir -p "$ROOT/ThirdParty/src" "$BUILD" "$INSTALL/lib" "$INSTALL/include"

if [[ ! -d "$SRC" ]]; then
  git clone https://github.com/aws/aws-lc.git "$SRC"
else
  git -C "$SRC" fetch --tags
fi

echo "Checking out AWS-LC version $VERSION..."
git -C "$SRC" checkout "$VERSION"
git -C "$SRC" submodule update --init --recursive || true

echo "Configuring AWS-LC with CMake..."
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=OFF

echo "Building AWS-LC..."
cmake --build "$BUILD" -j"$(sysctl -n hw.ncpu)"

echo "Installing AWS-LC..."
cmake --install "$BUILD"

echo "AWS-LC installation completed."
