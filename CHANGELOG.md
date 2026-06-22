# Changelog

Notable changes to **kimiflow**. Versions track `.claude-plugin/plugin.json`.

## 0.1.2

### Added
- **MIT license** — a `LICENSE` file + `license` field in the manifest, so the README's
  "anyone can install/fork" is actually covered (previously de-facto all-rights-reserved).
- **CI runs the unit tests** — `hooks/test-resolve-verbosity.sh` is now a hard gate in CI
  (was `bash -n` + JSON validation + advisory shellcheck only; the green tests were never run).
- **Artifact-economy rule** — on-disk artifacts (re-read by every subagent each round, the
  dominant token cost) are written information-dense; density never trades away rigor.

### Changed
- **First-run onboarding is now mechanical** — `resolve-verbosity.sh onboard-check` decides
  `ASK`/`SKIP` in the unit-tested script (`ASK` iff no project/global config and no flag), so it
  fires reliably on a fresh project and never nags a configured one. 0.1.1's prompt was
  orchestrator-judged and could be silently skipped.
- **Stale `flow` → `kimiflow`** in the hooks' headers and operator-visible deny/block messages.
- **SKILL.md / reference.md prose compacted** — decoration removed, telegraphic phrasing;
  every rule, threshold, path, and acceptance-criteria precision unchanged.

## 0.1.1

### Added
- **Display verbosity** — `quiet` / `balanced` / `verbose` levels that change **only** visible
  output; the engine (gates, artifacts, evidence, subagents, thresholds) is identical at every
  level. One-off `--quiet` / `--verbose`, setter `--set-verbosity`, a `--settings` dialog
  (level + scope), and a one-time first-run prompt (headless/skip → `balanced`, no block).
  Precedence `flag > project > global > balanced`, resolved by a unit-tested helper
  (`hooks/resolve-verbosity.sh`). Only verbosity may live globally (`~/.claude/kimiflow/verbosity`).

### Changed
- **State dir renamed `.flow/` → `.kimiflow/`** (self-documenting).
- **Fix-mode research** now names `WebSearch` / context7 / `WebFetch` explicitly (parity with the
  feature path).
- **Vault research is freshness-aware** — a hit is weighed by its `date:`; a fresh hit that
  answers the question replaces web research, and re-search uses a **different search vector**
  rather than repeating a prior query.

## 0.1.0 — Initial release

> Pre-1.0: early and evolving — interfaces and gate details may change between 0.x versions.

A user-invoked Claude Code skill: a disciplined feature & bug-fix loop with real,
mechanical quality gates.

### Added
- **8-phase loop** — scope-gate → clarify → understand/diagnose → plan → plan-gate →
  implement → verify → code-review/commit — with **colored phase markers**
  (⚪🔵🟣⚫🟡🟠🟤🟢) so a run reads at a glance in Claude Code.
- **Binary gates, no numeric score.** Reviewers write structured findings to per-round,
  orchestrator-immutable files; the gate counts open BLOCKER/HIGH **mechanically** and
  **fails closed** on missing/empty/malformed input — no self-reported counts, no re-count.
- **Fix mode** — reproduce, prove the root cause (`file:line`), and research the correct
  fix *before* fixing.
- **Self-contained** — every gate/threshold lives in the skill + `reference.md`, never in
  a personal/global `CLAUDE.md`.
- **Bundled hooks** (active only in kimiflow repos — a `.kimiflow/` dir at the git root):
  - `commit-secret-gate` (PreToolUse) — blocks staged secrets and bulk `git add -A`/`.`;
    **fails closed without `jq`**.
  - `test-gate` (opt-in Stop hook) — blocks finishing on red tests; runs **only a local,
    untracked marker** (a committed `.kimiflow/test-gate` is refused — no drive-by `eval`).
  - `test-weakening-scan` (advisory) — flags deleted tests / added skips / removed
    assertions to a non-gating channel, surfaced at the commit-gate.

### Requirements
- `jq` on `PATH` (used by the hooks).

### Notes
- Renamed from `claude-flow` to **kimiflow** to de-collide from `ruvnet/claude-flow`.
