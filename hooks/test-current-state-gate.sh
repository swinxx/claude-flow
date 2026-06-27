#!/usr/bin/env bash
# kimiflow — unit tests for current-state-gate.sh.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/current-state-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — current-state-gate uses jq"; exit 0
fi

write_file() {
  local path="$1" text="$2"
  printf '%s\n' "$text" > "$path"
}

assert_assess() {
  local text="$1" expected="$2" name="$3" input out
  input="$WORK/$name.txt"
  write_file "$input" "$text"
  out="$("$SCRIPT" assess --input "$input")"
  if printf '%s\n' "$out" | jq -e --arg expected "$expected" '.current_state_risk == $expected' >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
    printf '%s\n' "$out"
  fi
}

assert_verify() {
  local assessment_text="$1" recall_text="$2" expected="$3" name="$4"
  local assessment recall out verdict
  assessment="$WORK/$name.assessment.json"
  recall="$WORK/$name.recall.md"
  printf '%s\n' "$assessment_text" > "$assessment"
  printf '%s\n' "$recall_text" > "$recall"
  out="$("$SCRIPT" verify --assessment "$assessment" --recall "$recall")"
  verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
  if [ "$verdict" = "$expected" ]; then
    pass "$name"
  else
    fail "$name"
    printf '%s\n' "$out"
  fi
}

assert_assess "Rename helper variable in local shell script" "low" "low_local_change"
assert_assess "Build a Codex and Claude Code plugin hook for MCP marketplace behavior" "high" "high_host_plugin_surface"
assert_assess "Implement Stripe payment auth deployment SDK flow" "high" "high_security_external_surface"
assert_assess "Update React dependency usage for new framework API" "medium" "medium_library_api_surface"

HIGH='{"schema_version":1,"current_state_risk":"high"}'
MEDIUM='{"schema_version":1,"current_state_risk":"medium"}'
LOW='{"schema_version":1,"current_state_risk":"low"}'

assert_verify "$LOW" "" "OPEN" "verify_low_opens_without_recall"
assert_verify "$MEDIUM" "# Recall" "CLOSED" "verify_medium_closes_without_checked_source"
assert_verify "$MEDIUM" "# Recall

Status: checked

- source_type: official_docs
  source_url: https://react.dev/reference/react
  summary: Current API behavior checked." "OPEN" "verify_medium_opens_with_primary_source"
assert_verify "$HIGH" "# Recall" "CLOSED" "verify_high_closes_without_checked_source"
assert_verify "$HIGH" "# Recall

Status: checked

- source_type: official_docs
  summary: Missing URL." "CLOSED" "verify_high_closes_without_source_url"
assert_verify "$HIGH" "# Recall

- source_type: official_docs
  source_url: https://developers.openai.com/codex/hooks
  summary: Missing checked status." "CLOSED" "verify_high_closes_without_checked_status"
assert_verify "$HIGH" "# Recall

Status: checked

- source_type: official_docs
  source_url: https://developers.openai.com/codex/hooks
  summary: Plugin-bundled hooks use the same event schema." "OPEN" "verify_high_opens_with_primary_source"
assert_verify "$HIGH" '{"status":"checked","source_type":"schema_or_manifest","source_url":"https://developers.openai.com/codex/plugins/build"}' "OPEN" "verify_high_opens_with_json_recall"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
