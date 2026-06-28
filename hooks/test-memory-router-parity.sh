#!/usr/bin/env bash
# kimiflow — memory-router parity harness: runs each case through the pinned old Bash
# and the new Python package, normalizes nondeterminism, and diffs stdout+stderr+exit.
# Known-bug divergences are listed in WHITELIST (see spec §12).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="kimiflow--v0.1.50"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OLD="$WORK/old-mr.sh"
if ! git -C "$ROOT" show "$TAG:hooks/memory-router.sh" > "$OLD" 2>/dev/null; then
  echo "cannot fetch $TAG:hooks/memory-router.sh — is the tag present?" >&2
  exit 1
fi
chmod +x "$OLD"

FAILS=0
ok()  { printf 'ok   %s\n' "$1"; }
wl()  { printf 'wl   %s (whitelisted divergence)\n' "$1"; }
bad() { printf 'BAD  %s\n' "$1"; FAILS=$((FAILS + 1)); }

# Whitelisted divergences: labels of cases whose divergence is an accepted known-bug.
# Empty for now — populate as real known-bug divergences are identified (see spec §12).
WHITELIST=()

# Cases the foundation covers: dispatch layer only (no --root state needed).
# Format: "label::arg1|arg2|..."  ('|' separates argv tokens; empty = no args)
CASES=(
  "no_args::"
  "help_long::--help"
  "help_short::-h"
  "help_word::help"
  "unknown_cmd::bogus"
)

normalize() { sed -e "s#$WORK#WORK#g" -e "s#$ROOT#ROOT#g"; }

in_whitelist() {
  local label="$1"
  local item
  for item in ${WHITELIST[@]+"${WHITELIST[@]}"}; do
    [ "$item" = "$label" ] && return 0
  done
  return 1
}

for entry in "${CASES[@]}"; do
  label="${entry%%::*}"; argstr="${entry#*::}"
  args=(); [ -n "$argstr" ] && IFS='|' read -r -a args <<< "$argstr"

  # Capture stdout and stderr to files (preserves trailing newlines)
  bash "$OLD" ${args[@]+"${args[@]}"} > "$WORK/o.out" 2> "$WORK/o.err"; o_code=$?
  python3 "$ROOT/hooks/memory_router" ${args[@]+"${args[@]}"} > "$WORK/n.out" 2> "$WORK/n.err"; n_code=$?

  # Normalize all four streams (path replacement) into separate .norm files
  normalize < "$WORK/o.out" > "$WORK/o.out.norm"
  normalize < "$WORK/o.err" > "$WORK/o.err.norm"
  normalize < "$WORK/n.out" > "$WORK/n.out.norm"
  normalize < "$WORK/n.err" > "$WORK/n.err.norm"

  # Detect divergences (file-based cmp preserves trailing newlines)
  diverged=""
  [ "$o_code" != "$n_code" ] && diverged="${diverged}exit($o_code!=$n_code) "
  cmp -s "$WORK/o.out.norm" "$WORK/n.out.norm" || diverged="${diverged}stdout "
  cmp -s "$WORK/o.err.norm" "$WORK/n.err.norm" || diverged="${diverged}stderr "

  if [ -z "$diverged" ]; then
    ok "$label"
  elif in_whitelist "$label"; then
    wl "$label"
  else
    bad "$label — diverged: $diverged"
    if [ "$o_code" != "$n_code" ]; then
      printf '  exit codes: old=%s new=%s\n' "$o_code" "$n_code"
    fi
    if ! cmp -s "$WORK/o.out.norm" "$WORK/n.out.norm"; then
      printf '  [stdout diff]\n'
      diff -u "$WORK/o.out.norm" "$WORK/n.out.norm" | sed 's/^/  /' || true
    fi
    if ! cmp -s "$WORK/o.err.norm" "$WORK/n.err.norm"; then
      printf '  [stderr diff]\n'
      diff -u "$WORK/o.err.norm" "$WORK/n.err.norm" | sed 's/^/  /' || true
    fi
  fi
done

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS DIVERGENCES"; exit 1; fi
