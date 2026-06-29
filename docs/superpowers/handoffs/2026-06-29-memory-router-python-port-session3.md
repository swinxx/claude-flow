# Handoff — memory-router Bash→Python port (session 3, Plans 7–11)

**Date:** 2026-06-29 · **Repo:** kimiflow · **Branch:** `feat/memory-router-py-foundation`

Supersedes `2026-06-29-memory-router-python-port.md` (session 2, Plans 3–6). Read the session-1/2 handoffs for the original strategy/decisions; this one carries the verified state forward and the loop refinements from this session.

---

## TL;DR

- Continued the **`hooks/memory-router.sh` → stdlib-Python port**. This session shipped **Plans 7, 8, 9, 10, 11** — all built, grounded byte-for-byte vs the real Bash, independently reviewed, tested green, committed on the feature branch.
  - **7** `build_recall_index` (multi-source RECALL.sqlite population)
  - **8** `index` subcommand wiring + the **first committed stdout-parity harness**
  - **9** `read_jsonl_summary` + `proposal_summary_json` (new `summaries.py`)
  - **10** `usage_summary_json`
  - **11** `economics_summary_json`
- **First stateful subcommand is wired** (`index`), and the shared wiring scaffolding (`resolve_root`, `json_print`) + parity-harness pattern now exist for every later subcommand.
- The Bash original is **untouched** (no cutover yet). Multi-session effort continues.
- Resume by saying **"weiter mit global_efficiency_summary_json"** (or "weiter mit <next block>").

---

## Git state (verified 2026-06-29, end of session 3)

| Ref | Commit | Meaning |
|---|---|---|
| `origin/main` | `a9bf10d` | Release 0.1.50 (pushed) |
| local `main` | `6e41728` | **2 unpushed** commits (design spec + Plan 0 doc) |
| `feat/memory-router-py-foundation` | `20bec95` | **37 commits ahead of local main**; all port code + plan docs |
| tag `kimiflow--v0.1.50` | `985bcbc` | the pinned Bash source-of-truth |

**Nothing on the feature branch is merged or pushed. Working tree clean.** `git diff main HEAD -- hooks/memory-router.sh` is **empty** (Bash untouched).

This session added 10 commits (`9a11a04..20bec95`): a `docs: plan N` + a `feat(memory_router): …` pair for each of Plans 7/8/9/10/11.

---

## What's DONE (all green)

Package `hooks/memory_router/`: `__init__`, `__main__`, `cli`, `contracts`, `store`, `paths`, `text`, `clock`, `classify`, `rows`, `writes`, `memory_md`, `recall_index`, **`index`**, **`summaries`**.

| Plan | Module(s) | What |
|---|---|---|
| 0–6 | foundation/classify/primitives/rows/writes/memory_md/recall_index | (prior sessions) |
| **7** | `recall_index` | `build_recall_index` + `_read_body`/`_first_lines`/`_jq_or`/`_evidence_ref`/`_artifact_title`/`_iter_run_artifacts` |
| **8** | `index`, `cli`, `contracts`, `__main__` | `index` subcommand; shared `resolve_root` (cli) + `json_print` (contracts); dispatch reg; **first stdout-parity harness** (`tests/test_index.py::IndexParityCase`) |
| **9** | `summaries` (new) | `read_jsonl_summary`, `proposal_summary_json` |
| **10** | `summaries` | `usage_summary_json` |
| **11** | `summaries` | `economics_summary_json` |

**Wired subcommands so far:** `classify` (Plan 1), `index` (Plan 8). All other modules are internal helpers (unit-tested; stdout/file parity arrives when their subcommands wire them).

**Verification (re-run to confirm green):**
```bash
cd "<repo>" && export PATH="/opt/homebrew/bin:$PATH"   # jq for contracts test; bash/sqlite3/git for the index parity harness
( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )   # 196 tests, OK (0 skipped in-repo)
git diff --stat main HEAD -- hooks/memory-router.sh                                  # empty = Bash untouched
```
**196 unit tests.** The 5 `IndexParityCase` tests **run** in-repo (shell out to the pinned Bash via `git show`) and **skip** when bash/jq/sqlite3/git or the tag are absent.

---

## What's NEXT — dependency-correct order

The handoff's old "record/index/curate (Plan 8)" grouping was **wrong** — the deep-read proved `cmd_curate` needs the full `status_json` aggregator and `cmd_record` calls `cmd_curate`, so both are blocked behind `status_json`. Real order (Bash line ranges @ `kimiflow--v0.1.50`):

1. **`global_efficiency_summary_json`** (483-597, ~115L) — last big economics pipeline (cross-run/global). *Start here.*
2. **`learning_lifecycle_json`** (599-651) + **`learning_usefulness_json`** (653-712) — LEARNINGS + usage derived summaries (one plan or two).
3. **provider/vault subsystem** — `provider_status_json` (1197-1292), `provider_sync_status_json` (1325-1351), `vault_status_json` (1353-1397). Reads `VAULT-PROVIDER.json`, git remotes; more I/O-shaped than the pure aggregators.
4. **`status_json`** (1399-1568, ~170L) — composes ALL the summaries above; then wire **`cmd_status`** (1810) → second big subcommand + status parity test.
5. **`curate`** — `cmd_curate` (4030) needs `status_json` (`.provider`/`.vault`/`.curation`) + `read_jsonl_summary`/`usage`/`economics`/`lifecycle` + a topics builder + the **inline `MEMORY-INDEX.json` writer at Bash ~4109** (lives in `cmd_curate`, NOT a standalone fn) + calls `cmd_index --write`.
6. **`record`** — `cmd_record` (3508) = `append_learning_row` (done) + `write_bounded_memory`/`write_bounded_user_memory` (done) + `cmd_curate --write` + `RECORDED\t<path>\t<id>` stdout.
7. Remaining subcommands: `recall`, `history`, `metrics`, `review-run`, `verify-run`, `consolidate`, `propose`, `provider`.
8. **Cutover** (final): replace the Bash body with the shim `exec env PYTHONPATH="$dir" python3 -m memory_router "$@"`, delete the Bash, full suite + smokes green, update README/COMPATIBILITY (Python ≥3.9)/CHANGELOG, `/release`.

**Progress: ~12 of ~14 building blocks done.** The back half is the remaining summaries + `status_json` + the `curate`/`record` wiring + cutover.

---

## The proven loop (refined this session)

Per building block, on branch `feat/memory-router-py-foundation`:

1. **Deep-read the Bash subsystem** from the pinned tag (`git show kimiflow--v0.1.50:hooks/memory-router.sh | sed -n 'A,Bp'`), cite exact line ranges. **Don't trust groupings — verify scope + dependencies against real code** (this session: curate/record blocked behind `status_json`; pick the smallest *unblocked* coherent piece).
2. **PRE-VALIDATE in a scratch package copy AND ground against the real Bash** (highest-leverage step). `cp -r hooks/memory_router <scratch>/`, write the module + tests there, run green. Then extract the Bash fn into a tiny harness (`git show …:memory-router.sh | sed -n 'A,Bp' > h.sh`), run on fixtures, and diff:
   - **Subcommands (stdout):** run the *whole* `bash memory-router.sh <cmd>` and diff stdout byte-for-byte (Plan 8: `index` stdout is timestamp-free).
   - **Internal helpers (return dicts):** normalize the Bash output through `jq -c .` (preserves key order) and diff against the Python `contracts.dumps(result)` — semantic + key-order parity, since these return Python objects serialized later at the subcommand boundary. (Plans 9/10/11.)
   This catches real divergences before any commit (Plan 7 caught 3: `status:null` keep, `7.0` literal, CRLF; Plan 10/11 confirmed jq `//`, `tonumber? // 0`, `floor`, env-parse).
3. **Write the plan** with the verified code → `docs/superpowers/plans/2026-06-28-memory-router-python-cli-N-<name>.md`; verify the plan's code blocks match the scratch/repo files **byte-for-byte** and that **code fences are pure ASCII**; commit as `docs: plan N …`.
4. **Implement + INDEPENDENT REVIEW.** This session the controller (opus) implemented directly from the grounded scratch (the code was already empirically verified), then dispatched a **`senior-reviewer` subagent** against the real diff + the Bash source (prompt: terse, real-issues-only, anti-hallucination, verify parity points, may run tests + ground vs jq). Fix any findings, re-ground, and **amend the `docs: plan N` commit** so the plan matches shipped code. (Subagent-driven *implementation* per `superpowers:subagent-driven-development` is still valid; controller-implements + independent-review was the efficient choice given the grounding.)
5. After review-clean: byte-check the changed source is **pure ASCII**, run the full suite, append one block to the ledger `.superpowers/sdd/progress.md` (gitignored scratch). Commit named paths only (`git add <paths>`); **no AI/co-author trailer**; never `git add -A`. Then commit `feat(memory_router): …`.

### Gotcha — non-ASCII transcription
Source must be **pure ASCII**. The U+00B7 middle dot is written as the escape `_MIDDOT = "·"` (and `DOT = "·"` in tests) — never the literal char. Byte-check every changed file: `[ (i+1, repr(l)) for i,l in enumerate(open(f)) if any(ord(c)>127 for c in l) ]`. Pre-existing intentional non-ASCII: the verbatim Bash em-dash in `cli.USAGE` and the `ü/ä/ö` UTF-8 fixture in `test_contracts.py`.

### Blessed bug-fixes / divergences go to the user
When the deep-read/grounding surfaces a latent Bash bug or an unavoidable divergence, decide: replicate faithfully vs fix-with-divergence. Record every divergence as a **spec §12 row**. Cheaply-avoidable divergences are **fixed** (Plan 7 CRLF, Plan 8 logical-cwd), not documented.

---

## spec §12 known divergences (now ~10 rows; `…-design.md` §12)
Session-3 additions: (7) `build_recall_index` run-artifact **sort order** vs `find` filesystem order + malformed-JSONL skip; jq `//`, jq-1.7 number-literal preservation, and CRLF/bare-CR are **replicated** (not divergences). (8) `resolve_root` uses `abspath`/logical-`$PWD` (symlink-preserving, matches bash logical paths) + `need_jq` no-op for all ported subcommands. (10) `usage_summary_json` non-object-JSON → absent shape (Bash jq-errors; unreachable). (11) `economics_summary_json` `_n` sci-notation/underscore **string** fields render differently (unreachable; fields are JSON numbers).

### Carry-forward Minors (for the final/cutover review)
- `_jq_or` is duplicated (2-line) in `recall_index` and `summaries`; consolidate into a shared jq-helper module once a 3rd consumer lands.
- Several `tempfile.mkdtemp()` in tests use `addCleanup(shutil.rmtree)` (good); the older `test_writes`/`test_store` mkdtemp-without-cleanup remains (plan-mandated, harmless).
- The first **file-parity** (not just stdout) harness arrives with `curate`/`record` (MEMORY.md/USER.md body-format whitelist + `id`/`date`/`source_commit`/`updated_at`/`recall_meta.updated_at` normalization).

---

## Open decisions for the user (when resuming)
- **Merge `feat/memory-router-py-foundation` → `main`?** It's now **37 commits** with no merge checkpoint. Everything is additive (Bash untouched, no cutover), so risk is low, but a merge would warrant a **whole-branch (opus) review of Plans 0–11** first. Otherwise keep accumulating until the port is further along (e.g. after `status_json`/`curate`/`record`, or at cutover).
- **Push local `main`** (2 unpushed spec/Plan-0 doc commits) or leave it local?
