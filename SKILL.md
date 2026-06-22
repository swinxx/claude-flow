---
name: kimiflow
description: Feature & bug-fix loop — clarify (plain language) → understand & research / diagnose (memory-first) → plan with testable acceptance criteria → plan-gate (independent reviewers, binary, cap 3) → implement → verify against specs → code-review → commit (stops first). Fix mode proves the problem, verifies the root cause, and researches the correct fix BEFORE fixing. Modes: full run · --prepare · --resume <slug> · --fix. Manual only via /kimiflow.
disable-model-invocation: true
argument-hint: <feature-or-bug> [--fix] [--prepare] [--quiet|--verbose] [--set-verbosity <level>] [--settings]  ·  --resume <slug>
---

# kimiflow — Feature & Fix Loop

Orchestrates the full loop for: **$ARGUMENTS**

You are the **orchestrator**. Run the phases below as a state machine, delegate heavy work to subagents (fresh, isolated context), and keep only the essentials in your own context. Detailed conventions live in **[reference.md](reference.md)** — read the relevant section exactly when a phase calls for it.

## Modes (invocation)

- **`/kimiflow <feature-or-bug>`** — full run (phases 0–7).
- **`/kimiflow … --prepare`** — **prepare only**: phases 0–4, then STOP. Package lives in `.kimiflow/<slug>/`; implement later, even in a new session.
- **`/kimiflow --resume <slug>`** — **continue**: read `.kimiflow/<slug>/STATE.md`, resume at the first open phase. No re-clarification — the spec files suffice. Without `<slug>` → list existing `.kimiflow/*/` with status and ask.
- **Feature or fix:** kimiflow detects from the request whether you are **building** or **fixing a bug** and routes accordingly. Force with **`/kimiflow --fix <bug>`**.
- **Display verbosity (visible output only — engine unchanged):** `--quiet` / `--verbose` set the level for a **single run** (never persisted); **`--set-verbosity <level>`** writes the **project** default (`.kimiflow/verbosity`) and exits; **`--settings`** opens a dialog to pick level **+** scope (project / global) and exits. Precedence: **`flag > project > global > balanced`** (project `.kimiflow/verbosity`, global `~/.claude/kimiflow/verbosity`). On a **first run** with no config and no flag, kimiflow asks **once** (interactive only) — headless or dismissed → `balanced`, no block. Levels change only how much you print; gates/artifacts/evidence/subagents are identical. Details: **reference.md → "Display verbosity"**.

## Core principles (apply in ALL phases)

- **Language: reply in the user's language.** Detect the language the user writes in and use it for everything they see and for the artifacts they review (INTENT/PROBLEM/PLAN/…). These English instructions do NOT dictate the conversation language.
- **Terse output (HARD RULE — governs every phase; this is where runs bloat).** This rule is the **`balanced`** baseline; the resolved **display-verbosity** level scales it — `quiet` prints even less, `verbose` adds narration but stays bounded by **(b)** — while the *engine* (gates, artifacts, evidence, subagents, thresholds) is **identical at every level** (reference.md → "Display verbosity"). Your visible output is **control-plane only**: a phase line, the gate verdict, the decisive evidence, and a question when you need an answer. Concretely:
  - **(a) One-line phase announcements** — marker + name + ≤1 clause. Never a paragraph.
  - **(b) NEVER paste a full artifact into chat** (INTENT/PROBLEM/RESEARCH/DIAGNOSIS/PLAN/ACCEPTANCE). Write it to its file; show a **≤3-line summary + the path**. The user opens the file for detail. (This is the #1 volume leak.)
  - **(c) Gate verdict = ONE line** — e.g. `gate open · open BLOCKER/HIGH: 0`. No narrative; the reasoning lives in `REVIEW.md`.
  - **(d) Evidence = the command + only the decisive output line(s)**, never a full log dump.
  - **(e) No STATE narration in chat, no recap tables, no restating what a subagent will do or just did.**
  - **Budget: ≤~6 lines of your own prose per phase**, outside the required artifact-summary / decisive-evidence. **Exempt:** the Phase-7 commit-gate `git diff --staged` and direct answers the user asked for. Gates, findings and evidence stay — the volume around them goes.
- **Phase colors — announce each phase with its marker.** As you enter a phase, prefix the announcement with its colored marker so the run reads at a glance: ⚪ 0 Setup · 🔵 1 Clarify · 🟣 2 Understand · ⚫ 3 Plan · 🟡 4 Plan-gate · 🟠 5 Implement · 🟤 6 Verify · 🟢 7 Review/Commit (the headers below carry the same marker). Keep that phase's marker on its STATE updates and status lines. (The main output is markdown — the emoji IS the color channel; there is no ANSI text color.)
- **Self-contained — the skill is the authority.** Every gate, threshold and acceptance standard lives here (+ reference.md), never in a personal/global `CLAUDE.md`. kimiflow runs identically regardless of how — or whether — a `CLAUDE.md` exists. The only `CLAUDE.md` kimiflow consults is the **project's** one, as an optional conventions hint in Phase 2 — never as a source of gate criteria, numeric scores, or audit thresholds. Don't borrow gate rules from any `CLAUDE.md` or attribute a kimiflow gate to one.
- **Simplicity-first.** Minimal code/plan for the problem. No speculative abstractions, no features beyond the request. Complexity scales with the project, not with imagination.
- **Anti-hallucination.** Only claims you can back. "Not verifiable" is valid. Severity never higher than provable by a code reference.
- **Evidence-before-assertion.** Never claim "done/green/root cause found" without showing the actual command + output / the `file:line`.
- **Agent budget.** You may fan out to **up to ~5–10 subagents automatically** when it measurably improves the result (best-of-N, a diverse-family reviewer, parallel independent tasks). **Beyond ~10 → stop and ask the user first** (cost + consent). Default stays lean (1 implementer, 1–2 reviewers); knobs spend *within* this budget. Record any fan-out in STATE.md.
- **Persist phase progress.** After finishing **every** phase, set its status in `.kimiflow/<slug>/STATE.md` to `done` (`Phase N: open|in-progress|done`). Resume reads this list.
- **Stop criteria always active:** success-stop (gate/verification met), failure-stop (escalate — see phase 5), budget-stop (cap reached → stop + ask). Never loop forever.
- **Subagents do NOT see your context.** Every delegation carries: objective, output format, allowed files/boundaries, the **paths** of the relevant state files — and the reference.md content the subagent needs — pass the **path** `${CLAUDE_SKILL_DIR}/reference.md` + the exact section names to read, **not the text verbatim** (verbatim only for a snippet under ~15 lines; this avoids re-sending the same rubric/template into every spawn). Subagents write results to the named paths.

## ⚪ Phase 0 — Setup, Routing & Scope-Gate

1. **Slug + state dir.** Derive a kebab-case `<slug>`. State lives under `.kimiflow/<slug>/` at the **git root** of the current project — creating `.kimiflow/` there also activates the `commit-secret-gate` hook for the repo (reference.md → "Commit hygiene").
2. **Mode routing — feature or fix.** Detect: build/add/change → feature; crashes/error/bug/"doesn't work"/wrong behavior → **fix**. `--fix` forces it. When in doubt, ask **one** simple question. Record in STATE. Fix mode branches only phases 1+2; from phase 3 on, `PROBLEM.md` ≙ `INTENT.md` and `DIAGNOSIS.md` ≙ `RESEARCH.md`.
3. **Resume check.** With `--resume <slug>`: read its `STATE.md`, resume at the first unfinished phase. Else if `.kimiflow/<slug>/STATE.md` exists → continue. Else create `STATE.md` (feature/problem, slug, date, mode, scope tier, one status line per phase `Phase 0..7`).
4. **Git check.** `git rev-parse --is-inside-work-tree`. No repo → report + ask: `git init`, or run through verification only (phases 5–6), no commit (7). Parallel build requires git.
5. **Scope-gate — hard rule (the default protects simplicity-first):**
   - **Default = `small`** — most runs stay here; `large` multiplies subagent/round (token) cost, so it's the exception, not a reflex. Bump to **`large`** only if ≥~5 files · new dependency or data migration · auth/security/money/privacy path · **subtle/hard-to-reproduce bug** · user asks for the full loop.
   - **`trivial`** = 1–2 files, no risk (fix: obvious cause, e.g. a typo).
   - When in doubt, the **smaller** tier. Effect: trivial → no loop, no grill (implement/fix, verify briefly, commit-gate). small → reduced loop (light clarification, 1 reviewer, sequential). large → full loop **+ kimiflow enables the hard test-gate** for the repo (the marker is written in phase 7 from the phase-6-verified test command; reference.md → "Hard test-gate").
6. **Display verbosity + first-run onboarding (resolve at the very start — it governs how much you print from here on).** Map any `--quiet`/`--verbose` to a level and resolve via `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR}/hooks/resolve-verbosity.sh get [--flag <level>]`. If **no** verbosity flag was given, the run is **interactive**, and `… resolve-verbosity.sh origin`==`default` (no project and no global config) → ask **once** for level + save-scope, then `… resolve-verbosity.sh set <project|global> <level>`; **headless or dismissed → `balanced`, no write, no block.** Utility invocations `--set-verbosity <level>` (→ `set project`) and `--settings` (dialog → `set <scope>`) write config, report the path, and **exit** — they do not run the loop. The level changes only output volume, never the engine. Details: **reference.md → "Display verbosity"**.

## 🔵 Phase 1 — Clarify (plain language): Intent (feature) or Problem (fix)

Goal: shared understanding BEFORE research/plan. kimiflow clarifies **itself** (embedded), always in **plain language** (everyday words, one question at a time with a recommended answer, WHAT/WHY not HOW, bounded ~5 questions or "ok"). Scope sets depth (trivial → skip, small → 2–3, large → full). Full rules: **reference.md → "Intent clarification"** / **"Fix mode"**.

- **Feature → intent clarification:** clarify goal, value, in/out of scope, "what done looks like" → write `INTENT.md` → **gate** "Does this match?" (OK to continue).
- **Fix → problem clarification:** symptom, expected vs. actual, when/how it occurs (steps, logs, since when, always/intermittent) → write `PROBLEM.md` → **gate** "Did I understand the problem correctly?" (OK to continue).

## 🟣 Phase 2 — Understand & research / diagnose (memory-first → vault → understanding ∥ web → synthesis → save)

Goal: kimiflow must **truly understand** the affected code before planning — evidence-based. Full checklists: **reference.md → "Understand & research"**, **"Fix mode"**, **"Project memory & standards"**.

0. **Project memory first** (cheap, all tiers — `CLAUDE.md` is native, the `.kimiflow` files only if present). Read the project's `CLAUDE.md` and, if present, `.kimiflow/STANDARDS.md` + `.kimiflow/DECISIONS.md` → ground truth for conventions/patterns/past decisions. The `Explore` agent then only fills gaps.
1. **Vault** (a notes MCP such as Obsidian, if connected): `obsidian_simple_search` on the key terms from `INTENT.md`/`PROBLEM.md`; read hits as context. Don't re-research what the vault holds. No MCP → note, continue.

**Feature → understand & research:**
2. **Codebase understanding** (read-only, **`Explore` agent**, input `INTENT.md` + project memory): patterns/conventions to match, integration points, data flow, affected modules, **existing tests**, risks/assumptions. **Back every claim with `file:line`**, mark unproven "NOT VERIFIED". Depth by scope.
3. **External research** (`general-purpose` + `WebSearch`/context7/`WebFetch`): only the gaps vault + codebase don't close. Parallel to step 2 when both are needed.
4. **Synthesis → `RESEARCH.md`** (structure in reference.md, incl. **open unknowns**). **Mini-gate:** a plan-blocking unknown → resolve first, don't plan on assumptions.

**Fix → understand & diagnose** (prove first, then fix):
2. **Reproduce** — actually trigger the bug, ideally a **failing test** (proof: real + where). Not reproducible = a finding → clarify with the user, don't fix blindly.
3. **Verify the root cause** (input `PROBLEM.md`) — find AND prove the cause (`file:line` + why that spot produces the symptom). **Not** the first guess.
4. **Fix research (proactive, BEFORE the fix)** — how is this *currently solved correctly*? Vault → web/context7 → official docs/issues. The model may be outdated → check the obvious guess against the current state; discard stale/naive approaches.
5. **Synthesis → `DIAGNOSIS.md`** (reference.md → "Fix mode"). **Diagnosis gate:** root cause **not** proven → **do NOT fix** (keep investigating or stop + ask).

**Always last — vault-save** (automatic — **only if a vault MCP is connected; else skip + note in STATE**) per **reference.md → "Vault conventions"**. Report the path. Don't save trivial lookups.

## ⚫ Phase 3 — Plan (testable acceptance criteria)

Delegate to a `general-purpose` planner (or the read-only `Plan` agent + you persist). **Inputs: `INTENT.md`+`RESEARCH.md`** (or `PROBLEM.md`+`DIAGNOSIS.md`) + project memory. Pass the planner the `${CLAUDE_SKILL_DIR}/reference.md` path + the section names to read (**acceptance-criteria template**, **code mandate**) — not verbatim.

- `PLAN.md`: minimal, aligned with the **existing architecture** (and project standards); task breakdown; mark each task **independent** (file-disjoint) or **dependent**; **anchored** in `RESEARCH.md`/`DIAGNOSIS.md` (named patterns / verified root cause); no assumption without evidence.
- `ACCEPTANCE.md`: each criterion per template (EARS + concrete input→output + named verification method) with an explicit **`AC-N → test_name` link**. Lint criteria for vague terms ("fast", "robust") and missing error/edge cases. Trace each to `INTENT.md`/`PROBLEM.md`. In fix mode the central criterion = **"the reproduction no longer fails" + no regression**.

## 🟡 Phase 4 — Plan-gate (loop, binary, cap 3)

Read **reference.md → "Review rubric"**.

0. **Coverage check (before round 1):** every `ACCEPTANCE.md` criterion maps to a plan task **and** a test; no orphan task lacks a criterion. Gaps → fix the plan first.
1. Spawn **2 independent reviewers in parallel** (scope=small → 1, lens B), **fresh context**, seeing only `PLAN.md` + `ACCEPTANCE.md` + `INTENT.md`/`PROBLEM.md` + named code (add `RESEARCH.md`/`DIAGNOSIS.md` only if the plan cites it). **Frame each adversarially** ("you did NOT write this; assume it is flawed; find the strongest objection" — counters same-family self-preference).
   - **A — goal/completeness & understanding:** achieves the goal / fixes the verified root cause? criteria measurable, complete, non-contradictory? plan anchored in correct understanding, no invented assumptions? (goal-backward)
   - **B — risk:** security, edge cases, error handling, architecture breakage, over-engineering. Fix mode: does it address the **cause**, not the symptom?
   - Each reviewer gives reasoning before verdict, then **writes this round's findings to `.kimiflow/<slug>/findings/r<N>-<lens>.md`** in the canonical one-line format (`FINDING <SEVERITY> <ref> :: <reason>`, sentinel `NONE` if clean — reference.md → "Review rubric"). No self-reported count; the orchestrator reads these files and never edits them.
2. Append a human-readable round summary to `REVIEW.md` (narrative only — reasoning, **not** the gate truth).
3. **Gate (binary, NO numeric score):** count open BLOCKER/HIGH **mechanically from this round's findings files** (`grep` over `.kimiflow/<slug>/findings/r<N>-*.md`; **fail-closed** on missing/empty/malformed — reference.md → "Review rubric"). 0 blocker/high → **gate open**. Else revise narrowly, round +1 — a finding is resolved only when the next round's reviewer no longer raises it (not asserted).
4. **Anti-oscillation (blocker-aware):** open BLOCKER/HIGH count doesn't strictly decrease across a round, or a disappeared finding reappears → **stop + ask, gate CLOSED** (reference.md → "Review rubric").
5. **Cap (3) reached without an open gate → stop + ask, gate CLOSED (never auto-proceed).**
6. **Gate open →** `--prepare`: STOP, update STATE (0–4 done), output `/kimiflow --resume <slug>`. Else → phase 5.

## 🟠 Phase 5 — Implement / fix

**Default: 1 implementation subagent, sequential.** Full tools, fresh context, inputs `PLAN.md` + `ACCEPTANCE.md` + `INTENT.md`/`PROBLEM.md` (+ `DIAGNOSIS.md`).

- **TDD where sensible:** failing test first (Red) → **commit tests before the implementation** → green → refactor. In fix mode the **reproduction** is the Red test. Address the **cause**, not the symptom.
- **Surgical:** every changed line traces to plan/intent/diagnosis. Leave foreign code alone, clean your own orphans.
- **Escalation keyed on the FIRST failure's signal** (failure-stop): a **clear** test/stack failure → one targeted execution-feedback fix; an **unclear / unexpected-API / likely-guess** failure → **escalate to research immediately** (`WebSearch`/context7) — don't burn a blind second attempt. After repeated failure → question the **approach/architecture**, not just the API. Then stop + ask.

## 🟤 Phase 6 — Verify against acceptance criteria (goal-backward)

Run each check, show real output, prove the goal — details: **reference.md → "Verification"**.

- **Run each criterion's method** and **show the command + the decisive result line(s)** — not full logs.
- **Goal-backward:** for each criterion's artifact check **Exists / Substantive / Wired** (imported AND used) — "task done ≠ goal achieved"; catch stubs/orphans that pass superficially.
- **Fix mode (mandatory):** the reproduction no longer fails.
- **Regression:** existing/affected test suite green.
- **Cold-start smoke test** — *only if* the diff touches `server.*`/`app.*`/`migrations/*`/`seed*`/`docker-compose*`: boot from scratch once.
- Non-automatable criteria → verifier subagent (fresh context, derives pass/fail from evidence; **does not trust** the implementer's self-report).
- Any failure → back to phase 5 (escalation rule applies).

## 🟢 Phase 7 — Code-review against specs → fix → commit-gate

1. **Review.** Spawn `code-review-audit` (or `senior-reviewer`) in **fresh context** (adversarial framing): sees the **diff** + `ACCEPTANCE.md` + `INTENT.md`/`PROBLEM.md`. Scope **correctness/requirements/security only — NOT style**. Also: "Were tests weakened/deleted to go green?". → `CODE-REVIEW.md`. **Run the bundled test-weakening scan — `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR}/hooks/test-weakening-scan.sh` (resolves in both plugin and skill installs) — over the staged diff and append its `FLAG` lines to `.kimiflow/<slug>/ADVISORIES.md`**; if the script can't be located or run, **note it in STATE and say so** — never silently skip the advisory channel (mechanizes the test-weakening check — a non-gating advisory channel; reference.md → "Review rubric").
2. **Fix.** Fix BLOCKER/HIGH, re-review until clean — **same findings-file + current-round grep + blocker-aware anti-oscillation as phase 4** (reviewers write `.kimiflow/<slug>/findings/r<N>-<lens>.md`; the gate counts them, fail-closed).
3. **Commit-gate — STOP.** Read **reference.md → "Commit hygiene"**. **Advisory triage (fail-closed):** present every `.kimiflow/<slug>/ADVISORIES.md` `FLAG`; the commit is blocked until each is explicitly **dismissed with a reason** (legit refactor) or **promoted** (→ a real `FINDING HIGH` → back to phase-7 review). Then show: short summary, `git status`, `git diff --staged`. **Wait for explicit OK.** Then commit (only named paths, no `git add -A`, no co-author/AI trailer, tests green). **(large)** if scope=`large` and `.kimiflow/test-gate` doesn't exist, write it with the test command verified green in phase 6 (idempotent, **kept local/untracked — never staged or committed**; suggest gitignoring `.kimiflow/`) and announce it. Set all phases done.
4. **Project memory (if enabled).** Append newly **verified** conventions to `.kimiflow/STANDARDS.md` and a 3–5 line entry to `.kimiflow/DECISIONS.md` (append-only, verified content only). Optional one-line run record in `.kimiflow/LEDGER.md` (slug, scope, rounds, gate result, knobs). Details: **reference.md → "Project memory & standards"**.

## Scaling knobs (OFF by default — enable within the agent budget; record in STATE.md)

> **Display verbosity is NOT a knob.** It is always-on and changes only visible output volume — never gates, cost, quality, or behavior. It must never be coupled to anything gate- or cost-related (reference.md → "Display verbosity").

- **Parallel implementation (incl. merge):** ≥2 genuinely independent, file-disjoint, small tasks → implementers with `isolation: worktree` (foreground), then sequential rebase/merge (test baseline after each, no octopus), then phase 6.
- **Best-of-N with tests:** a hard, **fully test-encoded** task → build 2–3 candidate implementations in parallel worktrees, keep the one passing the most acceptance + regression tests. Lift only exists *because* kimiflow has the test oracle. Counts against the agent budget.
- **Cross-family reviewer:** route **one** plan/code reviewer to a different model family (e.g. the `codex` CLI if available) → breaks same-family blind spots.
- **Multi-run gate:** for `large`/critical, take the reviewer's binary verdict **3× by majority** (variance reduction).
- **Deeper debugging:** for a stubborn bug, pull in `superpowers:systematic-debugging`.
- **Hard test-gate (opt-in, per project):** kimiflow ships a Stop hook (`hooks/`) that blocks finishing on red tests — see **reference.md → "Hard test-gate"** to enable.
- **Anti-reward-hacking hardening (critical code):** held-out/hidden tests, stricter diff inspection for test manipulation.
