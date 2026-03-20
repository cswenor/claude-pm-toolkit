#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT_GITIGNORE="$REPO_ROOT/.gitignore"
TARGET_TEMPLATE="$REPO_ROOT/templates/gitignore-section.txt"

pass=0
fail=0

pass_test() {
  echo "  PASS: $1"
  pass=$((pass + 1))
}

fail_test() {
  echo "  FAIL: $1"
  echo "    $2"
  fail=$((fail + 1))
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local desc="$3"

  if grep -qxF "$pattern" "$file"; then
    pass_test "$desc"
  else
    fail_test "$desc" "missing '$pattern' in ${file#$REPO_ROOT/}"
  fi
}

assert_contains "$ROOT_GITIGNORE" ".plans/" "toolkit .gitignore covers .plans/"
assert_contains "$ROOT_GITIGNORE" "plans/" "toolkit .gitignore covers plans/"
assert_contains "$TARGET_TEMPLATE" "plans/" "target template covers plans/"
assert_contains "$TARGET_TEMPLATE" ".plans/" "target template covers .plans/"

echo
echo "Results: $pass passed, $fail failed"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
