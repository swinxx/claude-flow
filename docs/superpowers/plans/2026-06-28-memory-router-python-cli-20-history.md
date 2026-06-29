# memory-router Python CLI - Plan 20: `history` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_history` (Bash 2021-2085) - the run-artifact recall read. With a query it returns ranked run-artifact hits; without one it returns the most-recent run artifacts (`query="recent"`). On `--write` it emits `RUN-HISTORY.json` + `RUN-HISTORY.md` and updates `MEMORY-USAGE.json` (event kind `history`). **Almost every dependency was ported in Plan 19** - only the `write_history_markdown` writer is new.

**Architecture:** New module `hooks/memory_router/history.py` with `run(argv)`, `history_json(root, query, max_hits, write)`, and `write_history_markdown(path, obj)`. Reuses `recall.terms_json_from_query` + `recall._sed_read` (the shared query layer), `recall_index.run_artifact_hits_json` / `run_artifact_rows_json`, `usage_metrics.update_usage_metrics`, `store`/`contracts`/`clock`/`cli`. Registered in `__main__.COMMANDS`.

**Tech Stack:** Python 3.9+ stdlib only (`os`). No new deps.

## Global Constraints

- **Drop-in / scope:** new `history.py`, `tests/test_history.py`; `__main__.py` += `"history": history.run`. No edits to `hooks/memory-router.sh`, other modules, or manifests. **No new §12 row** (history composes already-documented helpers; its writers reuse the recall `--write` atomic-write §12 rationale).
- **Source of truth:** Bash `cmd_history` (2021-2085) + `write_history_markdown` (1687-1703) @ `kimiflow--v0.1.50`. Ground byte-for-byte (whole real Bash vs Python CLI, isolated `env -i`, dead detection port).

### Arg parsing (`run`)
`--root`/`--query`/`--query-file`/`--max`(default `10`)/`--write`(**boolean flag, NO value** - unlike recall)/`--pretty`/`--help`/`-h`/unknown->`die("history: unknown argument: <a>", 2)`. Value flags consume the next token; trailing -> `""`. Then `need_jq` no-op; `root = resolve_root(root)`. If `--query-file`: must exist else `die("query file not found: <f>", 2)`; `query = recall._sed_read(query_file, 120)` (first 120 lines). `--max` must be **non-empty AND all ASCII digits** else `die("history --max must be a number", 2)` (`''|*[!0-9]*`). **No "requires query" gate** - history works with no query.

### `history_json(root, query, max_hits, write)` -> dict (EXACT key order)
- If `query` non-empty: `terms = recall.terms_json_from_query(query)`; `hits = recall_index.run_artifact_hits_json(root, terms, max_hits)`.
- Else: `query = "recent"`; `terms = []`; `hits = [del-text(row) for row in recall_index.run_artifact_rows_json(root)[:max_hits]]` (Bash `run_artifact_rows_json | .[:max] | map(del(.text))`; output rows keep kind,slug,artifact,path,ref,title,summary).
- `status = "written" if write else "preview"`.
- Return `{schema_version:1, status, query, query_terms:terms, path:".kimiflow/project/RUN-HISTORY.json", markdown_path:".kimiflow/project/RUN-HISTORY.md", written:write, hits}` (Bash `written: ($written == 1)` -> the bool).

### `run` write path (only on `--write`)
- `mkdir -p project`; `store.atomic_write(project/RUN-HISTORY.json, dumps(obj, pretty=True) + "\n")` (Bash `jq . > json_path`).
- `write_history_markdown(project/RUN-HISTORY.md, obj)`.
- `usage_metrics.update_usage_metrics(root, obj["hits"], "history")`.
- Always: `contracts.json_print(obj, pretty)`.

### `write_history_markdown(path, obj)` (NEW; Bash 1687-1703)
`mkdir -p` parent; emit exactly: `# Run History Recall\n\n`, `Generated: <iso_now>\n\n`, `Query: <obj.query>\n\n`, `Hits: <len(obj.hits)>\n\n`, `## Hits\n\n`, then per hit one line `- [<slug // "run"> <MIDDOT> <artifact // "artifact">] <summary // ""> (<path // "">)\n` (none -> no lines). `store.atomic_write`.

- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/history.py` | NEW: `run`, `history_json`, `write_history_markdown` (+`_jq_or`, `_MIDDOT`). |
| `hooks/memory_router/__main__.py` | register `"history": history.run`. |
| `hooks/memory_router/tests/test_history.py` | NEW: `HistoryRunCase` + `HistoryParityCase` (stdout + written RUN-HISTORY.json/.md/MEMORY-USAGE.json parity vs pinned bash, timestamps normalized). |

---

### Task 1: history

**Step 1 (Red -> Green):** Implement `history.py` + tests + dispatch exactly as specified.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green.
- Grounding (isolated `env -i`, dead detect port): `bash <pinned> history ...` vs `python3 -m memory_router history ...` on separate roots with run-artifacts (incl. a `STATE.md` + `findings/*.md`): stdout identical for query / no-query (`recent`) / `--pretty` / `--max 1`; on `--write` verify RUN-HISTORY.json, RUN-HISTORY.md, and MEMORY-USAGE.json byte-identical after normalizing `Generated:` / `updated_at` / `at` / `last_used_at`. Verify the 3 error paths (bad `--max`, empty trailing `--max`, missing query-file) + unknown-arg.
- ASCII check on `history.py` -> clean.

## Self-Review (grounding evidence)

**Pre-implementation plan-audit** (external vs pinned Bash): 0 BLOCKER/HIGH/MEDIUM. 1 LOW (informational): the `Query:` markdown line drops a *trailing* newline in Bash (command-sub `$(... | jq -r '.query')`) but not in Python — unreachable (only via `--query` carrying a trailing `\n` + `--write`; `--query-file` is `_sed_read`-rstripped, no-query is `"recent"`) AND **byte-identical to the already-shipped `recall.write_recall_markdown` baseline**, so left consistent rather than diverging the two writers. Confirmed the recall-vs-history divergences (boolean `--write`, default `--max 10`, no "requires query" gate) and that `run_artifact_rows_json` returns rows with a `text` key (so the del-text slice is required).

**Grounded byte-for-byte vs the real Bash** (isolated `env -i`, dead detect port):
- In-repo `HistoryParityCase`: stdout identical for `--query auth` / no-query (`recent`) / `--pretty` / `--max 1` / query+pretty / no-match; on `--write` (query and no-query) the written **RUN-HISTORY.json**, **RUN-HISTORY.md**, and **MEMORY-USAGE.json** identical after normalizing only `Generated:` / `updated_at` / `at` / `last_used_at`.
- Manual: all 4 error/unknown-arg paths (bad `--max`, empty trailing `--max`, missing query-file, unknown arg) identical message + exit 2; no-query `--write` RUN-HISTORY.md identical.

**Independent senior-review** (vs Bash, full file): 0 BLOCKER/HIGH, no issues. Verified arg parsing (default 10, boolean `--write`, no requires-query gate), both `history_json` branches (slice-then-del-text, no aliasing), key order + `written` boolean, the write path (`atomic_write`≡`jq .>`, `update_usage_metrics(..., "history")`), and `write_history_markdown` byte-layout incl. the `_jq_or` `//` defaults and the U+00B7 middot.

**Suite:** 342 -> 359 tests, all green. ASCII-clean on `history.py` + tests (middot as `·`). No new §12 row (reuses the recall `--write` atomic-write rationale).
