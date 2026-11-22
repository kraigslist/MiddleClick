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

# expect_test_failure <file> <sed script that puts the bug back> <test that must fail, or "compile"> <what the fix fixed>
expect_test_failure() {
  dir="$TMP/replay$((replays = ${replays:-0} + 1))"
  mkdir -p "$dir"
  cp -R MiddleClick tests "$dir"
  sed -i '' -e "$2" "$dir/$1"
  if cmp -s "$1" "$dir/$1"; then
    report missed "$1" "$4: the replay no longer applies, update it"
  elif scripts/test.sh "$dir" >"$dir.log" 2>&1; then
    report missed "$1" "$4"
  elif [ "$3" = compile ] && grep -q 'error:' "$dir.log" || grep -qF "FAIL  $3" "$dir.log"; then
    report caught "$1" "$4"
  else
    report missed "$1" "$4"
  fi
}

expect_test_failure MiddleClick/Gestures.c 's/i < nFingers/i < 3/' \
  "the configured finger count is used" "taps summed three fingers whatever the setting (fixed in 6da864a)"
expect_test_failure MiddleClick/Gestures.c '/double elapsedTime/d; s/ \&\& elapsedTime <= settings->maxTimeDelta//' \
  "fingers resting past the time limit" "fingers could rest any time and still tap (fixed in ec70590)"
expect_test_failure MiddleClick/PreferenceKeys.h 's/DeltaDefault 0.05f/DeltaDefault 0.4f/; s/MsDefault 300/MsDefault 500/' \
  "fingers that slide don't click" "defaults let swipes middle-click (fixed in b67c7a8, #39)"
expect_test_failure MiddleClick/Gestures.c '/click->fingersDown = false;/d' \
  "the next click is a left click" "three-finger click got stuck (fixed in 3f3aa45)"
expect_test_failure MiddleClick/Gestures.c 's/bool isTap = false;/bool isTap = [NSDate new] != nil;/' \
  compile "per-frame NSDate allocation in the touch callback (fixed in 854f3e2)"

expect_lint_error d9a61d0^ "Potential leak of an object stored into 'ourEvent'" "leaked CGEvents in touchCallback (fixed in d9a61d0)"
expect_lint_error d0bce95^ "Potential leak of an object stored into 'task'" "leaked NSTask in runCommand (fixed in d0bce95)"
expect_lint_error 8e98c80^ "[-Werror,-Wstrict-prototypes]" "C functions declared without prototypes (fixed in 8e98c80)"

exit $failures
