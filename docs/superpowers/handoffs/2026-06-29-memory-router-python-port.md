# Handoff — memory-router Bash→Python port (session 2, Plans 3–6)

**Date:** 2026-06-29 · **Repo:** kimiflow · **Branch:** `feat/memory-router-py-foundation`

Supersedes `2026-06-28-memory-router-python-port.md` (read that for the original strategy/decisions; this one carries forward the verified state and the loop refinements).

---

## TL;DR

- Continued the **`hooks/memory-router.sh` → stdlib-Python port**. This session shipped **Plans 3, 4, 5, 6** (row-validation, write-path, bounded-memory, RECALL.sqlite FTS5 engine) — all built, tested green, reviewed Approved, committed on the feature branch.
- **The #1 risk is retired:** macOS system `python3` (sqlite 3.51.0) has FTS5; the engine is ported and parity-grounded. No more big unknowns.
- The Bash original is **untouched** (no cutover yet). Multi-session effort continues.
- Resume by saying **"weiter mit Plan 7"**.

---

## Git state (verified 2026-06-29)

| Ref | Commit | Meaning |
|---|---|---|
| `origin/main` | `a9bf10d` | Release 0.1.50 (pushed) |
| local `main` | `6e41728` | 2 unpushed commits (design spec + Plan 0 doc) |
| `feat/memory-router-py-foundation` | `db3049c` | **26 commits ahead of local main**; all port code + plan docs |

**Nothing on the feature branch is merged or pushed. Working tree clean.** `git diff main HEAD -- hooks/memory-router.sh` is **empty** (Bash untouched).

This session added 8 commits (`8b696d6..db3049c`): a `docs: plan N` + a `feat(memory_router): …` pair for each of Plans 3/4/5/6.

---

## What's DONE (all green)

Package `hooks/memory_router/`: `__init__`, `__main__`, `cli`, `contracts`, `store`, `paths`, `text`, `clock`, `classify`, **`rows`**, **`writes`**, **`memory_md`**, **`recall_index`**.

| Plan | Module(s) | What |
|---|---|---|
| 0 | foundation | dispatch/usage, `contracts.dumps`, `store`, parity harness |
| 1 | `classify` | first subcommand, drop-in, 17 parity cases |
| 2 | `paths`/`text`/`clock` | primitives |
| **3** | `rows` | security gate (`memory_security_json`) + evidence sanitize/fingerprint |
| **4** | `writes` | `append_learning_row` (gate → dedup → supersession → append/rewrite) + `clock.date_compact` + `store.append_line` |
| **5** | `memory_md` | `write_bounded_memory`/`write_bounded_user_memory` (MEMORY.md/USER.md) + `store.read_json` |
| **6** | `recall_index` | RECALL.sqlite FTS5 engine: `fts5_available`, `init_recall_db`, `insert_fts_row`, `fts_query_from_terms`, `fts_hits_json` |

**Verification (re-run to confirm green):**
```bash
cd "<repo>" && export PATH="/opt/homebrew/bin:$PATH"   # jq for the contracts test
( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )   # 120 tests, OK
git diff --stat main HEAD -- hooks/memory-router.sh                                  # empty = Bash untouched
```
9 test files, **120 unit tests**. (Plans 3–6 are internal helpers/engine — unit-tested only; stdout/file parity arrives when subcommands wire them, Plan 8+.)

---

## What's NEXT — start with Plan 7

**Plan 7 — `build_recall_index`** (Bash 2547-2621): the multi-source population that fills the FTS engine. Opens one connection, calls `recall_index.init_recall_db`, then `insert_fts_row` for each source:
- `MEMORY.md` / `USER.md` → first 180 lines as body (Bash `sed -n '1,180p'`).
- current `LEARNINGS.jsonl` rows → title `"<topic> · <kind> · <id>"`, body summary, ref = evidence[0].
- current `USER.jsonl` rows → title `"<topic> · <id>"`.
- `FACTS.jsonl` rows → title `"<kind> · <area> · <path>"`, ref `"<path>:<line>"`.
- run-artifact `.md` files: `find "$root/.kimiflow" -path "$project" -prune -o -type f \( -name 'INTENT.md' -o 'PROBLEM.md' -o 'RESEARCH.md' -o 'DIAGNOSIS.md' -o 'PLAN.md' -o 'ACCEPTANCE.md' -o 'REVIEW.md' -o 'CODE-REVIEW.md' -o 'LEARNING-REVIEW.md' -o 'ADVISORIES.md' -o -path '*/findings/*.md' \) -print`; title via `awk -F/ '{print $2 " · " substr(...)}'`.
- `return 2` when FTS5 unavailable (`sqlite_available || return 2`).
- **Watch out:** titles use a ` · ` middle dot → **write it as a `·` escape**, never a literal char (see the loop gotcha below). Consumes `paths.rel_path` (done), `recall_index.*` (done), `store.read_jsonl` (done).

Then (handoff order, layer-first, smallest piece):
- **curate** composition (incl. the inline `MEMORY-INDEX.json` builder at Bash 4109 — it lives in `cmd_curate`, NOT a standalone fn).
- **record/index/curate subcommand wiring** (Plan 8) → first stdout/file parity for the write+index path; harness must normalize `id`/`date`/`source_commit`/`updated_at` and **whitelist the MEMORY.md/USER.md body-format divergence** (see §12 below).
- Remaining subcommands: `recall`, `history`, `metrics`, `status` (big aggregator over ~11 summary helpers — `read_jsonl_summary`, `usage_summary_json`, `economics_summary_json`, `global_efficiency_summary_json`, `learning_lifecycle_json`, `learning_usefulness_json`, `provider_status_json`, `provider_sync_status_json`, `vault_status_json`, `proposal_summary_json` — do near last), `review-run`, `verify-run`, `consolidate`, `propose`, `provider`.
- **Cutover** (final): replace the Bash body with the shim `exec env PYTHONPATH="$dir" python3 -m memory_router "$@"`, delete the Bash, full suite + smokes green, update README/COMPATIBILITY (Python ≥3.9)/CHANGELOG, `/release`.

**Progress: 7 of ~14 building blocks done. The hardest unknown (sqlite/FTS5) is now verified.** Roughly ~45% to cutover; the back half is the subcommand wiring + the `status` aggregator + cutover.

---

## The proven loop (refined this session)

Per building block, on branch `feat/memory-router-py-foundation`:

1. **Deep-read the Bash subsystem** from the pinned tag (`git show kimiflow--v0.1.50:hooks/memory-router.sh | sed -n 'A,Bp'`), cite exact line ranges. **Don't trust the handoff's groupings** — this session found two: the `MEMORY-INDEX.json` "builder" is inline in `cmd_curate` (not with bounded-memory), and `build_recall_index` is separable from the FTS engine. Verify scope against real code.
2. **PRE-VALIDATE in a scratch package copy** (the highest-leverage refinement): `cp -r hooks/memory_router <scratch>/`, write the module + tests there, run them green BEFORE writing the plan. Then the plan ships empirically-verified code. For parity-sensitive ports, also **ground against the real Bash**: extract the Bash fn into a tiny harness, run on a fixture, `diff` outputs (normalize timestamps). This session that grounding caught the MEMORY.md `jq -c` quoted-body quirk and confirmed `fts_query_from_terms`/`sqlite3 -json` parity byte-for-byte.
3. **Write the plan** with the verified code → `docs/superpowers/plans/2026-06-28-…-N-<name>.md`; verify the plan's code blocks match the scratch files byte-for-byte and that code fences are pure ASCII; commit as `docs: plan N …`.
4. **Subagent-driven execution** (skill `superpowers:subagent-driven-development`): task-brief → **haiku** implementer → `review-package` → **sonnet** task reviewer → fix loop. Helper scripts under the skill dir; pass explicit out-paths `.superpowers/sdd/pN-task-M-{brief,report}.md`.
5. After review-clean: append one line to the ledger `.superpowers/sdd/progress.md` (gitignored scratch). Commit named paths only; **no AI/co-author trailer**; never `git add -A`.

### Gotcha that bit repeatedly — non-ASCII transcription
The **haiku implementer converts `\uXXXX` escapes back to raw/literal chars and then falsely "confirms" them** (Plan 3: invisible U+200B zero-width space; Plan 5: raw U+00B7 middle dot). **The controller MUST byte-check every implementer commit** for stray non-ASCII (`[hex(ord(c)) for c in src if ord(c)>127]`) and normalize via script + `git commit --amend` BEFORE the review. Plan 6 was pure ASCII → clean. Plan 7 has ` · ` middle dots → expect to fix.

### Blessed bug-fixes go to the user
When the deep-read/grounding surfaces a latent Bash bug, **ask the user** (AskUserQuestion) whether to replicate faithfully or fix-with-divergence — don't decide silently. This session: the MEMORY.md/USER.md `jq -c` quoted-body quirk → user chose **fix now** → recorded as a §12 divergence + code comment + harness-whitelist note.

---

## §12 known divergences (6 rows; spec §12)
1. `contracts.dumps` numbers (jq `1.0→1`) — add float coverage before first numeric-stdout subcommand (metrics/economics).
2. `classify` jq-absent — Python needs no jq.
3. `memory_security_json` hidden_unicode + `file_digest_json` — Python stdlib always scans/hashes (no perl/shasum gate).
4. `\\.env` exfiltration quirk — **replicated faithfully** in `rows.py` (latent gate bug; fix is a separate blessed change).
5. **MEMORY.md/USER.md body** — port renders real markdown bullets; Bash `jq -c | join` emits a quoted one-liner with literal `\n`. **User-blessed fix.** Harness must whitelist this when bounded-memory is wired.
6. RECALL.sqlite engine — stdlib `sqlite3` module + FTS5 probe + parameter binding (vs `command -v sqlite3` + `sql_quote`).

### Carry-forward Minors (for the final/cutover review)
- Plan 4: `test_writes` uses `tempfile.mkdtemp()` without cleanup (plan-mandated; same class as Plan 0 `test_store`).
- Plan 5: `_int_env` accepts negative budget (defensive, matches Bash); no dedicated user-budget-shrink test.
- Plan 6: `init_recall_db` could carry a one-line "caller must confirm `fts5_available()` first" contract note for Plan 7.
- Latent symlink-on-append vuln in `writes.append_learning_row` append path (Bash `>>` follows symlinks too) — candidate future hardening, documented in Plan 4 notes.

---

## Open decisions for the user (when resuming)
- Merge `feat/memory-router-py-foundation` into `main` now (low risk: Bash untouched, no cutover; 26 commits) or keep accumulating until the port is further along? A merge would warrant a whole-branch (opus) review of Plans 0–6 first.
- Push local `main` (2 unpushed spec/Plan-0 doc commits) or leave it local?
