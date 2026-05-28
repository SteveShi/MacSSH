#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build_boringssl.sh"
"$ROOT/scripts/build_libssh2.sh"
"$ROOT/scripts/build_libghostty.sh"

echo "All dependency build steps completed."
