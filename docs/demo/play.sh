#!/usr/bin/env bash
# kimiflow demo — SCRIPTED ILLUSTRATION, not a captured model run.
# Prints the README's 30-second demo block with phase pacing, so kimiflow-demo.tape
# can render a deterministic branded GIF. For a REAL recorded run, follow the
# asciinema steps in README.md instead.
set -euo pipefail

p() { printf '%s\n' "$1"; sleep "${2:-0.5}"; }

printf '$ /kimiflow --fix  token refresh throws after the access token expires\n'
sleep 0.9
p ''
p '⚪ Phase 0  scope-gate ····· large (touches auth; reproducible symptom)'
p '🔵 Phase 1  clarify ········ symptom? repro? expected? → PROBLEM.md  ✋ "Does this match?"'
p '🟣 Phase 2  diagnose ······· reproduces the throw, proves the cause at auth/refresh.ts:88'
p '            └─ no proven root cause ⇒ NO fix. (proven → continue)' 0.7
p '⚫ Phase 3  plan ··········· fix + EARS acceptance criteria → PLAN.md'
p '🟡 Phase 4  PLAN-GATE ······ 2 independent reviewers → resolve-review-gate.sh'
p '            └─ counts open BLOCKER/HIGH, fail-closed, cap 3 → 0 open ✅' 0.7
p '🟠 Phase 5  implement ······ failing test first (red) → fix → green'
p '🟤 Phase 6  verify ········· throw gone, suite green, checked against the criteria'
p '🟢 Phase 7  code-review ···· reviewers write findings → gate counts them (fail-closed)'
p '            └─ COMMIT-GATE: shows the diff, ✋ STOPS for your OK — never auto-commits' 1.2
