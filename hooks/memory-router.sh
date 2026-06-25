#!/usr/bin/env bash
# kimiflow — token-cheap local memory router. Orchestrator-invoked, not a hook.
#
# Usage:
#   memory-router.sh status [--root <path>] [--pretty]
#   memory-router.sh recall --query <text>|--query-file <path> [--root <path>] [--max <n>] [--write <path>] [--pretty]
#   memory-router.sh classify --input <path>|--text <text> [--pretty]
#   memory-router.sh record --summary <text> --topic <topic> --evidence <ref>... [--root <path>] [--kind <kind>] [--scope <scope>] [--confidence <level>] [--sensitivity <level>] [--status <status>]
#   memory-router.sh review-run --run <path> [--root <path>] [--write] [--pretty] [--skip <reason>]
#   memory-router.sh verify-run --run <path> [--root <path>]
#   memory-router.sh curate [--root <path>] [--write] [--pretty]
#
# Output: JSON except record/verify-run, which emit stable tab-separated lines.
set -u

usage() {
  sed -n '1,13p' "$0" >&2
}

die() {
  printf 'memory-router: %s\n' "$1" >&2
  exit "${2:-1}"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required" 2
}

resolve_root() {
  local root="$1"
  if [ -n "$root" ]; then
    (cd "$root" 2>/dev/null && pwd) || printf '%s' "$root"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

date_now() {
  date -u +"%Y-%m-%d"
}

word_count_file() {
  local file="$1"
  if [ -f "$file" ]; then
    wc -w < "$file" | tr -d '[:space:]'
  else
    printf '0'
  fi
}

json_print() {
  local json="$1" pretty="$2"
  if [ "$pretty" -eq 1 ]; then
    printf '%s\n' "$json" | jq .
  else
    printf '%s\n' "$json" | jq -c .
  fi
}

read_jsonl_summary() {
  local file="$1"
  if [ ! -f "$file" ]; then
    jq -n '{
      total: 0,
      current: 0,
      stale: 0,
      superseded: 0,
      archived: 0,
      private: 0,
      security: 0,
      by_topic: {}
    }'
    return 0
  fi

  jq -Rsc '
    def rows: split("\n") | map(select(length > 0) | (fromjson? // empty));
    rows as $rows
    | {
        total: ($rows | length),
        current: ($rows | map(select((.status // "current") == "current")) | length),
        stale: ($rows | map(select((.status // "") == "stale")) | length),
        superseded: ($rows | map(select((.status // "") == "superseded")) | length),
        archived: ($rows | map(select((.status // "") == "archived")) | length),
        private: ($rows | map(select((.sensitivity // "") == "private")) | length),
        security: ($rows | map(select((.sensitivity // "") == "security")) | length),
        by_topic: (
          $rows
          | sort_by(.topic // "uncategorized")
          | group_by(.topic // "uncategorized")
          | map({key: (.[0].topic // "uncategorized"), value: length})
          | from_entries
        )
      }
  ' "$file"
}

vault_status_json() {
  local index="$1"
  local env_available="${KIMIFLOW_VAULT_AVAILABLE:-}"
  local available=false
  local last_recall='null'
  local last_write='null'

  case "$env_available" in
    1|true|TRUE|yes|YES) available=true ;;
  esac

  if [ -f "$index" ] && jq -e . "$index" >/dev/null 2>&1; then
    if jq -e '.vault.available == true' "$index" >/dev/null 2>&1; then
      available=true
    fi
    last_recall="$(jq -c '.vault.last_recall_at // null' "$index" 2>/dev/null || printf 'null')"
    last_write="$(jq -c '.vault.last_write_at // null' "$index" 2>/dev/null || printf 'null')"
  fi

  jq -n \
    --argjson available "$available" \
    --argjson last_recall "$last_recall" \
    --argjson last_write "$last_write" \
    '{available: $available, last_recall_at: $last_recall, last_write_at: $last_write}'
}

status_json() {
  local root="$1"
  local budget="${KIMIFLOW_MEMORY_BUDGET:-900}"
  local learning_threshold="${KIMIFLOW_MEMORY_CURATE_AFTER_LEARNINGS:-10}"
  local project="$root/.kimiflow/project"
  local memory="$project/MEMORY.md"
  local learnings="$project/LEARNINGS.jsonl"
  local index="$project/MEMORY-INDEX.json"
  local recall="$project/RECALL.md"

  local memory_tokens memory_present learnings_present index_present recall_present learning_json vault_json
  memory_tokens="$(word_count_file "$memory")"
  memory_present=false; [ -f "$memory" ] && memory_present=true
  learnings_present=false; [ -f "$learnings" ] && learnings_present=true
  index_present=false; [ -f "$index" ] && index_present=true
  recall_present=false; [ -f "$recall" ] && recall_present=true
  learning_json="$(read_jsonl_summary "$learnings")"
  vault_json="$(vault_status_json "$index")"

  jq -n \
    --arg root "$root" \
    --arg memory_path ".kimiflow/project/MEMORY.md" \
    --arg learnings_path ".kimiflow/project/LEARNINGS.jsonl" \
    --arg index_path ".kimiflow/project/MEMORY-INDEX.json" \
    --arg recall_path ".kimiflow/project/RECALL.md" \
    --argjson memory_present "$memory_present" \
    --argjson learnings_present "$learnings_present" \
    --argjson index_present "$index_present" \
    --argjson recall_present "$recall_present" \
    --argjson memory_tokens "$memory_tokens" \
    --argjson budget "$budget" \
    --argjson learning_threshold "$learning_threshold" \
    --argjson learnings "$learning_json" \
    --argjson vault "$vault_json" \
    '{
      schema_version: 1,
      present: ($memory_present or $learnings_present or $index_present or $recall_present),
      root: $root,
      paths: {
        memory: $memory_path,
        learnings: $learnings_path,
        index: $index_path,
        recall: $recall_path
      },
      memory: {
        present: $memory_present,
        path: $memory_path,
        tokens_estimate: $memory_tokens,
        budget: $budget,
        over_budget: ($memory_tokens > $budget)
      },
      learnings: ($learnings + {present: $learnings_present, path: $learnings_path}),
      vault: $vault,
      curation: {
        recommended: (
          ($memory_tokens > $budget)
          or ($learnings.stale > 0)
          or ($learnings.superseded > 0)
          or (($learnings.total > 0) and ($index_present | not))
          or ($learnings.total >= $learning_threshold)
        ),
        reasons: ([
          if $memory_tokens > $budget then "memory_over_budget" else empty end,
          if $learnings.stale > 0 then "stale_learnings" else empty end,
          if $learnings.superseded > 0 then "superseded_learnings" else empty end,
          if (($learnings.total > 0) and ($index_present | not)) then "memory_index_missing" else empty end,
          if $learnings.total >= $learning_threshold then "many_learnings" else empty end
        ])
      }
    }'
}

terms_json_from_query() {
  local query="$1"
  local terms
  terms="$(printf '%s\n' "$query" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]_-' '\n' \
    | awk '
      length($0) >= 3 &&
      $0 !~ /^(the|and|for|mit|und|der|die|das|ein|eine|ist|sind|was|wie|this|that|from|into|zur|zum|auf|von)$/ &&
      !seen[$0]++ { print }
    ' \
    | head -30 \
    | jq -R . \
    | jq -s .)"
  if [ "$(printf '%s\n' "$terms" | jq 'length')" -eq 0 ]; then
    jq -n --arg q "$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')" '[$q]'
  else
    printf '%s\n' "$terms"
  fi
}

jsonl_hits() {
  local file="$1" terms="$2" max="$3" fields="$4"
  if [ ! -f "$file" ]; then
    jq -n '[]'
    return 0
  fi

  jq -Rsc \
    --argjson terms "$terms" \
    --argjson max "$max" \
    --arg fields "$fields" \
    '
      def field_text($row; $fields):
        ($fields | split(","))
        | map(
            ($row[.] // "")
            | if type == "array" then join(" ")
              elif type == "object" then tostring
              else tostring
              end
          )
        | join(" ");
      def hit($text):
        ($text | ascii_downcase) as $t
        | any($terms[]; . as $term | ($term != "" and ($t | contains($term))));
      split("\n")
      | map(select(length > 0) | (fromjson? // empty))
      | map(select(hit(field_text(.; $fields))))
      | .[:$max]
    ' "$file"
}

write_recall_markdown() {
  local path="$1" json="$2"
  mkdir -p "$(dirname "$path")"
  {
    printf '# Recall\n\n'
    printf 'Generated: %s\n\n' "$(iso_now)"
    printf 'Query: %s\n\n' "$(printf '%s\n' "$json" | jq -r '.query')"
    printf 'Terms: %s\n\n' "$(printf '%s\n' "$json" | jq -r '.query_terms | join(", ")')"
    printf 'Token budget: %s\n\n' "$(printf '%s\n' "$json" | jq -r '.token_budget')"
    printf '## Sources\n\n'
    printf -- '- MEMORY.md: %s\n' "$(printf '%s\n' "$json" | jq -r '.sources.memory.status')"
    printf -- '- LEARNINGS.jsonl hits: %s\n' "$(printf '%s\n' "$json" | jq -r '.sources.learnings.count')"
    printf -- '- FACTS.jsonl hits: %s\n' "$(printf '%s\n' "$json" | jq -r '.sources.facts.count')"
    printf '\n## Omitted\n\n'
    printf '%s\n' "$json" | jq -r '.omitted[]? | "- " + .'
  } > "$path"
}

cmd_status() {
  local root="" pretty=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "status: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  json_print "$(status_json "$root")" "$pretty"
}

cmd_recall() {
  local root="" query="" query_file="" pretty=0 max=5 write_path=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --query) shift; query="${1:-}" ;;
      --query-file) shift; query_file="${1:-}" ;;
      --max) shift; max="${1:-}" ;;
      --write) shift; write_path="${1:-}" ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "recall: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  if [ -n "$query_file" ]; then
    [ -f "$query_file" ] || die "query file not found: $query_file" 2
    query="$(sed -n '1,120p' "$query_file")"
  fi
  [ -n "$query" ] || die "recall requires --query or --query-file" 2
  case "$max" in ''|*[!0-9]*) die "recall --max must be a number" 2 ;; esac

  local project memory learnings facts budget memory_tokens terms memory_status memory_content learning_hits fact_hits omitted json
  project="$root/.kimiflow/project"
  memory="$project/MEMORY.md"
  learnings="$project/LEARNINGS.jsonl"
  facts="$project/FACTS.jsonl"
  budget="${KIMIFLOW_MEMORY_BUDGET:-900}"
  memory_tokens="$(word_count_file "$memory")"
  terms="$(terms_json_from_query "$query")"
  omitted='[]'

  if [ -f "$memory" ]; then
    if [ "$memory_tokens" -le "$budget" ]; then
      memory_status="included"
      memory_content="$(sed -n '1,160p' "$memory")"
    else
      memory_status="omitted_over_budget"
      memory_content=""
      omitted="$(printf '%s\n' "$omitted" | jq '. + ["MEMORY.md omitted: over budget"]')"
    fi
  else
    memory_status="missing"
    memory_content=""
    omitted="$(printf '%s\n' "$omitted" | jq '. + ["MEMORY.md missing"]')"
  fi

  learning_hits="$(jsonl_hits "$learnings" "$terms" "$max" "id,kind,scope,topic,summary,status,sensitivity,evidence")"
  fact_hits="$(jsonl_hits "$facts" "$terms" "$max" "kind,area,path,summary,confidence")"

  json="$(jq -n \
    --arg query "$query" \
    --argjson terms "$terms" \
    --arg memory_status "$memory_status" \
    --arg memory_path ".kimiflow/project/MEMORY.md" \
    --arg memory_content "$memory_content" \
    --argjson memory_tokens "$memory_tokens" \
    --argjson budget "$budget" \
    --argjson learnings "$learning_hits" \
    --argjson facts "$fact_hits" \
    --argjson omitted "$omitted" \
    '{
      schema_version: 1,
      query: $query,
      query_terms: $terms,
      token_budget: $budget,
      sources: {
        memory: {
          path: $memory_path,
          status: $memory_status,
          tokens_estimate: $memory_tokens,
          content: $memory_content
        },
        learnings: {
          path: ".kimiflow/project/LEARNINGS.jsonl",
          count: ($learnings | length),
          hits: $learnings
        },
        facts: {
          path: ".kimiflow/project/FACTS.jsonl",
          count: ($facts | length),
          hits: $facts
        }
      },
      omitted: $omitted
    }')"

  if [ -n "$write_path" ]; then
    case "$write_path" in
      /*) ;;
      *) write_path="$root/$write_path" ;;
    esac
    write_recall_markdown "$write_path" "$json"
  fi
  json_print "$json" "$pretty"
}

classify_text() {
  local text="$1"
  local lower words sensitivity target confidence reasons vault_allowed repo_doc_allowed sanitized_required
  lower="$(printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]')"
  words="$(printf '%s\n' "$text" | wc -w | tr -d '[:space:]')"
  sensitivity="normal"
  target="run_only"
  confidence="medium"
  reasons='[]'
  vault_allowed=true
  repo_doc_allowed=false
  sanitized_required=false

  if printf '%s\n' "$lower" | grep -Eq '(secret|token|credential|password|private key|\.env|vulnerab|exploit|auth bypass|cve-|xss|csrf|sql injection)'; then
    sensitivity="security"
    vault_allowed=false
    repo_doc_allowed=false
    sanitized_required=true
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["security_sensitive"]')"
  elif printf '%s\n' "$lower" | grep -Eq '(/users/|/home/|customer|client|kunde|kundendaten|private|vault|obsidian)'; then
    sensitivity="private"
    vault_allowed=true
    repo_doc_allowed=false
    sanitized_required=true
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["private_or_local_detail"]')"
  fi

  if [ "$words" -lt 4 ] || printf '%s\n' "$lower" | grep -Eq '^(ok|done|fixed|typo|scratch|temporary)$'; then
    target="skip"
    confidence="high"
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["too_small_or_trivial"]')"
  elif printf '%s\n' "$lower" | grep -Eq '(readme|repo doc|documentation|docs/|architecture doc|onboarding|public docs|publish-safe)'; then
    target="repo_doc_candidate"
    if [ "$sensitivity" = "normal" ] || [ "$sensitivity" = "public" ]; then
      repo_doc_allowed=true
    fi
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["documentation_candidate"]')"
  elif printf '%s\n' "$lower" | grep -Eq '(cross-project|preference|always|remember|pattern|lesson|decision|learned|wiederkehrend|arbeitsstil|vault)'; then
    target="vault"
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["long_term_or_cross_project"]')"
  elif printf '%s\n' "$lower" | grep -Eq '(test|build|release|convention|standard|decision|architecture|flow|hook|launcher|codex|claude|project map|memory|vault|kimiflow)'; then
    target="project_memory"
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["project_reusable"]')"
  fi

  if [ "$sensitivity" = "security" ]; then
    target="project_memory"
    confidence="high"
  fi

  jq -n \
    --arg target "$target" \
    --arg sensitivity "$sensitivity" \
    --arg confidence "$confidence" \
    --argjson reasons "$reasons" \
    --argjson vault_allowed "$vault_allowed" \
    --argjson repo_doc_allowed "$repo_doc_allowed" \
    --argjson sanitized_required "$sanitized_required" \
    '{
      schema_version: 1,
      classification: {
        target: $target,
        sensitivity: $sensitivity,
        confidence: $confidence,
        reasons: $reasons,
        vault_allowed: $vault_allowed,
        repo_doc_allowed: $repo_doc_allowed,
        sanitized_required: $sanitized_required
      }
    }'
}

cmd_classify() {
  local input="" text="" pretty=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --input) shift; input="${1:-}" ;;
      --text) shift; text="${1:-}" ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "classify: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  if [ -n "$input" ]; then
    [ -f "$input" ] || die "input not found: $input" 2
    text="$(sed -n '1,160p' "$input")"
  fi
  [ -n "$text" ] || die "classify requires --input or --text" 2
  json_print "$(classify_text "$text")" "$pretty"
}

slugify() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '-' \
    | sed 's/^-//; s/-$//; s/--*/-/g' \
    | cut -c1-40
}

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    git hash-object "$file" 2>/dev/null || printf 'NOT AVAILABLE'
  fi
}

evidence_file_path() {
  local root="$1" ref="$2" ref_path
  ref_path="$(printf '%s' "$ref" | sed -E 's/:[0-9]+$//')"
  case "$ref_path" in
    /*) printf '%s' "$ref_path" ;;
    *) printf '%s/%s' "$root" "$ref_path" ;;
  esac
}

evidence_fingerprints_json() {
  local root="$1" evidence_json="$2"
  local out='[]' ref path rel status sha
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    path="$(evidence_file_path "$root" "$ref")"
    rel="$(rel_path "$root" "$path")"
    status="missing"
    sha=""
    if [ -f "$path" ]; then
      status="current"
      sha="$(sha256_file "$path")"
    fi
    out="$(printf '%s\n' "$out" | jq \
      --arg ref "$ref" \
      --arg path "$rel" \
      --arg sha "$sha" \
      --arg status "$status" \
      '. + [{ref: $ref, path: $path, sha256: $sha, status: $status}]')"
  done < <(printf '%s\n' "$evidence_json" | jq -r '.[]?')
  printf '%s\n' "$out" | jq -c .
}

quality_gate_json() {
  local kind="$1" summary="$2" evidence_json="$3"
  local lower words reasons='[]'
  lower="$(printf '%s\n' "$summary" | tr '[:upper:]' '[:lower:]')"
  words="$(printf '%s\n' "$summary" | tr -cs '[:alnum:]_-' '\n' | awk 'length($0) > 0 {n++} END{print n+0}')"

  if [ "$words" -lt 7 ]; then
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["too_short"]')"
  fi
  if printf '%s\n' "$lower" | grep -Eq '^(done|fixed|updated|changed|implemented|cleanup|misc|note|todo)[[:punct:][:space:]]*$|(^|[[:space:]])(various|several|stuff|things|something|some files)([[:space:]]|$)'; then
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["too_generic"]')"
  fi
  if [ "$(printf '%s\n' "$evidence_json" | jq 'length')" -eq 0 ] || printf '%s\n' "$evidence_json" | jq -e 'any(.[]; . == "NOT VERIFIED")' >/dev/null; then
    reasons="$(printf '%s\n' "$reasons" | jq '. + ["missing_verified_evidence"]')"
  fi

  case "$kind" in
    project_rule_confirmed)
      if ! printf '%s\n' "$lower" | grep -Eq '(rule|confirmed|every|must|always|convention|standard|should|regel|bestätigt|bestaetigt|muss|immer|jede|jedes|konvention)'; then
        reasons="$(printf '%s\n' "$reasons" | jq '. + ["project_rule_without_rule"]')"
      fi
      ;;
    trap_or_pitfall)
      if ! printf '%s\n' "$lower" | grep -Eq '(pitfall|trap|avoid|risk|do not|don'\''t|never|falle|risiko|vermeiden|nicht|niemals|achtung|surprise)'; then
        reasons="$(printf '%s\n' "$reasons" | jq '. + ["pitfall_without_avoidance"]')"
      fi
      ;;
    important_decision)
      if ! printf '%s\n' "$lower" | grep -Eq '(decision|decided|choose|chosen|keep|use|because|trade-off|instead|entscheidung|entschieden|bleibt|nutzen|beibehalten)'; then
        reasons="$(printf '%s\n' "$reasons" | jq '. + ["decision_without_decision"]')"
      fi
      ;;
  esac

  jq -n \
    --argjson reasons "$reasons" \
    --argjson words "$words" \
    '{
      ok: (($reasons | length) == 0),
      words: $words,
      reasons: $reasons
    }'
}

append_learning_row() {
  local root="$1" kind="$2" scope="$3" topic="$4" summary="$5" evidence_json="$6" confidence="$7" sensitivity="$8" status="$9"
  local project learnings fingerprints_json source_commit id row
  project="$root/.kimiflow/project"
  learnings="$project/LEARNINGS.jsonl"
  mkdir -p "$project"
  fingerprints_json="$(evidence_fingerprints_json "$root" "$evidence_json")"
  if [ -f "$learnings" ]; then
    local existing_id
    existing_id="$(jq -Rsc -r \
      --arg kind "$kind" \
      --arg scope "$scope" \
      --arg topic "$topic" \
      --arg summary "$summary" \
      --argjson evidence "$evidence_json" \
      --argjson fingerprints "$fingerprints_json" \
      '
        split("\n")
        | map(select(length > 0) | (fromjson? // empty))
        | map(select(
            (.kind // "") == $kind
            and (.scope // "") == $scope
            and (.topic // "") == $topic
            and (.summary // "") == $summary
            and ((.evidence // []) == $evidence)
            and ((.evidence_fingerprints // []) == $fingerprints)
            and ((.status // "current") == "current")
          ))
        | .[0].id // ""
      ' "$learnings")"
    if [ -n "$existing_id" ]; then
      printf '%s' "$existing_id"
      return 0
    fi
  fi
  source_commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || printf 'NOT VERIFIED')"
  id="learn_$(date -u +%Y%m%d)_$(slugify "$topic")_$$"
  row="$(jq -nc \
    --arg id "$id" \
    --arg kind "$kind" \
    --arg scope "$scope" \
    --arg topic "$topic" \
    --arg summary "$summary" \
    --argjson evidence "$evidence_json" \
    --argjson evidence_fingerprints "$fingerprints_json" \
    --arg confidence "$confidence" \
    --arg sensitivity "$sensitivity" \
    --arg last_verified "$(date_now)" \
    --arg source_commit "$source_commit" \
    --arg status "$status" \
    '{
      id: $id,
      kind: $kind,
      scope: $scope,
      topic: $topic,
      summary: $summary,
      evidence: $evidence,
      evidence_fingerprints: $evidence_fingerprints,
      confidence: $confidence,
      sensitivity: $sensitivity,
      last_verified: $last_verified,
      source_commit: $source_commit,
      status: $status
    }')"
  printf '%s\n' "$row" >> "$learnings"
  printf '%s' "$id"
}

rel_path() {
  local root="$1" path="$2"
  case "$path" in
    "$root"/*) printf '%s' "${path#"$root"/}" ;;
    "$root") printf '.' ;;
    *) printf '%s' "$path" ;;
  esac
}

resolve_run_dir() {
  local root="$1" run="$2"
  [ -n "$run" ] || die "run path required" 2
  case "$run" in
    /*) ;;
    *) run="$root/$run" ;;
  esac
  (cd "$run" 2>/dev/null && pwd) || die "run directory not found: $run" 2
}

first_substantive_line() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (line ~ /^#{1,6}[[:space:]]/) next
      if (line ~ /^```/) next
      gsub(/[[:space:]]+/, " ", line)
      print line
      exit
    }
  ' "$file"
}

review_candidate_json() {
  local root="$1" run_dir="$2" question="$3" kind="$4" topic="$5"
  shift 5
  local file path summary rel evidence_json classification target sensitivity confidence quality
  for file in "$@"; do
    path="$run_dir/$file"
    [ -f "$path" ] || continue
    summary="$(first_substantive_line "$path" | cut -c1-320)"
    [ -n "$summary" ] || continue
    rel="$(rel_path "$root" "$path")"
    evidence_json="$(jq -nc --arg evidence "$rel:1" '[$evidence]')"
    classification="$(classify_text "$summary")"
    target="$(printf '%s\n' "$classification" | jq -r '.classification.target')"
    sensitivity="$(printf '%s\n' "$classification" | jq -r '.classification.sensitivity')"
    confidence="$(printf '%s\n' "$classification" | jq -r '.classification.confidence')"
    [ "$target" = "skip" ] && continue
    [ "$target" = "run_only" ] && target="project_memory"
    quality="$(quality_gate_json "$kind" "$summary" "$evidence_json")"
    jq -nc \
      --arg question "$question" \
      --arg kind "$kind" \
      --arg scope "project" \
      --arg topic "$topic" \
      --arg summary "$summary" \
      --argjson evidence "$evidence_json" \
      --arg target "$target" \
      --arg sensitivity "$sensitivity" \
      --arg confidence "$confidence" \
      --argjson quality "$quality" \
      '{
        question: $question,
        kind: $kind,
        scope: $scope,
        topic: $topic,
        summary: $summary,
        evidence: $evidence,
        target: $target,
        sensitivity: $sensitivity,
        confidence: $confidence,
        quality: $quality
      }'
    return 0
  done
  return 1
}

write_bounded_memory() {
  local root="$1" budget="${KIMIFLOW_MEMORY_BUDGET:-900}"
  local project memory learnings body max_items words
  project="$root/.kimiflow/project"
  memory="$project/MEMORY.md"
  learnings="$project/LEARNINGS.jsonl"
  [ -f "$learnings" ] || return 0
  mkdir -p "$project"

  max_items=8
  while :; do
    body="$(jq -Rsc --argjson max "$max_items" '
      split("\n")
      | map(select(length > 0) | (fromjson? // empty))
      | map(select((.status // "current") == "current"))
      | map(select((.sensitivity // "normal") != "security" and (.sensitivity // "normal") != "private"))
      | reverse
      | .[:$max]
      | reverse
      | map("- [" + (.topic // "uncategorized") + " · " + (.kind // "learning") + "] " + ((.summary // "") | tostring | .[0:220]) + " (evidence: " + (((.evidence // []) | .[0] // "NOT VERIFIED") | tostring) + ")")
      | join("\n")
    ' "$learnings")"
    {
      printf '# Project Memory\n\n'
      printf 'Generated: %s\n' "$(iso_now)"
      printf 'Policy: bounded always-on summary; raw/private/security learnings stay in LEARNINGS.jsonl and are recalled on demand.\n\n'
      printf '## Always-On Learnings\n\n'
      if [ -n "$body" ]; then
        printf '%s\n' "$body"
      else
        printf 'No publish-safe always-on learnings yet. Use LEARNINGS.jsonl recall on demand.\n'
      fi
    } > "$memory"
    words="$(word_count_file "$memory")"
    [ "$words" -le "$budget" ] && break
    [ "$max_items" -le 2 ] && break
    max_items=$((max_items - 2))
  done
}

write_learning_review_markdown() {
  local path="$1" run_rel="$2" status="$3" entries="$4" skip_reason="$5"
  mkdir -p "$(dirname "$path")"
  {
    printf '# Learning Review\n\n'
    printf 'Run: %s\n' "$run_rel"
    printf 'Status: %s\n' "$status"
    printf 'Generated: %s\n\n' "$(iso_now)"
    if [ "$status" = "skipped" ]; then
      printf 'Skip reason: %s\n' "$skip_reason"
    else
      printf '## Four Questions\n\n'
      printf '%s\n' "$entries" | jq -r '
        .[] |
        "### " + .question + "\n" +
        "Summary: " + (.summary // "") + "\n" +
        "Kind: " + (.kind // "") + "\n" +
        "Target: " + (.target // "") + "\n" +
        "Sensitivity: " + (.sensitivity // "") + "\n" +
        "Quality: " + (if (.quality.ok // false) then "passed" else "failed:" + (((.quality.reasons // []) | join(","))) end) + "\n" +
        "Evidence:\n" + (((.evidence // []) | map("- " + .) | join("\n"))) + "\n" +
        "Recorded: " + (.recorded_id // "pending") + "\n"
      '
    fi
  } > "$path"
}

cmd_review_run() {
  local root="" run="" pretty=0 write=0 skip_reason=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --run) shift; run="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --skip) shift; skip_reason="${1:-}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "review-run: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  local run_dir run_rel review candidate entries recorded count i entry kind scope topic summary evidence_json confidence sensitivity id out memory_updated
  run_dir="$(resolve_run_dir "$root" "$run")"
  run_rel="$(rel_path "$root" "$run_dir")"
  review="$run_dir/LEARNING-REVIEW.md"
  memory_updated=false

  if [ -n "$skip_reason" ]; then
    if [ "$write" -eq 1 ]; then
      write_learning_review_markdown "$review" "$run_rel" "skipped" "[]" "$skip_reason"
    fi
    out="$(jq -n \
      --arg run "$run_rel" \
      --arg review_path "$(rel_path "$root" "$review")" \
      --arg reason "$skip_reason" \
      --argjson written "$write" \
      '{
        schema_version: 1,
        status: "skipped",
        run: $run,
        review_path: $review_path,
        skip_reason: $reason,
        written: ($written == 1),
        entries: [],
        recorded_count: 0,
        memory_updated: false
      }')"
    json_print "$out" "$pretty"
    return 0
  fi

  entries='[]'
  candidate="$(review_candidate_json "$root" "$run_dir" "what_was_learned" "learned" "run-learning" RESEARCH.md DIAGNOSIS.md VERIFICATION.md)" \
    && entries="$(printf '%s\n' "$entries" | jq --argjson item "$candidate" '. + [$item]')"
  candidate="$(review_candidate_json "$root" "$run_dir" "which_project_rule_was_confirmed" "project_rule_confirmed" "project-rules" ACCEPTANCE.md STANDARDS.md PLAN.md)" \
    && entries="$(printf '%s\n' "$entries" | jq --argjson item "$candidate" '. + [$item]')"
  candidate="$(review_candidate_json "$root" "$run_dir" "which_trap_or_pitfall_appeared" "trap_or_pitfall" "pitfalls" CODE-REVIEW.md ADVISORIES.md CURRENT-STATE.md)" \
    && entries="$(printf '%s\n' "$entries" | jq --argjson item "$candidate" '. + [$item]')"
  candidate="$(review_candidate_json "$root" "$run_dir" "which_decision_remains_important" "important_decision" "decisions" PLAN.md RESEARCH.md DIAGNOSIS.md)" \
    && entries="$(printf '%s\n' "$entries" | jq --argjson item "$candidate" '. + [$item]')"

  count="$(printf '%s\n' "$entries" | jq 'length')"
  [ "$count" -gt 0 ] || die "review-run found no reusable learning candidates; pass --skip <reason> if this run is intentionally trivial" 1

  local quality_failures quality_summary
  quality_failures="$(printf '%s\n' "$entries" | jq '[.[] | select((.quality.ok // false) != true)]')"
  if [ "$(printf '%s\n' "$quality_failures" | jq 'length')" -gt 0 ]; then
    quality_summary="$(printf '%s\n' "$quality_failures" | jq -r 'map(.question + ":" + ((.quality.reasons // []) | join(","))) | join(";")')"
    die "review-run quality gate closed: $quality_summary" 1
  fi

  if [ "$write" -eq 1 ]; then
    recorded='[]'
    i=0
    while [ "$i" -lt "$count" ]; do
      entry="$(printf '%s\n' "$entries" | jq -c ".[$i]")"
      kind="$(printf '%s\n' "$entry" | jq -r '.kind')"
      scope="$(printf '%s\n' "$entry" | jq -r '.scope')"
      topic="$(printf '%s\n' "$entry" | jq -r '.topic')"
      summary="$(printf '%s\n' "$entry" | jq -r '.summary')"
      evidence_json="$(printf '%s\n' "$entry" | jq -c '.evidence')"
      confidence="$(printf '%s\n' "$entry" | jq -r '.confidence')"
      sensitivity="$(printf '%s\n' "$entry" | jq -r '.sensitivity')"
      id="$(append_learning_row "$root" "$kind" "$scope" "$topic" "$summary" "$evidence_json" "$confidence" "$sensitivity" "current")"
      entry="$(printf '%s\n' "$entry" | jq --arg id "$id" '. + {recorded_id: $id}')"
      recorded="$(printf '%s\n' "$recorded" | jq --argjson item "$entry" '. + [$item]')"
      i=$((i + 1))
    done
    entries="$recorded"
    write_bounded_memory "$root"
    memory_updated=true
    cmd_curate --root "$root" --write >/dev/null
    write_learning_review_markdown "$review" "$run_rel" "recorded" "$entries" ""
  fi

  out="$(jq -n \
    --arg run "$run_rel" \
    --arg review_path "$(rel_path "$root" "$review")" \
    --argjson entries "$entries" \
    --argjson written "$write" \
    --argjson memory_updated "$memory_updated" \
    '{
      schema_version: 1,
      status: (if $written == 1 then "recorded" else "preview" end),
      run: $run,
      review_path: $review_path,
      written: ($written == 1),
      entries: $entries,
      recorded_count: ($entries | map(select(.recorded_id != null)) | length),
      memory_updated: $memory_updated
    }')"
  json_print "$out" "$pretty"
}

cmd_verify_run() {
  local root="" run=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --run) shift; run="${1:-}" ;;
      --help|-h) usage; exit 0 ;;
      *) die "verify-run: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  local run_dir review status reason learnings ids_json ids_count missing_ids missing_csv freshness_failures freshness_csv id row stored_fingerprints current_fingerprints evidence_json
  run_dir="$(resolve_run_dir "$root" "$run")"
  review="$run_dir/LEARNING-REVIEW.md"
  if [ ! -f "$review" ]; then
    printf 'LEARNING_REVIEW\tCLOSED\treason=missing_review\tpath=%s\n' "$(rel_path "$root" "$review")"
    return 1
  fi
  status="$(awk -F': ' '/^Status:/ {print $2; exit}' "$review")"
  case "$status" in
    recorded)
      ids_json="$(awk '/^Recorded:[[:space:]]+learn_/ {print $2}' "$review" | jq -R . | jq -s .)"
      ids_count="$(printf '%s\n' "$ids_json" | jq 'length')"
      if [ "$ids_count" -eq 0 ]; then
        printf 'LEARNING_REVIEW\tCLOSED\treason=missing_recorded_ids\tpath=%s\n' "$(rel_path "$root" "$review")"
        return 1
      fi
      learnings="$root/.kimiflow/project/LEARNINGS.jsonl"
      if [ ! -f "$learnings" ]; then
        printf 'LEARNING_REVIEW\tCLOSED\treason=missing_learnings\tpath=%s\n' "$(rel_path "$root" "$review")"
        return 1
      fi
      missing_ids="$(jq -Rsc --argjson ids "$ids_json" '
        (
          split("\n")
          | map(select(length > 0) | (fromjson? // empty))
          | map(select((.status // "current") == "current") | .id)
        ) as $current
        | [$ids[] | . as $id | select(($current | index($id)) == null)]
      ' "$learnings")"
      if [ "$(printf '%s\n' "$missing_ids" | jq 'length')" -eq 0 ]; then
        freshness_failures='[]'
        while IFS= read -r id; do
          [ -n "$id" ] || continue
          row="$(jq -Rsc -c --arg id "$id" '
            split("\n")
            | map(select(length > 0) | (fromjson? // empty))
            | map(select((.status // "current") == "current" and (.id // "") == $id))
            | .[0] // {}
          ' "$learnings")"
          evidence_json="$(printf '%s\n' "$row" | jq -c '.evidence // []')"
          stored_fingerprints="$(printf '%s\n' "$row" | jq -c '.evidence_fingerprints // []')"
          if [ "$(printf '%s\n' "$stored_fingerprints" | jq 'length')" -eq 0 ]; then
            freshness_failures="$(printf '%s\n' "$freshness_failures" | jq --arg id "$id" '. + [{id: $id, reason: "missing_evidence_fingerprints"}]')"
            continue
          fi
          current_fingerprints="$(evidence_fingerprints_json "$root" "$evidence_json")"
          if [ "$stored_fingerprints" != "$current_fingerprints" ]; then
            freshness_failures="$(printf '%s\n' "$freshness_failures" | jq --arg id "$id" '. + [{id: $id, reason: "evidence_changed_or_missing"}]')"
          fi
        done < <(printf '%s\n' "$ids_json" | jq -r '.[]')
        if [ "$(printf '%s\n' "$freshness_failures" | jq 'length')" -eq 0 ]; then
          printf 'LEARNING_REVIEW\tOPEN\tstatus=recorded\tfreshness=current\tpath=%s\n' "$(rel_path "$root" "$review")"
          return 0
        fi
        freshness_csv="$(printf '%s\n' "$freshness_failures" | jq -r 'map(.id + ":" + .reason) | join(",")')"
        printf 'LEARNING_REVIEW\tCLOSED\treason=evidence_stale\tids=%s\tpath=%s\n' "$freshness_csv" "$(rel_path "$root" "$review")"
        return 1
      fi
      missing_csv="$(printf '%s\n' "$missing_ids" | jq -r 'join(",")')"
      printf 'LEARNING_REVIEW\tCLOSED\treason=recorded_ids_missing_or_not_current\tids=%s\tpath=%s\n' "$missing_csv" "$(rel_path "$root" "$review")"
      return 1
      ;;
    skipped)
      reason="$(awk -F': ' '/^Skip reason:/ {print $2; exit}' "$review")"
      if [ -n "$reason" ]; then
        printf 'LEARNING_REVIEW\tOPEN\tstatus=skipped\treason=%s\tpath=%s\n' "$reason" "$(rel_path "$root" "$review")"
        return 0
      fi
      printf 'LEARNING_REVIEW\tCLOSED\treason=missing_skip_reason\tpath=%s\n' "$(rel_path "$root" "$review")"
      return 1
      ;;
    *)
      printf 'LEARNING_REVIEW\tCLOSED\treason=invalid_status\tstatus=%s\tpath=%s\n' "${status:-missing}" "$(rel_path "$root" "$review")"
      return 1
      ;;
  esac
}

cmd_record() {
  local root="" summary="" topic="" kind="learning" scope="project" confidence="medium" sensitivity="normal" status="current"
  local evidence_json='[]'
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --summary) shift; summary="${1:-}" ;;
      --topic) shift; topic="${1:-}" ;;
      --kind) shift; kind="${1:-}" ;;
      --scope) shift; scope="${1:-}" ;;
      --confidence) shift; confidence="${1:-}" ;;
      --sensitivity) shift; sensitivity="${1:-}" ;;
      --status) shift; status="${1:-}" ;;
      --evidence) shift; evidence_json="$(printf '%s\n' "$evidence_json" | jq --arg value "${1:-}" '. + [$value]')" ;;
      --help|-h) usage; exit 0 ;;
      *) die "record: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  [ -n "$summary" ] || die "record requires --summary" 2
  [ -n "$topic" ] || die "record requires --topic" 2
  [ "$(printf '%s\n' "$evidence_json" | jq 'length')" -gt 0 ] || die "record requires at least one --evidence" 2
  root="$(resolve_root "$root")"

  local id
  id="$(append_learning_row "$root" "$kind" "$scope" "$topic" "$summary" "$evidence_json" "$confidence" "$sensitivity" "$status")"
  printf 'RECORDED\t%s\t%s\n' ".kimiflow/project/LEARNINGS.jsonl" "$id"
}

repo_id() {
  local root="$1" remote
  remote="$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "$remote" ]; then
    printf '%s\n' "$remote" | sed -E 's#^git@github.com:#github.com/#; s#^https://##; s#\.git$##'
  else
    printf 'unknown'
  fi
}

cmd_curate() {
  local root="" pretty=0 write=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "curate: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"

  local project memory learnings index status learning_summary vault existing_vault topics out
  project="$root/.kimiflow/project"
  memory="$project/MEMORY.md"
  learnings="$project/LEARNINGS.jsonl"
  index="$project/MEMORY-INDEX.json"
  status="$(status_json "$root")"
  learning_summary="$(read_jsonl_summary "$learnings")"
  vault="$(vault_status_json "$index")"
  topics='{}'
  if [ -f "$learnings" ]; then
    topics="$(jq -Rsc '
      split("\n")
      | map(select(length > 0) | (fromjson? // empty))
      | map(select((.status // "current") == "current"))
      | sort_by(.topic // "uncategorized")
      | group_by(.topic // "uncategorized")
      | map({key: (.[0].topic // "uncategorized"), value: map(.id)})
      | from_entries
    ' "$learnings")"
  fi

  existing_vault="$vault"
  out="$(jq -n \
    --arg updated_at "$(iso_now)" \
    --arg repo_id "$(repo_id "$root")" \
    --arg language "de" \
    --argjson tokens "$(word_count_file "$memory")" \
    --argjson learnings "$learning_summary" \
    --argjson vault "$existing_vault" \
    --argjson topics "$topics" \
    --argjson status "$status" \
    '{
      schema_version: 1,
      updated_at: $updated_at,
      repo_id: $repo_id,
      language: $language,
      always_on_memory_tokens_estimate: $tokens,
      vault: $vault,
      learnings: $learnings,
      topics: $topics,
      curation: $status.curation
    }')"

  if [ "$write" -eq 1 ]; then
    mkdir -p "$project"
    printf '%s\n' "$out" | jq . > "$index"
  fi
  json_print "$out" "$pretty"
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 2; }
shift

case "$cmd" in
  status) cmd_status "$@" ;;
  recall) cmd_recall "$@" ;;
  classify) cmd_classify "$@" ;;
  record) cmd_record "$@" ;;
  review-run) cmd_review_run "$@" ;;
  verify-run) cmd_verify_run "$@" ;;
  curate) cmd_curate "$@" ;;
  --help|-h|help) usage; exit 0 ;;
  *) die "unknown command: $cmd" 2 ;;
esac
