# Handoff — memory-router Bash→Python port (session 4, Plans 12–18)

**Date:** 2026-06-29 · **Repo:** kimiflow · **Branch:** `feat/memory-router-py-foundation`

Supersedes the session-3 handoff. Per-plan detail lives in the gitignored ledger `.superpowers/sdd/progress.md` (read it for exact nuances, grounding evidence, and commit SHAs). This handoff carries the verified state + roadmap forward.

---

## TL;DR

This session shipped **Plans 12–18** — all built, grounded byte-for-byte vs the real Bash (`kimiflow--v0.1.50`), independently reviewed (3 real bugs caught + fixed, incl. a **P1 token-leak**), tested green, committed (14 commits). 

- **12** `global_efficiency_summary_json` (+ `global_metrics.py`, `_jq_sum`)
- **13** `learning_lifecycle_json` + `learning_usefulness_json` (+ `clock.date_days_ago`)
- **14** provider status chain — `provider.py`: manifest/detection/loopback/auth/status (live curl→urllib probes)
- **15** `provider.sync_status_json` + `vault_status_json`
- **16** `status_json` + **`status` subcommand** (the keystone read)
- **17** **`curate` subcommand** + the MEMORY-INDEX.json writer (first file-parity harness)
- **18** **`record` subcommand**

**★ The core memory cycle is COMPLETE and byte-identical:** `status` (read) → `curate` (build index/recall) → `record` (append learning → bounded memory → re-curate). The entire summaries layer + provider/vault subsystem is done.

**Wired subcommands:** `classify`, `index`, `status`, `curate`, `record`. **Suite: 196 → 293 tests, all green** (incl. in-repo parity harnesses that shell to the pinned bash).

The Bash original is **untouched** (no cutover yet). Resume with **"weiter mit recall"** (or the next subcommand).

---

## Git state (end of session 4)

| Ref | Meaning |
|---|---|
| `feat/memory-router-py-foundation` | HEAD = Plan-18 feat `791135f`; ~14 commits ahead of session-3 end; **all additive, Bash untouched, nothing merged/pushed** |
| `kimiflow--v0.1.50` (tag) | the pinned Bash source-of-truth |

`git diff main HEAD -- hooks/memory-router.sh` is still empty. Working tree clean.

## Package state — `hooks/memory_router/`

Modules: `__init__`, `__main__`, `cli`, `contracts`, `store`, `paths`, `text`, `clock`, `classify`, `rows`, `writes`, `memory_md`, `recall_index`, `index`, `summaries`, **`global_metrics`** (12), **`provider`** (14–15), **`status`** (16), **`curate`** (17), **`record`** (18).

The summaries layer (`summaries.py`) is complete: read_jsonl/proposal/usage/economics/global_efficiency/learning_lifecycle/learning_usefulness. The evidence subsystem (`rows.py`: file_digest/evidence_*/sanitize_*/fingerprints) + `word_count_file` (`text.py`) were already ported in earlier sessions.

**Verify (re-run to confirm green):**
```bash
cd "<repo>" && export PATH="/opt/homebrew/bin:$PATH"
( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )   # 293 OK
git diff --stat main HEAD -- hooks/memory-router.sh                                  # empty
```

---

## What's NEXT — remaining subcommands, then cutover

Each is its own plan via the proven loop (deep-read pinned Bash → ground byte-for-byte → implement → independent senior-reviewer → test → commit docs+feat → ledger). Bash line ranges @ `kimiflow--v0.1.50`:

1. **`recall`** — `cmd_recall` (1826-~1990). The biggest remaining read. Deep-read map (already scouted this session):
   - **Done already (reuse):** `recall_index.fts_query_from_terms` + `fts_hits_json` (Plan 6), `text.word_count_file`, `fts5_available` (= Bash `sqlite_available`).
   - **NEW helpers to port:**
     - `terms_json_from_query` (1570-1589): **ASCII-lower** (Bash `tr '[:upper:]'`, NOT `str.lower()` — matters for the non-ASCII fallback) → split on `[^a-z0-9_-]+` → keep `len>=3`, drop stopwords `{the,and,for,mit,und,der,die,das,ein,eine,ist,sind,was,wie,this,that,from,into,zur,zum,auf,von}`, dedup (first occurrence) → first 30 → array; empty → `[ascii_lower(query)]`.
     - `jsonl_hits` (1591-~1771, **~180 lines of jq — the heavy part**): `field_text($row;$fields)` joins the named fields, `hit($text)` scores by term matches; returns top-`max` ranked rows. Needs careful deep-read + grounding.
     - `run_artifact_hits_json` (grep its def): run-artifact term matching (reuses `recall_index._iter_run_artifacts`).
     - `write_recall_markdown` (1772-1794): RECALL.md (`# Recall`, Generated/Query/Terms/Token budget, `## Sources` memory/user/learnings/facts/index/history, `## Explanation` reason_codes+total, `## Omitted`). `recall_json_path_for` (1796-1802): `*.md`→`*.json`. `write_recall_json` (1804-1808): `jq . > path` (pretty).
   - **`cmd_recall` flow:** args `--root/--query/--query-file/--max(default 5)/--write/--pretty`; `--query-file` → first 120 lines; validate query non-empty + `--max` all-digit; `budget=KIMIFLOW_MEMORY_BUDGET:-900`, `user_budget=KIMIFLOW_USER_MEMORY_BUDGET:-500`; memory/user content via `sed 1,160p`/`1,120p` with `included`/`omitted_over_budget`/`missing` + the `omitted[]` list; learning/fact hits via `jsonl_hits`; index hits via `fts_hits_json`; `index_status` ladder (used / available_no_hits / missing / unavailable); on `--write` write the `.md` + sibling `.json`. Stdout has `Generated`-style nondeterminism inside the file only — the JSON object stdout is timestamp-free EXCEPT the file write embeds `iso_now`; normalize as in record/curate.
2. **`history`** — RUN-HISTORY.json query/append.
3. **`metrics`** — incl. `--global`/`--global-purge`: the global-metrics record/purge infra (`ensure_global_metrics_salt`/`hash_text`/project_id) on top of the `global_metrics.py` location helpers from Plan 12.
4. **`review-run`** + **`verify-run`** — run-artifact review/verify.
5. **`consolidate`** + **`propose`** — proposal lifecycle (`quality_gate_json` @ 2339, `memory_security_json` done).
6. **`provider`** subcommand — `cmd_provider` (4160+): status/health/setup/detect/connect/configure/prefetch/sync actions; needs `provider_setup_plan_json` (890-994), the markdown writers (`write_provider_prefetch_markdown`/`write_provider_sync_markdown` 4115-4158), base/mcp-url helpers.
7. **Cutover** (final): replace the Bash body with the shim `exec env PYTHONPATH="$dir" python3 -m memory_router "$@"`, delete the Bash, full suite + smokes green, update README/COMPATIBILITY (Python ≥3.9)/CHANGELOG, `/release`. **This is the public step — present to the user for go/no-go.**

---

## The proven loop (unchanged; key reminders)

1. **Ground byte-for-byte** against the real Bash before committing — extract fns via awk (`index($0, fn"() {")==1`) or run the WHOLE pinned script; normalize via `jq -c .`; diff. This is the highest-leverage step — it caught every divergence this session.
2. **Isolated env for provider/network/record grounding:** the host has a **real `OBSIDIAN_API_KEY`** + `KIMIFLOW_OBSIDIAN_MCP_AVAILABLE=1`. Always run grounding under `env -i PATH=... HOME=/tmp KIMIFLOW_OBSIDIAN_URL='http://127.0.0.1:9/'` (dead port) + a **test token only**. Never log/commit the real key.
3. **Independent review** (senior-reviewer subagent) per block against the Bash source — it caught: Plan-13 cross-type `last_verified` crash (P2), Plan-14 **redirect token-leak (P1)**, Plan-14 non_loopback url-blank + multiline-url bugs. Fix → re-ground → amend the `docs: plan N` commit.
4. **Pure ASCII** every changed file (`[ (i+1,repr(l)) for i,l in enumerate(open(f)) if any(ord(c)>127 for c in l) ]`); middle-dot etc. as escapes.
5. Commit named paths only; **no AI/co-author trailer**; never `git add -A`. `docs: plan N` = the plan doc; `feat(memory_router): …` = spec §12 + code + tests.

### Carry-forward minors (address at cutover review)
- `_jq_or` now has 4 copies (recall_index, summaries, provider, curate) — the consolidation into a shared jq helper is overdue.
- `_max_present` (summaries) has the same cross-type-sort crash class as the Plan-13 `last_verified` (fixed there) — unreachable (date fields), deferred.
- `topics`/`read_jsonl_summary` `sorted()` on a non-string topic would crash where jq wouldn't — unreachable.

## spec §12 known divergences
`…-design.md` §12 now has ~15 rows. New this session: `_jq_sum` float rendering (replicated), non-object usage in learning summaries, provider curl-gate/TLS+no-follow/manifest/timeout, sync non-list evidence, status sqlite_available=fts5, curate atomic index write. All either replicated or unreachable-and-safer.

## Open decisions for the user
- **Merge `feat/memory-router-py-foundation` → `main`?** Now a large additive branch (Bash untouched). A whole-branch review before merge would be warranted; otherwise keep accumulating until cutover.
- **Push local `main`** (still 2 unpushed spec/Plan-0 commits) or leave local?
