#!/bin/sh
# Usage: scripts/test.sh [repo root], defaulting to this checkout.
set -eu
cd "$(dirname "$0")/.."
ROOT=${1:-.}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

clang -std=c11 -Wall -Wstrict-prototypes -Werror -I"$ROOT/MiddleClick" \
  "$ROOT/tests/GesturesTests.c" "$ROOT/MiddleClick/Gestures.c" -o "$TMP/GesturesTests"
"$TMP/GesturesTests"
