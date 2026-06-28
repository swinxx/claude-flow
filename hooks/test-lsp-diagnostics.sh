#!/usr/bin/env bash
# kimiflow - unit tests for lsp-diagnostics.sh.
set -u

SCANNER="$(cd "$(dirname "$0")" && pwd)/lsp-diagnostics.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
BIN="$WORK/bin"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$BIN"
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
unset KIMIFLOW_LSP_MAX_COMMANDS

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

reset_repo() {
  rm -rf "$REPO"
  git init -q "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name tester
}

write_file() {
  mkdir -p "$REPO/$(dirname "$1")"
  printf '%s' "$2" > "$REPO/$1"
}

mock_tool() {
  local name="$1" exit_code="$2" output="$3"
  cat > "$BIN/$name" <<EOF
#!/bin/sh
printf '%s\n' "$output"
exit $exit_code
EOF
  chmod +x "$BIN/$name"
}

unmock_tools() {
  rm -f "$BIN/npm" "$BIN/pnpm" "$BIN/yarn" "$BIN/tsc" "$BIN/pyright" "$BIN/ruff" "$BIN/mypy" "$BIN/diagnostic-tool"
}

run_stdout() {
  (cd "$REPO" && PATH="$BIN:$BASE_PATH" "$SCANNER" 2>/dev/null)
}

run_stderr() {
  (cd "$REPO" && PATH="$BIN:$BASE_PATH" "$SCANNER" 2>&1 1>/dev/null)
}

run_stdout_with_max() {
  (cd "$REPO" && PATH="$BIN:$BASE_PATH" KIMIFLOW_LSP_MAX_COMMANDS="$1" "$SCANNER" 2>/dev/null)
}

assert_has() {
  if printf '%s' "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3 (want '$2' in: ${1:-<empty>})"; fi
}

assert_hasnt() {
  if printf '%s' "$1" | grep -qF -- "$2"; then fail "$3 (did not want '$2' in: $1)"; else pass "$3"; fi
}

assert_count() {
  count="$(printf '%s' "$1" | grep -cF -- "$2")"
  if [ "$count" -eq "$3" ]; then pass "$4"; else fail "$4 (want $3 occurrences of '$2', got $count in: ${1:-<empty>})"; fi
}

reset_repo
unmock_tools
assert_hasnt "$(run_stdout)" "[FLAG]" "no_tool_no_flag_stdout"
assert_has "$(run_stderr)" "SKIPPED" "no_tool_skips_stderr"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit","lint":"eslint ."}}'
mock_tool npm 1 "type error on line 1"
out="$(run_stdout)"
assert_has "$out" "[FLAG]" "npm_typecheck_failure_flagged"
assert_has "$out" "npm run -s typecheck" "npm_typecheck_command_reported"
assert_has "$out" "type error on line 1" "npm_typecheck_summary_reported"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit","lint":"eslint ."}}'
mock_tool npm 1 "src/app.ts(1,1): diagnostic"
out="$(run_stdout)"
assert_count "$out" "[FLAG]" 2 "package_typecheck_and_lint_both_flagged"
assert_has "$out" "package lint" "package_lint_command_reported"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit","lint":"eslint ."}}'
mock_tool npm 1 "src/app.ts(1,1): diagnostic"
out="$(run_stdout_with_max 1)"
assert_count "$out" "[FLAG]" 1 "max_commands_caps_diagnostics"
assert_has "$out" "package typecheck" "max_commands_keeps_first_diagnostic"
assert_hasnt "$out" "package lint" "max_commands_skips_later_diagnostic"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit","lint":"eslint ."}}'
mock_tool npm 1 "src/app.ts(1,1): diagnostic"
out="$(run_stdout_with_max bogus)"
assert_count "$out" "[FLAG]" 2 "invalid_max_commands_uses_default"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit"}}'
write_file src/app.ts 'export const value = 1;'
git -C "$REPO" add package.json src/app.ts >/dev/null 2>&1
git -C "$REPO" commit -q -m baseline
write_file src/app.ts 'export const value: string = 1;'
mock_tool npm 1 "src/app.ts(1,14): error TS2322"
out="$(run_stdout)"
assert_has "$out" "changed-files" "changed_file_diagnostic_classified"
assert_has "$out" "touched: src/app.ts" "changed_file_diagnostic_names_path"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit"}}'
write_file src/app.ts 'export const value = 1;'
write_file legacy/old.ts 'export const old = true;'
git -C "$REPO" add package.json src/app.ts legacy/old.ts >/dev/null 2>&1
git -C "$REPO" commit -q -m baseline
write_file src/app.ts 'export const value = 2;'
mock_tool npm 1 "legacy/old.ts(1,1): error TS1005"
out="$(run_stdout)"
assert_has "$out" "project-wide" "project_wide_diagnostic_classified"
assert_has "$out" "no touched file referenced" "project_wide_diagnostic_explained"

reset_repo
unmock_tools
write_file package.json '{"scripts":{"typecheck":"tsc --noEmit"}}'
mock_tool npm 0 "clean"
assert_hasnt "$(run_stdout)" "[FLAG]" "clean_typecheck_no_flag"

reset_repo
unmock_tools
write_file tsconfig.json '{"compilerOptions":{}}'
mock_tool tsc 2 "src/app.ts(1,1): error TS1005"
out="$(run_stdout)"
assert_has "$out" "[FLAG]" "tsc_failure_flagged"
assert_has "$out" "tsc --noEmit --pretty false" "tsc_command_reported"

reset_repo
unmock_tools
write_file ".kimiflow/lsp-diagnostics" "diagnostic-tool"
mock_tool diagnostic-tool 1 "custom diagnostic"
out="$(run_stdout)"
assert_has "$out" "[FLAG]" "untracked_config_failure_flagged"
assert_has "$out" "configured diagnostics" "untracked_config_label_reported"

reset_repo
unmock_tools
write_file ".kimiflow/lsp-diagnostics" "diagnostic-tool"
git -C "$REPO" add .kimiflow/lsp-diagnostics >/dev/null 2>&1
git -C "$REPO" commit -q -m seed
mock_tool diagnostic-tool 1 "should not run"
assert_hasnt "$(run_stdout)" "[FLAG]" "tracked_config_ignored_no_flag"
assert_has "$(run_stderr)" "tracked .kimiflow/lsp-diagnostics ignored" "tracked_config_warns"

reset_repo
unmock_tools
write_file app.py 'print("hi")'
mock_tool pyright 1 "1 error, 0 warnings"
out="$(run_stdout)"
assert_has "$out" "[FLAG]" "pyright_failure_flagged"
assert_has "$out" "pyright diagnostics" "pyright_label_reported"

reset_repo
unmock_tools
mock_tool diagnostic-tool 1 "should not run"
out="$( (cd "$REPO" && PATH="$BIN:$BASE_PATH" "$SCANNER" --command diagnostic-tool) 2>&1)"
assert_has "$out" "--command is not accepted" "command_override_rejected"
assert_hasnt "$out" "[FLAG]" "command_override_no_flag"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
