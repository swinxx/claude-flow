#!/usr/bin/env bash
# kimiflow demo — SCRIPTED ILLUSTRATION of a feature-build workflow, NOT a captured
# model run. Walks one feature (a dark-mode toggle) through the 8 phases to the
# commit-gate, mirroring examples/03-feature.md. Rendered to a GIF by
# kimiflow-demo.tape. For a REAL run, see the asciinema steps in README.md.
set -euo pipefail

D=$'\033[2m'      # dim — detail under a phase
B=$'\033[1m'      # bold — command + climax
G=$'\033[1;32m'   # green — a gate that passed
Z=$'\033[0m'

e(){ printf '%b\n' "$1"; sleep "${2:-0.5}"; }

e "${B}\$ /kimiflow  add a dark-mode toggle in settings${Z}" 1.0
e "" 0.2
e "⚪ scope ······ ${D}feature · large (settings + theme + persistence)${Z}" 0.7
e "🔵 clarify ···· ${D}3 Qs: live? persist? follow the OS first? → INTENT.md${Z}" 0.6
e "               ✋ ${D}\"Does this match?\" → yes${Z}" 0.6
e "🟣 research ··· ${D}vault: color tokens already CSS vars · web: data-theme + no-FOUC${Z}" 0.7
e "               ${D}considered: class-toggle · data-theme ✓ · context-rerender → RESEARCH.md${Z}" 0.7
e "⚫ plan ······· ${D}useTheme hook · apply · pre-hydration script · toggle UI → PLAN.md${Z}" 0.7
e "               ${D}AC-1 live · AC-2 persist · AC-3 OS-default · AC-4 no-flash${Z}" 0.6
e "🟡 plan-gate ·· ${D}2 independent reviewers → resolve-review-gate.sh →${Z} ${G}0 BLOCKER/HIGH ✅${Z}" 0.8
e "               ${D}(1 MEDIUM noted — doesn't gate; folded into the plan)${Z}" 0.6
e "               ✋ ${D}pre-build summary: \"approve to build?\" → approved${Z}" 0.7
e "🟠 implement ·· ${D}red tests first → hook + inline script + switch → green${Z}" 0.7
e "🟤 verify ····· ${D}AC-1..4 pass · no flash on reload · regression green · cold-start ok${Z}" 0.7
e "🟢 code-review  ${D}clean · test-weakening scan: no flags${Z}" 0.6
e "               ${B}✋ commit-gate — shows the diff, STOPS for your OK${Z}" 0.9
e "               ${D}feat(settings): live light/dark toggle — persisted, no FOUC${Z}" 0.7
e "" 0.3
e "${B}a feature, built gate by gate — you approve the plan, you approve the commit.${Z}" 1.2
