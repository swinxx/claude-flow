# memory-router Python CLI - Plan 16: `status_json` + `status` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the keystone read: `status_json` (Bash 1399-1568, ~170 lines) - the composed project memory status that assembles every summary aggregator + the provider/vault subsystem + the curation-reason list - and wire `cmd_status` (1810-1824) as the second big read subcommand (after `index`), with an in-repo stdout-parity harness.

**Architecture:** New module `hooks/memory_router/status.py` with `status_json(root)` + `run(argv)`. It composes already-ported helpers: `summaries.*` (read_jsonl/proposal/usage/economics/global_efficiency/learning_lifecycle/learning_usefulness), `provider.status_json/sync_status_json/vault_status_json`, `text.word_count_file`, `recall_index.fts5_available`. Registered in `__main__.COMMANDS`.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `json`); no new deps.

## Global Constraints

- **Drop-in / scope:** new `status.py`, `__main__.py` dispatch entry, new `tests/test_status.py`, one spec §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests.
- **Source of truth:** Bash `status_json` (1399-1568) + `cmd_status` (1810-1824) @ `kimiflow--v0.1.50`. Grounded byte-for-byte by running the WHOLE real Bash script vs the Python CLI (`python3 -m memory_router status`) under isolated `env -i` + a dead detection port - see Self-Review.
- **Key order:** the output object and EVERY nested object preserve the Bash jq literal key order. `($summary + {present,path})` merges keep summary keys in place and append present/path; the provider merge updates the existing `present`/`path` in place and appends `sync` (`dict(obj, **kw)` reproduces jq `+`).
- **Curation reasons (exact conditions + order):** memory_over_budget, stale_learnings, superseded_learnings, learning_lifecycle_review_due, memory_index_missing (`total>0 and not index_present`), many_learnings (`total>=threshold`), recall_index_missing (`total>0 and sqlite_available and not recall_db_present`), learning_proposals_pending/approved/need_revalidation, provider_sync_pending, provider_detected_unconfigured (`status==... and exportable_count>0`), provider_auth_failed (`health.status=="auth_failed"`), provider_auth_required (`health.status=="connected_local_only" and exportable_count>0`), memory_economics_waste_risk (`action_required is True`). `visible_reasons` = all minus `many_learnings`; `silent_reasons` = the `many_learnings`; `recommended` = visible>0; `internal_recommended` = all>0.
- **`present` (top level):** OR of all 12 `*_present` flags. **budget/threshold:** `${VAR:-default}` then `json.loads` (matches `--argjson`). **over_budget:** `memory_tokens > budget`.
- **`sqlite_available`:** `recall_index.fts5_available()` (stdlib FTS5 probe) replaces Bash `command -v sqlite3` - the documented §12 generalization (recall engine row). Feeds both `recall_index.sqlite_available` and the `recall_index_missing` reason.
- **`cmd_status`:** `--root`/`--pretty`/`--help`/`-h`/unknown->`die ... 2`; `need_jq` no-op; `resolve_root`; `json_print`.
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/status.py` | NEW: `_budget`, `status_json`, `run`. |
| `hooks/memory_router/__main__.py` | register `"status": status.run`. |
| `hooks/memory_router/tests/test_status.py` | NEW: `StatusRunCase` (unit, isolated env) + `StatusParityCase` (shells to pinned bash). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (status sqlite_available). |

---

### Task 1: status_json + cmd_status

**Step 1 (Red -> Green):** Implement `status.py` + tests + dispatch exactly as shipped.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (275 with this plan; the StatusParityCase runs in-repo, skips when bash/jq/sqlite3/git or the tag are absent).
- Grounding: run `bash <pinned-script> status --root R` vs `python3 -m memory_router status --root R` under isolated `env -i` (dead detection URL) over empty + populated roots; diff stdout.
- ASCII check on `status.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte by running the WHOLE real Bash script vs the Python CLI under isolated `env -i` (no host `OBSIDIAN_API_KEY`/MCP leak; dead detection port) across: empty root; a richly-populated root (MEMORY.md, mixed-status LEARNINGS, USER.md/jsonl, PROPOSALS pending+approved, MEMORY-USAGE, MEMORY-ECONOMICS, configured+available VAULT-PROVIDER, MEMORY-INDEX vault, RUN-HISTORY, RECALL.md); budget override (over_budget); threshold override (many_learnings -> silent_reason); `--pretty`; `KIMIFLOW_VAULT_AVAILABLE` env; and a connected_local_only -> provider_auth_required + provider_sync_pending scenario (fresh unsynced evidence candidate). All identical. The in-repo `StatusParityCase` (shelling to the pinned bash, shared read-only root) is green.
