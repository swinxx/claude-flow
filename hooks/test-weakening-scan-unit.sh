#!/usr/bin/env bash
# kimiflow — unit tests for test-weakening-scan.sh (the advisory test-weakening scanner).
# Named *-unit.sh because the script under test is itself called test-weakening-scan.sh
# (it scans tests), so test-weakening-scan.sh is taken. Black-box: stages real diffs in
# a throwaway repo and asserts on the scanner's FLAG output. No framework.
# Run: bash hooks/test-weakening-scan-unit.sh
set -u

SCANNER="$(cd "$(dirname "$0")" && pwd)/test-weakening-scan.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

reset_repo() {
  rm -rf "$REPO"; git init -q "$REPO"
  git -C "$REPO" config user.email t@example.com; git -C "$REPO" config user.name tester
}
w()        { mkdir -p "$REPO/$(dirname "$1")"; printf '%s' "$2" > "$REPO/$1"; }
commit()   { git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m "$1"; }
scan()     { ( cd "$REPO" && "$SCANNER" ); }
assert_has()   { if printf '%s' "$1" | grep -qF "$2"; then pass "$3"; else fail "$3 (expected to contain '$2', got: ${1:-<empty>})"; fi; }
assert_hasnt() { if printf '%s' "$1" | grep -qF "$2"; then fail "$3 (did NOT expect '$2', got: $1)"; else pass "$3"; fi; }

# 1) Deleted test file → flagged.
reset_repo
w "foo.test.js" "test('a', () => { expect(1).toBe(1); });"
commit "seed"
git -C "$REPO" rm -q foo.test.js
out="$(scan)"
assert_has "$out" "deleted test file" "deleted_test_flagged"

# 2) Added skip marker → flagged.
reset_repo
w "keep.js" "export const x = 1;"
commit "seed"
w "bar.test.js" "it.skip('x', () => { expect(1).toBe(1); });"
git -C "$REPO" add -A >/dev/null 2>&1
out="$(scan)"
assert_has "$out" "added skip/disable marker" "added_skip_flagged"

# 3) Removed assertion in a test file, no skip → flagged.
reset_repo
w "calc.test.js" "$(printf 'test("a", () => {\n  expect(x).toBe(1);\n  expect(y).toBe(2);\n});\n')"
commit "seed"
w "calc.test.js" "$(printf 'test("a", () => {\n  expect(x).toBe(1);\n});\n')"
git -C "$REPO" add -A >/dev/null 2>&1
out="$(scan)"
assert_has "$out" "removed assertion" "removed_assertion_flagged"

# 4) Removed assertion AND added skip in the SAME hunk → skip flagged, assertion SUPPRESSED.
reset_repo
w "x.test.js" "$(printf 'test("a", () => {\n  expect(x).toBe(1);\n});\n')"
commit "seed"
w "x.test.js" "$(printf 'test.skip("a", () => {\n  // expect(x).toBe(1);\n});\n')"
git -C "$REPO" add -A >/dev/null 2>&1
out="$(scan)"
assert_has   "$out" "added skip/disable marker" "suppress_skip_still_flagged"
assert_hasnt "$out" "removed assertion"         "suppress_assertion_suppressed"

# 5) Removed assertion in a NON-test file → not flagged.
reset_repo
w "app.js" "$(printf 'function f() {\n  assert(x);\n  return 1;\n}\n')"
commit "seed"
w "app.js" "$(printf 'function f() {\n  return 1;\n}\n')"
git -C "$REPO" add -A >/dev/null 2>&1
out="$(scan)"
assert_hasnt "$out" "removed assertion" "nontest_assertion_ignored"

# 6) Clean change (no weakening) → no flags at all.
reset_repo
w "app.js" "export const x = 1;"
commit "seed"
w "app.js" "$(printf 'export const x = 1;\nexport const y = 2;\n')"
git -C "$REPO" add -A >/dev/null 2>&1
out="$(scan)"
assert_hasnt "$out" "[FLAG]" "clean_change_no_flags"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
