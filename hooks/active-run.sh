#!/usr/bin/env bash
# kimiflow — active session contract helper and hooks.
#
# Orchestrator commands:
#   active-run.sh status [--root <path>] [--pretty]
#   active-run.sh start --run <path> [--root <path>] [--mode <mode>] [--scope <scope>] [--host <host>] [--write] [--pretty]
#   active-run.sh append-item --title <text> [--kind <kind>] [--root <path>] [--write] [--pretty]
#   active-run.sh mark-built|mark-accepted --id <id> [--root <path>] [--write] [--pretty]
#   active-run.sh mark-rejected|drop-item --id <id> --reason <text> [--root <path>] [--write] [--pretty]
#   active-run.sh refresh-baseline [--root <path>] [--write] [--pretty]
#   active-run.sh finish [--root <path>] [--write] [--skip-learning <reason>] [--pretty]
#   active-run.sh park|fail|abort [--root <path>] --reason <text> [--write] [--pretty]
#
# Hook commands:
#   active-run.sh prompt-context
#   active-run.sh stop-gate
set -u

usage() {
  sed -n '1,19p' "$0" >&2
}

die() {
  printf 'active-run: %s\n' "$1" >&2
  exit "${2:-1}"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required" 2
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

resolve_root() {
  local root="$1"
  if [ -n "$root" ]; then
    (cd "$root" 2>/dev/null && pwd) || printf '%s' "$root"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

rel_path() {
  local root="$1" path="$2"
  case "$path" in
    "$root"/*) printf '%s\n' "${path#"$root"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

json_print() {
  local json="$1" pretty="$2"
  if [ "$pretty" -eq 1 ]; then
    printf '%s\n' "$json" | jq .
  else
    printf '%s\n' "$json" | jq -c .
  fi
}

active_file() {
  printf '%s/.kimiflow/session/ACTIVE_RUN.json\n' "$1"
}

resolve_run_dir() {
  local root="$1" run="$2" path
  [ -n "$run" ] || die "run path is required" 2
  case "$run" in
    .kimiflow/*) path="$root/$run" ;;
    "$root"/.kimiflow/*) path="$run" ;;
    *) die "run path must be under .kimiflow/<slug>" 2 ;;
  esac
  case "$path" in
    *"/../"*|*"/.."|*"/./"*) die "run path must not contain relative traversal" 2 ;;
  esac
  printf '%s\n' "$path"
}

state_value() {
  local file="$1" label="$2"
  awk -v label="$label" '
    {
      line = $0
      gsub(/\r/, "", line)
      gsub(/\*\*/, "", line)
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      if (line ~ "^" label ":[[:space:]]*") {
        sub("^" label ":[[:space:]]*", "", line)
        print line
        exit
      }
    }
  ' "$file" 2>/dev/null
}

pathish_affected_entry() {
  case "$1" in
    */*|*.*|Dockerfile|Containerfile|Makefile|Procfile|Justfile|Rakefile|Gemfile|Vagrantfile) return 0 ;;
    *) return 1 ;;
  esac
}

affected_paths_json() {
  local state="$1" json='[]' path
  [ -f "$state" ] || { printf '[]'; return 0; }
  while IFS= read -r path; do
    path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$path" ] || continue
    pathish_affected_entry "$path" || continue
    json="$(printf '%s\n' "$json" | jq --arg path "$path" 'if index($path) then . else . + [$path] end')"
  done < <(
    awk '
      {
        line = $0
        gsub(/\r/, "", line)
        gsub(/\*\*/, "", line)
        plain = line
        sub(/^[[:space:]]*-[[:space:]]*/, "", plain)
        if (plain ~ /^(Affected files|Affected paths):[[:space:]]*/) {
          sub(/^(Affected files|Affected paths):[[:space:]]*/, "", plain)
          if (length(plain) > 0) {
            n = split(plain, parts, /,[[:space:]]*/)
            for (i = 1; i <= n; i++) print parts[i]
          }
          in_list = 1
          next
        }
        if (in_list && line ~ /^[[:space:]]*-[[:space:]]+/) {
          sub(/^[[:space:]]*-[[:space:]]+/, "", line)
          print line
          next
        }
        if (in_list && line !~ /^[[:space:]]*$/) in_list = 0
      }
    ' "$state" 2>/dev/null
  )
  printf '%s\n' "$json"
}

git_head() {
  local root="$1"
  git -C "$root" rev-parse HEAD 2>/dev/null || printf 'NOT VERIFIED'
}

git_commit_ok() {
  local root="$1" commit="$2"
  [ -n "$commit" ] && [ "$commit" != "NOT VERIFIED" ] || return 1
  git -C "$root" cat-file -e "$commit^{commit}" >/dev/null 2>&1
}

changed_paths_json() {
  local root="$1" base="$2" json='[]' path
  if git_commit_ok "$root" "$base"; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      json="$(printf '%s\n' "$json" | jq --arg path "$path" 'if index($path) then . else . + [$path] end')"
    done < <(
      {
        git -C "$root" diff --name-only "$base"..HEAD 2>/dev/null
        git -C "$root" diff --name-only --cached 2>/dev/null
        git -C "$root" diff --name-only 2>/dev/null
        git -C "$root" ls-files --others --exclude-standard 2>/dev/null
      } | sort -u
    )
  fi
  printf '%s\n' "$json"
}

path_matches() {
  local changed="$1" affected="$2"
  case "$affected" in
    *"*"*|*"?"*)
      [[ "$changed" == $affected ]]
      ;;
    *)
      [ "$changed" = "$affected" ] && return 0
      case "$changed" in "$affected"/*) return 0 ;; esac
      return 1
      ;;
  esac
}

stale_json() {
  local root="$1" base="$2" affected_json="$3" changed_json risk='current' relevant='[]' changed affected changed_count affected_count
  if ! git_commit_ok "$root" "$base"; then
    jq -n '{risk: "unknown", changed_paths: [], relevant_changed_paths: [], reason: "baseline_missing"}'
    return 0
  fi
  changed_json="$(changed_paths_json "$root" "$base")"
  changed_count="$(printf '%s\n' "$changed_json" | jq 'length')"
  affected_count="$(printf '%s\n' "$affected_json" | jq 'length')"
  if [ "$changed_count" -gt 0 ] && [ "$affected_count" -eq 0 ]; then
    jq -n \
      --argjson changed "$changed_json" \
      '{
        risk: "unknown",
        changed_paths: $changed,
        relevant_changed_paths: [],
        reason: "affected_paths_unknown"
      }'
    return 0
  fi
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    while IFS= read -r affected; do
      [ -n "$affected" ] || continue
      if path_matches "$changed" "$affected"; then
        relevant="$(printf '%s\n' "$relevant" | jq --arg path "$changed" 'if index($path) then . else . + [$path] end')"
      fi
    done < <(printf '%s\n' "$affected_json" | jq -r '.[]?')
  done < <(printf '%s\n' "$changed_json" | jq -r '.[]?')
  if [ "$(printf '%s\n' "$relevant" | jq 'length')" -gt 0 ]; then
    risk="needs_revalidation"
  fi
  jq -n \
    --arg risk "$risk" \
    --argjson changed "$changed_json" \
    --argjson relevant "$relevant" \
    '{
      risk: $risk,
      changed_paths: $changed,
      relevant_changed_paths: $relevant,
      reason: (if $risk == "needs_revalidation" then "affected_paths_changed" else "current" end)
    }'
}

items_path_for_run() {
  printf '%s/ITEMS.jsonl\n' "$1"
}

items_rows_json() {
  local file="$1"
  if [ -f "$file" ]; then
    jq -Rsc 'split("\n") | map(select(length > 0) | (fromjson? // empty))' "$file"
  else
    jq -n '[]'
  fi
}

item_counts_json() {
  local file="$1"
  items_rows_json "$file" | jq '{
    total: length,
    pending: (map(select((.status // "") == "pending")) | length),
    built: (map(select((.status // "") == "built")) | length),
    accepted: (map(select((.status // "") == "accepted")) | length),
    rejected: (map(select((.status // "") == "rejected")) | length),
    dropped: (map(select((.status // "") == "dropped")) | length),
    open: (map(select((.status // "") == "pending" or (.status // "") == "built" or (.status // "") == "rejected")) | length)
  }'
}

load_active_json() {
  local root="$1" file
  file="$(active_file "$root")"
  if [ ! -f "$file" ]; then
    jq -n '{present: false, status: "none"}'
    return 0
  fi
  if ! jq -e . "$file" >/dev/null 2>&1; then
    jq -n --arg path ".kimiflow/session/ACTIVE_RUN.json" '{present: true, status: "invalid", path: $path}'
    return 0
  fi
  jq '. + {present: true}' "$file"
}

status_json() {
  local root="$1" active run_rel run_dir state affected_json base stale items counts
  active="$(load_active_json "$root")"
  if ! printf '%s\n' "$active" | jq -e '.present == true and .status != "invalid"' >/dev/null 2>&1; then
    jq -n --argjson active "$active" '{
      schema_version: 1,
      present: ($active.present == true),
      status: ($active.status // "none"),
      active_file: ".kimiflow/session/ACTIVE_RUN.json",
      run: null,
      item_counts: {total: 0, pending: 0, built: 0, accepted: 0, rejected: 0, dropped: 0, open: 0},
      stale_risk: "none",
      stale: {risk: "none", changed_paths: [], relevant_changed_paths: [], reason: "no_active_session"},
      terminal: true
    }'
    return 0
  fi

  run_rel="$(printf '%s\n' "$active" | jq -r '.run // empty')"
  run_dir="$(resolve_run_dir "$root" "$run_rel")"
  state="$run_dir/STATE.md"
  affected_json="$(affected_paths_json "$state")"
  base="$(printf '%s\n' "$active" | jq -r '.last_checked_head // .started_head // "NOT VERIFIED"')"
  stale="$(stale_json "$root" "$base" "$affected_json")"
  items="$(items_path_for_run "$run_dir")"
  counts="$(item_counts_json "$items")"

  jq -n \
    --argjson active "$active" \
    --arg run "$run_rel" \
    --arg active_file ".kimiflow/session/ACTIVE_RUN.json" \
    --arg items_path "$(rel_path "$root" "$items")" \
    --arg state_path "$(rel_path "$root" "$state")" \
    --argjson affected "$affected_json" \
    --argjson counts "$counts" \
    --argjson stale "$stale" \
    '{
      schema_version: 1,
      present: true,
      status: ($active.status // "active"),
      active_file: $active_file,
      run: $run,
      state_path: $state_path,
      items_path: $items_path,
      started_at: ($active.started_at // null),
      started_head: ($active.started_head // "NOT VERIFIED"),
      last_checked_head: ($active.last_checked_head // $active.started_head // "NOT VERIFIED"),
      host: ($active.host // "unknown"),
      mode: ($active.mode // ""),
      scope: ($active.scope // ""),
      affected_files: $affected,
      item_counts: $counts,
      stale_risk: ($stale.risk // "unknown"),
      stale: $stale,
      terminal: ((($active.status // "active") | IN("done","parked","failed","aborted")) == true),
      next_action: (
        if (($stale.risk // "") | IN("needs_revalidation", "unknown")) then "revalidate_then_refresh_baseline"
        elif ($counts.open // 0) > 0 then "resolve_or_accept_items"
        else "finish_or_continue"
        end
      )
    }'
}

write_active_json() {
  local root="$1" json="$2" file tmp old_umask
  file="$(active_file "$root")"
  mkdir -p "$(dirname "$file")" || return 1
  old_umask="$(umask)"
  umask 077
  tmp="$file.tmp.$$"
  printf '%s\n' "$json" | jq . > "$tmp" || { umask "$old_umask"; return 1; }
  umask "$old_umask"
  mv "$tmp" "$file"
}

rewrite_items_json() {
  local file="$1" rows="$2" tmp
  mkdir -p "$(dirname "$file")" || return 1
  tmp="$file.tmp.$$"
  printf '%s\n' "$rows" | jq -c '.[]' > "$tmp" || return 1
  mv "$tmp" "$file"
}

next_item_id() {
  local file="$1" n
  n="$(items_rows_json "$file" | jq '[.[]?.id // "" | select(test("^item_[0-9]+$")) | sub("^item_"; "") | tonumber] | max // 0')"
  printf 'item_%03d\n' $((n + 1))
}

update_state_status() {
  local run_dir="$1" status="$2" tmp
  local state="$run_dir/STATE.md"
  [ -f "$state" ] || return 0
  tmp="$state.tmp.$$"
  awk -v status="$status" '
    BEGIN { done = 0 }
    {
      line = $0
      plain = line
      gsub(/\*\*/, "", plain)
      sub(/^[[:space:]]*-[[:space:]]*/, "", plain)
      if (plain ~ /^Status:[[:space:]]*/) {
        print "Status: " status
        done = 1
      } else {
        print line
      }
    }
    END {
      if (!done) print "Status: " status
    }
  ' "$state" > "$tmp" && mv "$tmp" "$state"
}

update_state_phase7_done() {
  local run_dir="$1" tmp
  local state="$run_dir/STATE.md"
  [ -f "$state" ] || return 0
  tmp="$state.tmp.$$"
  awk '
    BEGIN { done = 0 }
    {
      line = $0
      plain = line
      gsub(/\*\*/, "", plain)
      sub(/^[[:space:]]*-[[:space:]]*/, "", plain)
      if (plain ~ /^Phase[[:space:]]+7:[[:space:]]*/) {
        print "Phase 7: done"
        done = 1
      } else {
        print line
      }
    }
    END {
      if (!done) print "Phase 7: done"
    }
  ' "$state" > "$tmp" && mv "$tmp" "$state"
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

cmd_start() {
  local root="" run="" mode="feature" scope="small" host="${KIMIFLOW_HOST:-unknown}" write=0 pretty=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --run) shift; run="${1:-}" ;;
      --mode) shift; mode="${1:-}" ;;
      --scope) shift; scope="${1:-}" ;;
      --host) shift; host="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "start: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  local run_dir run_rel now head existing status affected
  run_dir="$(resolve_run_dir "$root" "$run")"
  run_rel="$(rel_path "$root" "$run_dir")"
  existing="$(status_json "$root")"
  if printf '%s\n' "$existing" | jq -e '.present == true and .terminal == false and .run != $run' --arg run "$run_rel" >/dev/null 2>&1; then
    die "another active Kimiflow session exists: $(printf '%s\n' "$existing" | jq -r '.run')" 1
  fi
  now="$(iso_now)"
  head="$(git_head "$root")"
  affected="$(affected_paths_json "$run_dir/STATE.md")"
  status="$(jq -n \
    --arg run "$run_rel" \
    --arg mode "$mode" \
    --arg scope "$scope" \
    --arg host "$host" \
    --arg now "$now" \
    --arg head "$head" \
    --argjson affected "$affected" \
    '{
      schema_version: 1,
      status: "active",
      run: $run,
      mode: $mode,
      scope: $scope,
      host: $host,
      started_at: $now,
      updated_at: $now,
      started_head: $head,
      last_checked_head: $head,
      affected_files_at_start: $affected
  }')"
  if [ "$write" -eq 1 ]; then
    mkdir -p "$run_dir" || die "cannot create run dir: $run_rel" 1
    write_active_json "$root" "$status" || die "cannot write active session" 1
  fi
  json_print "$(status_json "$root")" "$pretty"
}

require_active_status() {
  local root="$1" status
  status="$(status_json "$root")"
  printf '%s\n' "$status" | jq -e '.present == true and .terminal == false' >/dev/null 2>&1 || die "no active Kimiflow session" 1
  printf '%s\n' "$status"
}

cmd_append_item() {
  local root="" title="" kind="change" write=0 pretty=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --title) shift; title="${1:-}" ;;
      --kind) shift; kind="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "append-item: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  [ -n "$title" ] || die "append-item requires --title" 2
  root="$(resolve_root "$root")"
  local status run_dir file id now row rows out
  status="$(require_active_status "$root")"
  run_dir="$(resolve_run_dir "$root" "$(printf '%s\n' "$status" | jq -r '.run')")"
  file="$(items_path_for_run "$run_dir")"
  id="$(next_item_id "$file")"
  now="$(iso_now)"
  row="$(jq -n --arg id "$id" --arg kind "$kind" --arg title "$title" --arg now "$now" '{
    id: $id,
    kind: $kind,
    title: $title,
    status: "pending",
    created_at: $now,
    updated_at: $now
  }')"
  if [ "$write" -eq 1 ]; then
    mkdir -p "$(dirname "$file")" || die "cannot create items dir" 1
    printf '%s\n' "$row" | jq -c . >> "$file"
  fi
  rows="$(items_rows_json "$file")"
  out="$(jq -n --arg path "$(rel_path "$root" "$file")" --argjson item "$row" --argjson rows "$rows" --argjson written "$write" '{
    status: "item_appended",
    written: ($written == 1),
    items_path: $path,
    item: $item,
    item_counts: {
      total: ($rows | length),
      open: ($rows | map(select((.status // "") == "pending" or (.status // "") == "built" or (.status // "") == "rejected")) | length)
    }
  }')"
  json_print "$out" "$pretty"
}

cmd_update_item() {
  local command="$1"; shift
  local root="" id="" reason="" write=0 pretty=0 new_status=""
  case "$command" in
    mark-built) new_status="built" ;;
    mark-accepted) new_status="accepted" ;;
    mark-rejected) new_status="rejected" ;;
    drop-item) new_status="dropped" ;;
    *) die "unknown item command: $command" 2 ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --id) shift; id="${1:-}" ;;
      --reason) shift; reason="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "$command: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  [ -n "$id" ] || die "$command requires --id" 2
  case "$new_status" in rejected|dropped) [ -n "$reason" ] || die "$command requires --reason" 2 ;; esac
  root="$(resolve_root "$root")"
  local status run_dir file rows updated now count out
  status="$(require_active_status "$root")"
  run_dir="$(resolve_run_dir "$root" "$(printf '%s\n' "$status" | jq -r '.run')")"
  file="$(items_path_for_run "$run_dir")"
  rows="$(items_rows_json "$file")"
  count="$(printf '%s\n' "$rows" | jq --arg id "$id" '[.[] | select((.id // "") == $id)] | length')"
  [ "$count" -gt 0 ] || die "item not found: $id" 1
  now="$(iso_now)"
  updated="$(printf '%s\n' "$rows" | jq \
    --arg id "$id" \
    --arg status "$new_status" \
    --arg reason "$reason" \
    --arg now "$now" \
    'map(if (.id // "") == $id then
      . + {status: $status, updated_at: $now}
      + (if $reason == "" then {} else {reason: $reason} end)
    else . end)')"
  if [ "$write" -eq 1 ]; then
    rewrite_items_json "$file" "$updated" || die "cannot update items file" 1
  fi
  out="$(jq -n --arg path "$(rel_path "$root" "$file")" --arg id "$id" --arg status "$new_status" --argjson written "$write" --argjson rows "$updated" '{
    status: "item_updated",
    written: ($written == 1),
    items_path: $path,
    id: $id,
    item_status: $status,
    item_counts: {
      total: ($rows | length),
      pending: ($rows | map(select((.status // "") == "pending")) | length),
      built: ($rows | map(select((.status // "") == "built")) | length),
      accepted: ($rows | map(select((.status // "") == "accepted")) | length),
      rejected: ($rows | map(select((.status // "") == "rejected")) | length),
      dropped: ($rows | map(select((.status // "") == "dropped")) | length),
      open: ($rows | map(select((.status // "") == "pending" or (.status // "") == "built" or (.status // "") == "rejected")) | length)
    }
  }')"
  json_print "$out" "$pretty"
}

cmd_refresh_baseline() {
  local root="" write=0 pretty=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "refresh-baseline: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  local status active now head affected refreshed
  status="$(require_active_status "$root")"
  active="$(load_active_json "$root")"
  now="$(iso_now)"
  head="$(git_head "$root")"
  affected="$(affected_paths_json "$(resolve_run_dir "$root" "$(printf '%s\n' "$status" | jq -r '.run')")/STATE.md")"
  refreshed="$(printf '%s\n' "$active" | jq --arg now "$now" --arg head "$head" --argjson affected "$affected" '. + {
    updated_at: $now,
    last_checked_head: $head,
    affected_files_at_last_check: $affected
  }')"
  if [ "$write" -eq 1 ]; then
    write_active_json "$root" "$refreshed" || die "cannot refresh active baseline" 1
  fi
  json_print "$(status_json "$root")" "$pretty"
}

write_outcome() {
  local root="$1" run_dir="$2" outcome="$3" reason="$4" review_json="$5" verify_line="$6" now out file
  now="$(iso_now)"
  file="$run_dir/SESSION-OUTCOME.json"
  out="$(jq -n \
    --arg outcome "$outcome" \
    --arg reason "$reason" \
    --arg now "$now" \
    --argjson review "$review_json" \
    --arg verify "$verify_line" \
    '{
      schema_version: 1,
      outcome: $outcome,
      reason: (if $reason == "" then null else $reason end),
      completed_at: $now,
      learning_review: $review,
      learning_verify: (if $verify == "" then null else $verify end)
    }')"
  printf '%s\n' "$out" | jq . > "$file"
  printf '%s\n' "$out"
}

global_metrics_file() {
  local base="${KIMIFLOW_HOME:-}"
  if [ -z "$base" ]; then
    [ -n "${HOME:-}" ] || return 1
    base="$HOME/.kimiflow"
  fi
  [ -n "$base" ] && [ "$base" != "/" ] || return 1
  printf '%s/metrics/token-economics.jsonl\n' "$base"
}

snapshot_finish_state() {
  local root="$1" run_dir="$2" snapshot="$3" file metrics
  local project="$root/.kimiflow/project"
  mkdir -p "$snapshot/run" || return 1
  if [ -d "$project" ]; then
    cp -Rp "$project" "$snapshot/project"
    printf 'present\n' > "$snapshot/project.present"
  else
    printf 'absent\n' > "$snapshot/project.present"
  fi
  for file in LEARNING-REVIEW.md RUN-LIFECYCLE.json RUN-LIFECYCLE.md SESSION-OUTCOME.json; do
    if [ -f "$run_dir/$file" ]; then
      cp -p "$run_dir/$file" "$snapshot/run/$file"
      printf 'present\n' > "$snapshot/run/$file.present"
    else
      printf 'absent\n' > "$snapshot/run/$file.present"
    fi
  done
  metrics="$(global_metrics_file 2>/dev/null || true)"
  if [ -n "$metrics" ] && [ -f "$metrics" ]; then
    mkdir -p "$snapshot/global-metrics" || return 1
    cp -p "$metrics" "$snapshot/global-metrics/token-economics.jsonl"
    printf 'present\n' > "$snapshot/global-metrics.present"
  else
    printf 'absent\n' > "$snapshot/global-metrics.present"
  fi
}

restore_finish_state() {
  local root="$1" run_dir="$2" snapshot="$3" file metrics
  local project="$root/.kimiflow/project"
  if [ "$(cat "$snapshot/project.present" 2>/dev/null || printf absent)" = "present" ]; then
    rm -rf "$project"
    mkdir -p "$root/.kimiflow" || return 1
    cp -Rp "$snapshot/project" "$project"
  else
    rm -rf "$project"
  fi
  for file in LEARNING-REVIEW.md RUN-LIFECYCLE.json RUN-LIFECYCLE.md SESSION-OUTCOME.json; do
    if [ "$(cat "$snapshot/run/$file.present" 2>/dev/null || printf absent)" = "present" ]; then
      cp -p "$snapshot/run/$file" "$run_dir/$file"
    else
      rm -f "$run_dir/$file"
    fi
  done
  metrics="$(global_metrics_file 2>/dev/null || true)"
  if [ -n "$metrics" ]; then
    if [ "$(cat "$snapshot/global-metrics.present" 2>/dev/null || printf absent)" = "present" ]; then
      mkdir -p "$(dirname "$metrics")" || return 1
      cp -p "$snapshot/global-metrics/token-economics.jsonl" "$metrics"
    else
      rm -f "$metrics"
    fi
  fi
}

cmd_finish() {
  local root="" write=0 pretty=0 skip_learning=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --write) write=1 ;;
      --skip-learning) shift; skip_learning="${1:-}" ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "finish: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  root="$(resolve_root "$root")"
  local status run_rel run_dir counts stale_risk router review verify outcome active_rm snapshot verify_status
  status="$(require_active_status "$root")"
  run_rel="$(printf '%s\n' "$status" | jq -r '.run')"
  run_dir="$(resolve_run_dir "$root" "$run_rel")"
  counts="$(printf '%s\n' "$status" | jq -c '.item_counts')"
  stale_risk="$(printf '%s\n' "$status" | jq -r '.stale_risk')"
  [ "$(printf '%s\n' "$counts" | jq '.open')" -eq 0 ] || die "finish refused: unresolved active-session items remain" 1
  [ "$stale_risk" = "current" ] || die "finish refused: active session requires revalidation ($stale_risk)" 1
  router="${KIMIFLOW_MEMORY_ROUTER:-$SCRIPT_DIR/memory-router.sh}"
  [ -x "$router" ] || die "memory router missing or not executable: $router" 1
  if [ "$write" -eq 1 ]; then
    snapshot="$(mktemp -d "${TMPDIR:-/tmp}/kimiflow-finish.XXXXXX")" || die "cannot create finish snapshot" 1
    snapshot_finish_state "$root" "$run_dir" "$snapshot" || { rm -rf "$snapshot"; die "cannot snapshot finish state" 1; }
    if [ -n "$skip_learning" ]; then
      review="$("$router" review-run --root "$root" --run "$run_rel" --write --skip "$skip_learning")" || { rm -rf "$snapshot"; return 1; }
    else
      review="$("$router" review-run --root "$root" --run "$run_rel" --write)" || { rm -rf "$snapshot"; return 1; }
    fi
    verify="$("$router" verify-run --root "$root" --run "$run_rel" 2>&1)"
    verify_status=$?
    if [ "$verify_status" -ne 0 ]; then
      restore_finish_state "$root" "$run_dir" "$snapshot" || true
      rm -rf "$snapshot"
      printf '%s\n' "$verify" >&2
      return "$verify_status"
    fi
    rm -rf "$snapshot"
    outcome="$(write_outcome "$root" "$run_dir" "done" "" "$review" "$verify")"
    update_state_status "$run_dir" "done"
    update_state_phase7_done "$run_dir"
    active_rm="$(active_file "$root")"
    rm -f "$active_rm"
  else
    review='{"status":"preview","written":false}'
    verify=""
    outcome="$(jq -n '{schema_version: 1, outcome: "preview", learning_review: {status: "preview", written: false}}')"
  fi
  json_print "$(jq -n --arg run "$run_rel" --argjson written "$write" --argjson outcome "$outcome" '{
    status: (if $written == 1 then "finished" else "preview" end),
    written: ($written == 1),
    run: $run,
    outcome: $outcome
  }')" "$pretty"
}

cmd_terminal() {
  local command="$1"; shift
  local root="" reason="" write=0 pretty=0 outcome state_status
  case "$command" in
    park) outcome="parked"; state_status="backlog" ;;
    fail) outcome="failed"; state_status="failed" ;;
    abort) outcome="aborted"; state_status="aborted" ;;
    *) die "unknown terminal command: $command" 2 ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) shift; root="${1:-}" ;;
      --reason) shift; reason="${1:-}" ;;
      --write) write=1 ;;
      --pretty) pretty=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "$command: unknown argument: $1" 2 ;;
    esac
    shift
  done
  need_jq
  [ -n "$reason" ] || die "$command requires --reason" 2
  root="$(resolve_root "$root")"
  local status run_rel run_dir outcome_json active_rm
  status="$(require_active_status "$root")"
  run_rel="$(printf '%s\n' "$status" | jq -r '.run')"
  run_dir="$(resolve_run_dir "$root" "$run_rel")"
  outcome_json="$(jq -n --arg outcome "$outcome" --arg reason "$reason" --arg now "$(iso_now)" '{
    schema_version: 1,
    outcome: $outcome,
    reason: $reason,
    completed_at: $now,
    learning_review: {status: "not_promoted", reason: "session_not_finished"}
  }')"
  if [ "$write" -eq 1 ]; then
    printf '%s\n' "$outcome_json" | jq . > "$run_dir/SESSION-OUTCOME.json"
    update_state_status "$run_dir" "$state_status"
    active_rm="$(active_file "$root")"
    rm -f "$active_rm"
  fi
  json_print "$(jq -n --arg run "$run_rel" --argjson written "$write" --argjson outcome "$outcome_json" '{
    status: $outcome.outcome,
    written: ($written == 1),
    run: $run,
    outcome: $outcome
  }')" "$pretty"
}

hook_root_from_input() {
  local input="$1" cwd=""
  if command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$input" | jq -r '.cwd // .tool_input.cwd // .working_directory // empty' 2>/dev/null || true)"
  fi
  [ -n "$cwd" ] || cwd="$(pwd)"
  resolve_root "$cwd"
}

cmd_prompt_context() {
  need_jq
  local input root status present context stale run open
  input="$(cat 2>/dev/null || true)"
  root="$(hook_root_from_input "$input")"
  status="$(status_json "$root")"
  present="$(printf '%s\n' "$status" | jq -r '.present')"
  [ "$present" = "true" ] || exit 0
  printf '%s\n' "$status" | jq -e '.terminal == false' >/dev/null 2>&1 || exit 0
  run="$(printf '%s\n' "$status" | jq -r '.run')"
  stale="$(printf '%s\n' "$status" | jq -r '.stale_risk')"
  open="$(printf '%s\n' "$status" | jq -r '.item_counts.open')"
  context="Kimiflow active session is open: ${run}. Treat this user prompt as part of that Kimiflow run unless the user explicitly says to exit, abort, park, or switch workflows. Do not route follow-up fixes/features to another skill. Before editing, append or update run items with hooks/active-run.sh append-item/mark-built/mark-accepted/mark-rejected/drop-item. Open item count: ${open}. Finish only through hooks/active-run.sh finish --write, or park/fail/abort with a reason."
  case "$stale" in
    needs_revalidation|unknown)
      context="${context} Active-session freshness is ${stale}; revalidate the plan/code first, then run hooks/active-run.sh refresh-baseline --write before finishing."
      ;;
  esac
  jq -n --arg context "$context" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $context
    }
  }'
}

cmd_stop_gate() {
  need_jq
  local input active root status run open stale reason
  input="$(cat 2>/dev/null || true)"
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // .hook_input.stop_hook_active // false' 2>/dev/null || true)"
  [ "$active" = "true" ] && exit 0
  root="$(hook_root_from_input "$input")"
  status="$(status_json "$root")"
  printf '%s\n' "$status" | jq -e '.present == true and .terminal == false' >/dev/null 2>&1 || exit 0
  run="$(printf '%s\n' "$status" | jq -r '.run')"
  open="$(printf '%s\n' "$status" | jq -r '.item_counts.open')"
  stale="$(printf '%s\n' "$status" | jq -r '.stale_risk')"
  reason="kimiflow active-session gate: ${run} is still open. Open items: ${open}. Continue the Kimiflow loop, or close it mechanically with hooks/active-run.sh finish --write, park --write --reason <text>, fail --write --reason <text>, or abort --write --reason <text>."
  case "$stale" in
    needs_revalidation|unknown)
      reason="${reason} Active-session freshness is ${stale}, so revalidate and run hooks/active-run.sh refresh-baseline --write before finishing."
      ;;
  esac
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 2; }
shift || true

case "$cmd" in
  status) cmd_status "$@" ;;
  start) cmd_start "$@" ;;
  append-item) cmd_append_item "$@" ;;
  mark-built|mark-accepted|mark-rejected|drop-item) cmd_update_item "$cmd" "$@" ;;
  refresh-baseline) cmd_refresh_baseline "$@" ;;
  finish) cmd_finish "$@" ;;
  park|fail|abort) cmd_terminal "$cmd" "$@" ;;
  prompt-context) cmd_prompt_context "$@" ;;
  stop-gate) cmd_stop_gate "$@" ;;
  --help|-h|help) usage; exit 0 ;;
  *) die "unknown command: $cmd" 2 ;;
esac
