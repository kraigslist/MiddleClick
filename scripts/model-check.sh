#!/bin/sh
# Model-checks formal/ListenerLifecycle.tla: the current design must pass every invariant,
# and each replayed past bug must break the invariant that guards it.
# Usage: scripts/model-check.sh [Bug], where Bug is one of the replays below. Defaults to all.
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

# check <Bug> <invariant that must fail, or "none">
check() {
  dir="$TMP/$1"
  mkdir -p "$dir"
  cp formal/ListenerLifecycle.tla "$dir"
  cat >"$dir/ListenerLifecycle.cfg" <<EOF
SPECIFICATION Spec
CONSTANT Bug = "$1"
CONSTRAINT Bounded
INVARIANTS NoLeaks NothingOffConsole NoTapOnceRevokeKnown MissingPermissionIsChecked Converged
EOF
  (cd "$dir" && java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 1 -deadlock \
    -metadir "$dir/states" ListenerLifecycle >"$dir/tlc.log" 2>&1) || true
  if [ "$2" = none ]; then
    if grep -q 'Model checking completed. No error has been found.' "$dir/tlc.log"; then
      echo "passes  $1"
    else
      echo "FAILS   $1"; cat "$dir/tlc.log"; failures=$((failures + 1))
    fi
  elif grep -q "Invariant $2 is violated" "$dir/tlc.log"; then
    echo "caught  $1  breaks $2"
  else
    echo "MISSED  $1  should break $2"; cat "$dir/tlc.log"; failures=$((failures + 1))
  fi
}

run() { [ -z "${ONLY:-}" ] || [ "$ONLY" = "$1" ] && check "$1" "$2" || true; }
ONLY=${1:-}

run none none
run RestartLeak NoLeaks                         # 7249613: restarts leaked the tap, its source and the device list
run NoSessionGate NothingOffConsole             # 864fc4f: listeners stayed on while switched out
run SharedDebounce Converged                    # upstream #172: a quick switch back dropped become-active
run NoRevokeHandling MissingPermissionIsChecked # 08b1415: a revoked permission went unnoticed
run TapInTapMode Converged                      # dd4aa91: the tap was installed in tap mode

exit $failures
