#!/usr/bin/env bash
# kimiflow — unit tests for memory-router.sh.
# Isolation: temp git repo under mktemp; the real repo is never touched.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/memory-router.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_jq() {
  local json="$1" expr="$2" name="$3"
  if printf '%s\n' "$json" | jq -e "$expr" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — memory-router uses jq"; exit 0
fi

reset_repo() {
  rm -rf "$REPO"
  mkdir -p "$REPO/src" "$REPO/.kimiflow/project"
  ( cd "$REPO" && git init -q && git config user.email "kimiflow@example.test" && git config user.name "kimiflow test" )
  ( cd "$REPO" && git remote add origin https://github.com/swinxx/kimiflow.git )
  printf '.kimiflow/\n' > "$REPO/.gitignore"
  printf 'one\n' > "$REPO/src/a.txt"
  ( cd "$REPO" && git add .gitignore src/a.txt && git commit -q -m init )
}

run_router() {
  "$SCRIPT" "$@" --root "$REPO"
}

reset_repo
rm -rf "$REPO/.kimiflow/project"
out="$(run_router status)"
assert_jq "$out" '.present == false and .memory.present == false and .curation.recommended == false' "missing_memory_reports_empty"

reset_repo
cat > "$REPO/.kimiflow/project/MEMORY.md" <<'EOF'
# Memory

Builds use shell smoke tests. Release work updates Claude and Codex manifests together.
EOF
cat > "$REPO/.kimiflow/project/LEARNINGS.jsonl" <<'EOF'
{"id":"learn_release","kind":"process","scope":"project","topic":"release","summary":"Release updates both plugin manifests and tags kimiflow--vX.Y.Z.","evidence":[".claude-plugin/plugin.json:4",".codex-plugin/plugin.json:3"],"confidence":"high","sensitivity":"normal","last_verified":"2026-06-25","source_commit":"abc1234","status":"current"}
{"id":"learn_old","kind":"process","scope":"project","topic":"launcher","summary":"Old launcher detail superseded by memory status output.","evidence":["hooks/launcher-status.sh:1"],"confidence":"medium","sensitivity":"normal","last_verified":"2026-06-25","source_commit":"abc1234","status":"stale"}
{"id":"learn_secret","kind":"risk","scope":"project","topic":"security","summary":"Concrete credential handling detail stays local only.","evidence":["NOT VERIFIED"],"confidence":"low","sensitivity":"security","last_verified":"2026-06-25","source_commit":"abc1234","status":"current"}
EOF
out="$(run_router status)"
assert_jq "$out" '.present == true and .memory.tokens_estimate > 0' "status_reports_memory"
assert_jq "$out" '.learnings.total == 3 and .learnings.current == 2 and .learnings.stale == 1 and .learnings.security == 1' "status_counts_learnings"
assert_jq "$out" '.curation.recommended == true and (.curation.reasons | index("stale_learnings")) and (.curation.reasons | index("memory_index_missing"))' "status_recommends_curation"

cat > "$REPO/.kimiflow/project/FACTS.jsonl" <<'EOF'
{"kind":"entrypoint","area":"launcher","path":"hooks/launcher-status.sh","line":1,"summary":"Launcher status exposes memory router state.","confidence":"high","commit":"abc1234"}
{"kind":"test","area":"memory","path":"hooks/test-memory-router.sh","line":1,"summary":"Memory router tests cover recall and curation.","confidence":"high","commit":"abc1234"}
EOF
out="$(run_router recall --query "launcher memory" --max 2 --write .kimiflow/project/RECALL.md)"
assert_jq "$out" '.sources.memory.status == "included" and .sources.learnings.count >= 1 and .sources.facts.count >= 1' "recall_returns_relevant_hits"
[ -f "$REPO/.kimiflow/project/RECALL.md" ] && pass "recall_writes_markdown" || fail "recall_writes_markdown"

out="$("$SCRIPT" classify --text "Security finding: API token leaked through .env handling")"
assert_jq "$out" '.classification.target == "project_memory" and .classification.sensitivity == "security" and .classification.vault_allowed == false and .classification.repo_doc_allowed == false' "classify_security_stays_local"

out="$("$SCRIPT" classify --text "Write publish-safe architecture documentation for repo docs onboarding")"
assert_jq "$out" '.classification.target == "repo_doc_candidate" and .classification.repo_doc_allowed == true' "classify_publish_safe_repo_doc_candidate"

out="$(run_router record --summary "Memory router status is exposed through launcher-status." --topic memory --kind process --confidence high --sensitivity normal --evidence hooks/launcher-status.sh:1)"
printf '%s\n' "$out" | grep -q '^RECORDED	.kimiflow/project/LEARNINGS.jsonl	learn_' && pass "record_appends_learning" || fail "record_appends_learning"

out="$(run_router curate --write)"
assert_jq "$out" '.topics.memory | length >= 1' "curate_builds_topic_index"
[ -f "$REPO/.kimiflow/project/MEMORY-INDEX.json" ] && pass "curate_writes_index" || fail "curate_writes_index"
assert_jq "$(cat "$REPO/.kimiflow/project/MEMORY-INDEX.json")" '.schema_version == 1 and .repo_id == "github.com/swinxx/kimiflow" and .learnings.total >= 4' "curate_index_shape"

mkdir -p "$REPO/.kimiflow/demo-run"
if run_router verify-run --run .kimiflow/demo-run >/dev/null 2>&1; then
  fail "verify_run_blocks_missing_review"
else
  pass "verify_run_blocks_missing_review"
fi
cat > "$REPO/.kimiflow/demo-run/RESEARCH.md" <<'EOF'
Memory recall should run before web research when a local project map can answer the question.
EOF
cat > "$REPO/.kimiflow/demo-run/ACCEPTANCE.md" <<'EOF'
Project rule confirmed: every acceptance criterion maps to a named verification method.
EOF
cat > "$REPO/.kimiflow/demo-run/CODE-REVIEW.md" <<'EOF'
Pitfall: do not publish raw security findings into repo documentation.
EOF
cat > "$REPO/.kimiflow/demo-run/PLAN.md" <<'EOF'
Decision: keep Memory Router local-first and use Vault only as an optional provider.
EOF
out="$(run_router review-run --run .kimiflow/demo-run --write)"
assert_jq "$out" '.status == "recorded" and .recorded_count == 4 and .memory_updated == true' "review_run_records_four_questions"
[ -f "$REPO/.kimiflow/demo-run/LEARNING-REVIEW.md" ] && pass "review_run_writes_review" || fail "review_run_writes_review"
[ -f "$REPO/.kimiflow/project/MEMORY.md" ] && pass "review_run_writes_bounded_memory" || fail "review_run_writes_bounded_memory"
out="$(run_router verify-run --run .kimiflow/demo-run)"
printf '%s\n' "$out" | grep -q '^LEARNING_REVIEW	OPEN	status=recorded' && pass "verify_run_opens_recorded_review" || fail "verify_run_opens_recorded_review"
assert_jq "$(jq -Rsc 'split("\n") | map(select(length > 0) | (fromjson? // empty))' "$REPO/.kimiflow/project/LEARNINGS.jsonl")" 'map(.kind) | index("learned") and index("project_rule_confirmed") and index("trap_or_pitfall") and index("important_decision")' "review_run_records_expected_kinds"
assert_jq "$(cat "$REPO/.kimiflow/project/MEMORY-INDEX.json")" '.learnings.total >= 8 and (.topics.decisions | length >= 1)' "review_run_refreshes_index"
before_count="$(wc -l < "$REPO/.kimiflow/project/LEARNINGS.jsonl" | tr -d '[:space:]')"
out="$(run_router review-run --run .kimiflow/demo-run --write)"
after_count="$(wc -l < "$REPO/.kimiflow/project/LEARNINGS.jsonl" | tr -d '[:space:]')"
[ "$before_count" = "$after_count" ] && pass "review_run_is_idempotent" || fail "review_run_is_idempotent"

mkdir -p "$REPO/.kimiflow/skip-run"
out="$(run_router review-run --run .kimiflow/skip-run --write --skip "intentionally trivial run")"
assert_jq "$out" '.status == "skipped" and .recorded_count == 0 and .written == true' "review_run_allows_explicit_skip"
out="$(run_router verify-run --run .kimiflow/skip-run)"
printf '%s\n' "$out" | grep -q '^LEARNING_REVIEW	OPEN	status=skipped' && pass "verify_run_opens_explicit_skip" || fail "verify_run_opens_explicit_skip"

awk 'BEGIN{for(i=0;i<950;i++) printf "word "}' > "$REPO/.kimiflow/project/MEMORY.md"
out="$(run_router status)"
assert_jq "$out" '.memory.over_budget == true and (.curation.reasons | index("memory_over_budget"))' "over_budget_memory_recommends_curation"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
