#!/bin/sh
# Proves each check still catches the real bug it was added for:
# runs today's check against the source of the commit before each fix, and fails if the check passes.
set -eu
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

report() {
  if [ "$1" = caught ]; then
    echo "caught  $2  $3"
  else
    echo "MISSED  $2  $3"
    failures=$((failures + 1))
  fi
}

# expect_lint_error <commit with the bug> <diagnostic the bug must produce> <what the later fix fixed>
expect_lint_error() {
  dir="$TMP/$1"
  mkdir -p "$dir"
  git archive "$1" MiddleClick | tar -x -C "$dir"
  if ! scripts/lint.sh "$dir/MiddleClick" >"$dir.log" 2>&1 && grep -qF -- "$2" "$dir.log"; then
    report caught "$1" "$3"
  else
    report missed "$1" "$3"
  fi
}

expect_lint_error d9a61d0^ "Potential leak of an object stored into 'ourEvent'" "leaked CGEvents in touchCallback (fixed in d9a61d0)"
expect_lint_error d0bce95^ "Potential leak of an object stored into 'task'" "leaked NSTask in runCommand (fixed in d0bce95)"
expect_lint_error 8e98c80^ "[-Werror,-Wstrict-prototypes]" "C functions declared without prototypes (fixed in 8e98c80)"

exit $failures
