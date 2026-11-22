#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

TLA_VERSION=1.7.4
TLA_SHA256=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
JAR=$HOME/.cache/tla/tla2tools-$TLA_VERSION.jar
if [ ! -f "$JAR" ]; then
  mkdir -p "$(dirname "$JAR")"
  curl -sSfL -o "$JAR" "https://github.com/tlaplus/tlaplus/releases/download/v$TLA_VERSION/tla2tools.jar"
fi
echo "$TLA_SHA256  $JAR" | shasum -a 256 -c - >/dev/null

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

check() {
  bug=$1 broken_invariant=$2 fixed=$3
  dir="$TMP/$bug"
  mkdir -p "$dir"
  cp formal/ListenerLifecycle.tla "$dir"
  cat >"$dir/ListenerLifecycle.cfg" <<EOF
SPECIFICATION Spec
CONSTANT Bug = "$bug"
CONSTRAINT Bounded
INVARIANTS NoLeaks NothingOffConsole NoTapOnceRevokeKnown MissingPermissionIsChecked Converged
EOF
  (cd "$dir" && java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 1 -deadlock \
    -metadir "$dir/states" ListenerLifecycle >"$dir/tlc.log" 2>&1) || true
  if [ "$broken_invariant" = none ]; then
    if grep -q 'Model checking completed. No error has been found.' "$dir/tlc.log"; then
      echo "passes  $bug"
    else
      echo "FAILS   $bug"; cat "$dir/tlc.log"; failures=$((failures + 1))
    fi
  elif grep -q "Invariant $broken_invariant is violated" "$dir/tlc.log"; then
    echo "caught  $bug  breaks $broken_invariant  $fixed"
  else
    echo "MISSED  $bug  should break $broken_invariant  $fixed"; cat "$dir/tlc.log"; failures=$((failures + 1))
  fi
}

run() { [ -z "${ONLY:-}" ] || [ "$ONLY" = "$1" ] && check "$@" || true; }
ONLY=${1:-}

run none none "the current design"
run RestartLeak NoLeaks "restarts leaked the tap, its source and the device list (fixed in 7249613)"
run NoSessionGate NothingOffConsole "listeners stayed on while switched out (fixed in 864fc4f)"
run SharedDebounce Converged "a quick switch back dropped become-active (fixed in upstream #172)"
run NoRevokeHandling MissingPermissionIsChecked "a revoked permission went unnoticed (fixed in 08b1415)"
run TapInTapMode Converged "the tap was installed in tap mode (fixed in dd4aa91)"

exit $failures
