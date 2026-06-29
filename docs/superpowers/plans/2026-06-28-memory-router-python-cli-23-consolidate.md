# memory-router Python CLI - Plan 23: `consolidate` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_consolidate` (Bash 3931-3986) - archive superseded learnings, drop them from `LEARNINGS.jsonl`, refresh bounded memory + curate + index, and report current/superseded counts + duplicate groups. **All dependencies already ported** (`jsonl_rows`=`store.read_jsonl`, `write_bounded_memory`/`write_bounded_user_memory`, `curate.run`, `index.run`).

**Architecture:** New module `hooks/memory_router/consolidate.py` with `run(argv)` + `consolidate_json(rows, write)`. Registered in `__main__.COMMANDS`. Reuses `store`, `memory_md`, `curate`, `index`, `contracts`.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `io`, `contextlib`, `itertools`). No new deps.

## Global Constraints

- **Drop-in / scope:** new `consolidate.py`, `tests/test_consolidate.py`; `__main__.py` += `"consolidate": consolidate.run`. No edits to `hooks/memory-router.sh`, manifests. **No new §12 row** (reuses the bounded-memory §12 + curate atomic-write rationale; the LEARNINGS rewrite mirrors the `writes.py` atomic mktemp+mv pattern; the archive append mirrors Bash `>>`).
- **Source of truth:** Bash `cmd_consolidate` (3931-3986) @ `kimiflow--v0.1.50`. Ground byte-for-byte (whole real Bash vs Python CLI, isolated `env -i`).

### `run(argv)` / `consolidate_json`
- Args `--root`/`--write`/`--pretty`/`--help`/`-h`/unknown->`die("consolidate: unknown argument: <a>", 2)`. `need_jq` no-op. `root = resolve_root(root)`.
- `rows = store.read_jsonl(LEARNINGS.jsonl)`. `superseded = [r for r if (.status // "") == "superseded"]`; `current = [r for r if (.status // "current") == "current"]` (non-dict rows skipped - unreachable).
- `duplicates`: jq `sort_by(k) | group_by(k) | map(select(length>1) | {summary:.[0].summary//"", ids: map(.id)})` where `k = (kind//"")+"|"+(scope//"")+"|"+(topic//"")+"|"+(summary//"")`. Port: `sorted(current, key=k)` (stable) + `itertools.groupby(.., key=k)`, groups with len>1 -> `{summary: grp[0].summary//"", ids: [r.id]}` (id may be null; group/ids order = stable-sorted = original order for equal keys).
- **`--write` AND `LEARNINGS.jsonl` exists:** `mkdir project`; if `superseded`: append each (compact JSON + `\n`) to `LEARNINGS.archive.jsonl` (`store.append_line`, mirrors Bash `>>`); rewrite `LEARNINGS.jsonl` to the rows with `status != "superseded"` (compact each) via `store.atomic_write(refuse_symlink=False)` (mirrors Bash mktemp+mv); `write_bounded_memory` + `write_bounded_user_memory`; `curate.run(--write)` (stdout suppressed); `index.run(--write)` (stdout+stderr suppressed, errors ignored).
- **Output** (EXACT key order): `{schema_version:1, status:("consolidated" if write else "preview"), written:write(bool), archive_path:".kimiflow/project/LEARNINGS.archive.jsonl", current_count:len(current), archived_superseded_count:len(superseded), duplicate_groups:duplicates}`. `json_print(out, pretty)`.

- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/consolidate.py` | NEW: `run`, `consolidate_json` (+`_jq_or`, `_dup_key`). |
| `hooks/memory_router/__main__.py` | register `"consolidate": consolidate.run`. |
| `hooks/memory_router/tests/test_consolidate.py` | NEW: `ConsolidateRunCase` + `ConsolidateParityCase` (preview / write archive+rewrite + duplicate groups, vs pinned bash). |

---

### Task 1: consolidate

**Step 1 (Red -> Green):** Implement `consolidate.py` + tests + dispatch.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green.
- Grounding (isolated `env -i`): `bash <pinned> consolidate ...` vs `python3 -m memory_router consolidate ...` on a LEARNINGS.jsonl with superseded + current + duplicate rows: stdout identical for preview / `--write` / `--pretty`; on `--write` verify `LEARNINGS.jsonl` (superseded dropped), `LEARNINGS.archive.jsonl` (superseded appended), and MEMORY.md/USER.md/MEMORY-INDEX.json/RECALL.sqlite are produced; duplicate_groups byte-identical.
- ASCII check on `consolidate.py` -> clean.

## Self-Review (grounding evidence)

**Grounded byte-for-byte vs the real Bash** (isolated `env -i`, dead detect port):
- In-repo `ConsolidateParityCase`: stdout identical for preview / `--pretty`; on `--write` the rewritten `LEARNINGS.jsonl` (superseded dropped) AND `LEARNINGS.archive.jsonl` (superseded appended) byte-identical; mixed superseded/current/stale + duplicate rows.
- Manual: `--write` with NO superseded rows -> stdout identical, archive correctly NOT created on either side, LEARNINGS identical.

**Independent senior-review** (vs Bash): 0 BLOCKER/HIGH, no issues. Confirmed arg parsing, the `// ""` vs `// "current"` filters, the duplicate grouping (key + group order + within-group id order, with jq `sort_by`/`group_by` stability **empirically** matched to Python's stable `sorted`+`itertools.groupby`), the write path (append + atomic rewrite keeping non-superseded incl. stale, bounded-memory + curate + index suppression), and the exact output key order + status/written keyed off `--write`.

**Suite:** 390 -> 399 tests, all green. ASCII-clean on `consolidate.py` + tests.
