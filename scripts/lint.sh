#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
SRC=${1:-MiddleClick}

MIN_MACOS=$(sed -n 's/.*[[:space:]]MACOSX_DEPLOYMENT_TARGET = \(.*\);/\1/p' MiddleClick.xcodeproj/project.pbxproj | head -1)
CFLAGS="-mmacosx-version-min=$MIN_MACOS -F/System/Library/PrivateFrameworks -Wall -Wstrict-prototypes -Werror"

status=0
for file in "$SRC"/*.m "$SRC"/*.c; do
  [ -e "$file" ] || continue
  flags=$CFLAGS
  case $file in *.m) flags="$flags -fno-objc-arc -fobjc-weak" ;; esac
  clang -fsyntax-only $flags "$file" || status=1
  clang --analyze -Xclang -analyzer-werror -Xclang -analyzer-output=text $flags "$file" -o /dev/null || status=1
done

if awk '/^int touchCallback\(/,/^}/' "$SRC/Controller.m" | grep -qE '\[[A-Za-z_][A-Za-z0-9_]* [A-Za-z_]|@'; then
  echo "$SRC/Controller.m: error: touchCallback sends an Objective-C message. It runs on every multitouch frame," \
    "so it must not allocate: move the work into loadTouchSettings, which runs once per gesture, or into Gestures.c."
  status=1
fi
exit $status
