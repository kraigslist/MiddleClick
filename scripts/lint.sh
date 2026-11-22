#!/bin/sh
# Fails on compiler warnings and on static analyzer findings such as leaked CF objects.
# Usage: scripts/lint.sh [source dir], defaulting to MiddleClick.
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
exit $status
