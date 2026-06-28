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
bad() { printf 'BAD  %s\n' "$1"; FAILS=$((FAILS + 1)); }

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

for entry in "${CASES[@]}"; do
  label="${entry%%::*}"; argstr="${entry#*::}"
  args=(); [ -n "$argstr" ] && IFS='|' read -r -a args <<< "$argstr"

  o_out="$(bash "$OLD" ${args[@]+"${args[@]}"} 2>"$WORK/o.err")"; o_code=$?
  o_err="$(normalize < "$WORK/o.err")"
  n_out="$(python3 "$ROOT/hooks/memory_router" ${args[@]+"${args[@]}"} 2>"$WORK/n.err")"; n_code=$?
  n_err="$(normalize < "$WORK/n.err")"

  if [ "$o_code" = "$n_code" ] && [ "$o_out" = "$n_out" ] && [ "$o_err" = "$n_err" ]; then
    ok "$label"
  else
    bad "$label (exit $o_code/$n_code)"
  fi
done

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS DIVERGENCES"; exit 1; fi
