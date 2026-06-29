# memory-router Python CLI - Plan 18: `record` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_record` (Bash 3508-3543) - the learning-write entrypoint. It appends a learning row, refreshes the bounded MEMORY.md/USER.md, re-curates (MEMORY-INDEX.json + RECALL.sqlite), and prints `RECORDED\t<path>\t<id>`. This completes the core write path; every helper it calls is already ported and grounded.

**Architecture:** New module `hooks/memory_router/record.py` with `run(argv)`. Composes `writes.append_learning_row` (+ its `SecurityGateError`), `memory_md.write_bounded_memory`/`write_bounded_user_memory`, `curate.run`, `paths.rel_path`/`rows_path_for_scope`. Registered in `__main__.COMMANDS`. No new file writers of its own.

**Tech Stack:** Python 3.9+ stdlib only (`io`, `contextlib`, `sys`); no new deps.

## Global Constraints

- **Drop-in / scope:** new `record.py`, `__main__.py` dispatch entry, new `tests/test_record.py`. No edits to `hooks/memory-router.sh`, other modules, manifests. **No new §12 row** (record introduces no new divergence; it inherits the write_bounded_memory body-format §12).
- **Source of truth:** Bash `cmd_record` (3508-3543) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (whole real Bash script vs Python CLI, isolated `env -i`, dead detection port) - see Self-Review.
- **Arg parsing:** `--root`/`--summary`/`--topic`/`--kind`(default `learning`)/`--scope`(default `project`)/`--confidence`(default `medium`)/`--sensitivity`(default `normal`)/`--status`(default `current`)/`--evidence`(repeatable, accumulates)/`--help`/`-h`/unknown->`die(...,2)`. A value flag consumes the next token; a trailing flag with no value -> `""`.
- **Validation order** (after parsing, before `resolve_root`): non-empty summary else `die "record requires --summary" 2`; non-empty topic else `die "record requires --topic" 2`; >=1 evidence else `die "record requires at least one --evidence" 2`.
- **Append + gate:** `append_learning_row(root, kind, scope, topic, summary, evidence, confidence, sensitivity, status)`; on `SecurityGateError` write `memory-router: memory security gate closed: <reasons joined by ",">` to stderr and return 1 (Bash's append_learning_row prints this itself, then `|| return 1`); no RECORDED on block.
- **Bounded memory:** scope in `{user,profile}` -> `write_bounded_user_memory(root)` else `write_bounded_memory(root)`.
- **Re-curate:** `curate.run(["--root", root, "--write"])` with ONLY stdout suppressed (Bash `>/dev/null`, not `2>&1`).
- **Output:** `RECORDED\t<rel_path of rows_path_for_scope(root, scope)>\t<id>\n` (project -> LEARNINGS.jsonl, user/profile -> USER.jsonl).
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/record.py` | NEW: `run`. |
| `hooks/memory_router/__main__.py` | register `"record": record.run`. |
| `hooks/memory_router/tests/test_record.py` | NEW: `RecordRunCase` + `RecordParityCase` (LEARNINGS row + RECORDED parity). |

---

### Task 1: record

**Step 1 (Red -> Green):** Implement `record.py` + tests + dispatch exactly as shipped.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (293 with this plan).
- Grounding: run `bash <pinned> record ...` vs `python3 -m memory_router record ...` (isolated `env -i`, dead detection URL) on separate roots; verify the appended LEARNINGS.jsonl row + the RECORDED line are byte-identical modulo the random id; verify MEMORY.md/USER.md/MEMORY-INDEX.json/RECALL.sqlite are produced and that MEMORY.md/USER.md differ ONLY by the documented body-format §12 (strip the jq -c quote-wrap + timestamps -> match); check the security-gate block path and all arg-validation errors.
- ASCII check on `record.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (isolated `env -i`, dead detection port): the appended **LEARNINGS.jsonl row** AND the **RECORDED line** are byte-identical modulo the random id suffix, for project scope (2 evidence), user scope, and a kind/confidence/sensitivity variant; all 4 error paths (missing summary/topic/evidence, unknown arg) match exactly (message + exit 2); MEMORY.md/USER.md are written by the right bounded-writer per scope and match after stripping the documented user-blessed body-format §12 quote-wrap + normalizing timestamps; MEMORY-INDEX.json + RECALL.sqlite are rebuilt via `curate --write`. The `always_on_memory_tokens_estimate` word-count drift is the documented downstream of that §12, not a record defect. The security-gate block path returns 1 with the exact stderr line and no RECORDED. In-repo `RecordParityCase` exercises the LEARNINGS row + RECORDED parity against the pinned bash.
