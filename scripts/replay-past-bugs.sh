#!/bin/sh
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

expect_lint_error() {
  buggy_commit=$1 diagnostic=$2 fixed=$3
  dir="$TMP/$buggy_commit"
  mkdir -p "$dir"
  git archive "$buggy_commit" MiddleClick | tar -x -C "$dir"
  if ! scripts/lint.sh "$dir/MiddleClick" >"$dir.log" 2>&1 && grep -qF -- "$diagnostic" "$dir.log"; then
    report caught "$buggy_commit" "$fixed"
  else
    report missed "$buggy_commit" "$fixed"
  fi
}

expect_test_failure() {
  file=$1 put_bug_back=$2 failing_test=$3 fixed=$4
  dir="$TMP/replay$((replays = ${replays:-0} + 1))"
  mkdir -p "$dir"
  cp -R MiddleClick tests "$dir"
  sed -i '' -e "$put_bug_back" "$dir/$file"
  if cmp -s "$file" "$dir/$file"; then
    report missed "$file" "$fixed: the replay no longer applies, update it"
  elif scripts/test.sh "$dir" >"$dir.log" 2>&1; then
    report missed "$file" "$fixed"
  elif [ "$failing_test" = compile ] && grep -q 'error:' "$dir.log" || grep -qF "FAIL  $failing_test" "$dir.log"; then
    report caught "$file" "$fixed"
  else
    report missed "$file" "$fixed"
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
expect_test_failure MiddleClick/Gestures.c 's/int tapFingers = 0;/int tapFingers = [NSDate new] != nil;/' \
  compile "per-frame NSDate allocation in the touch callback (fixed in 854f3e2)"

expect_lint_error d9a61d0^ "Potential leak of an object stored into 'ourEvent'" "leaked CGEvents in touchCallback (fixed in d9a61d0)"
expect_lint_error d0bce95^ "Potential leak of an object stored into 'task'" "leaked NSTask in runCommand (fixed in d0bce95)"
expect_lint_error 854f3e2^ "touchCallback sends an Objective-C message" "per-frame NSUserDefaults and NSDate allocation in touchCallback (fixed in 854f3e2)"
expect_lint_error 8e98c80^ "[-Werror,-Wstrict-prototypes]" "C functions declared without prototypes (fixed in 8e98c80)"

exit $failures
