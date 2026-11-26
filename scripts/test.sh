#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ROOT=${1:-.}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CFLAGS="-std=c11 -Wall -Wstrict-prototypes -Werror -I$ROOT/MiddleClick"
clang $CFLAGS "$ROOT/tests/GesturesTests.c" "$ROOT/MiddleClick/Gestures.c" -o "$TMP/GesturesTests"
clang $CFLAGS "$ROOT/tests/WindowFrameTests.c" "$ROOT/MiddleClick/WindowFrame.c" -o "$TMP/WindowFrameTests"

status=0
"$TMP/GesturesTests" || status=1
"$TMP/WindowFrameTests" || status=1
exit $status
