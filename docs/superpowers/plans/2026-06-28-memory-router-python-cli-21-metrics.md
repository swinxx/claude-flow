# memory-router Python CLI - Plan 21: `metrics` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_metrics` (Bash 2087-2126) - the token-economics read + the global-metrics purge. **Every dependency is already ported**: `usage_summary_json` / `economics_summary_json` / `global_efficiency_summary_json` (summaries.py) and `global_metrics.base_dir` / `display_path` (global_metrics.py, Plan 12). `cmd_metrics` only READS (global / default) and PURGES (rm two files) - it records nothing, so the salt/hash/record infra is NOT needed here.

**Architecture:** New module `hooks/memory_router/metrics.py` with `run(argv)`. Pure composition + a file-removal branch. Registered in `__main__.COMMANDS`. No new helpers.

**Tech Stack:** Python 3.9+ stdlib only (`os`). No new deps.

## Global Constraints

- **Drop-in / scope:** new `metrics.py`, `tests/test_metrics.py`; `__main__.py` += `"metrics": metrics.run`. No edits to `hooks/memory-router.sh`, other modules, manifests. **No new §12 row.**
- **Source of truth:** Bash `cmd_metrics` (2087-2126) @ `kimiflow--v0.1.50`. Ground byte-for-byte (whole real Bash vs Python CLI, isolated `env -i`, dead detect port).

### Arg parsing (`run`)
`--root`/`--global`(global_only)/`--global-purge`(global_purge)/`--pretty`/`--help`/`-h`/unknown->`die("metrics: unknown argument: <a>", 2)`. `--global`/`--global-purge`/`--pretty` consume no value. `need_jq` no-op.

### Branches (Bash order: purge -> global -> default)
1. **`--global-purge`** (checked FIRST, even if `--global` also passed): `base = global_metrics.base_dir()` (None when no HOME/KIMIFLOW_HOME; Bash `|| true` -> empty). `removed = salt_removed = False`. If `base`: `file = base/token-economics.jsonl`, `salt_file = base/salt`; `os.path.isfile(file)` -> `os.remove` (OSError -> leave False, mirrors `rm -f && removed=true`) -> `removed=True`; same for `salt_file` -> `salt_removed`. Output `{schema_version:1, status:"purged", path: global_metrics.display_path(), removed, salt_removed}`. Return 0.
2. **`--global`**: `json_print(summaries.global_efficiency_summary_json(), pretty)`. Return 0. (reads the global `token-economics.jsonl` internally.)
3. **default**: `root = resolve_root(root)`; `usage = usage_summary_json(root/.kimiflow/project/MEMORY-USAGE.json)`; `run_economics = economics_summary_json(root/.kimiflow/project/MEMORY-ECONOMICS.jsonl)`; `global_efficiency = global_efficiency_summary_json()`. Output = jq `$usage + {usage:$usage, run_economics:$run_economics, global_efficiency:$global_efficiency}` -> `dict(usage)` then set keys `usage`/`run_economics`/`global_efficiency` (jq `+`: left key order kept, the 3 keys appended since `usage_summary_json` never carries them). `json_print(out, pretty)`.

- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/metrics.py` | NEW: `run`. |
| `hooks/memory_router/__main__.py` | register `"metrics": metrics.run`. |
| `hooks/memory_router/tests/test_metrics.py` | NEW: `MetricsRunCase` + `MetricsParityCase` (default / `--global` / `--global-purge` stdout + the purge file-removal, vs pinned bash). |

---

### Task 1: metrics

**Step 1 (Red -> Green):** Implement `metrics.py` + tests + dispatch exactly as specified.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green.
- Grounding (isolated `env -i`, `KIMIFLOW_HOME` pointed at a temp dir so the global file is sandboxed): `bash <pinned> metrics ...` vs `python3 -m memory_router metrics ...`: stdout identical for default (populated MEMORY-USAGE.json + MEMORY-ECONOMICS.jsonl + a global token-economics.jsonl) / `--global` / `--global-purge` (incl. removed/salt_removed true when the files exist and false when absent) / `--pretty`; verify the purge actually deletes `token-economics.jsonl` + `salt` on both sides. Verify the unknown-arg error.
- ASCII check on `metrics.py` -> clean.

## Self-Review (grounding evidence)

**Scope note:** 1-file pure composition of already-parity-verified helpers (summaries + global_metrics) — external pre-impl plan-audit skipped per the mini-fix rule; byte-for-byte grounding is the primary gate.

**Grounded byte-for-byte vs the real Bash** (isolated `env -i`, `KIMIFLOW_HOME` sandboxed to a temp dir):
- In-repo `MetricsParityCase`: stdout identical for default (populated MEMORY-USAGE.json + MEMORY-ECONOMICS.jsonl + global token-economics.jsonl) / `--global` / `--pretty` variants; `--global-purge` stdout identical AND both sides actually delete the global file.
- Manual edges: default with absent files (empty project) identical; `--global-purge` with neither `KIMIFLOW_HOME` nor `HOME` (base_dir None) identical (`removed:false, salt_removed:false`, exit 0); `--global-purge` with only `token-economics.jsonl` present (no salt) identical (`removed:true, salt_removed:false`).

**Independent senior-review** (vs Bash): 0 BLOCKER/HIGH, no issues. Verified branch precedence (purge->global->default), the purge `base` falsy guard + `os.remove`-success-only `removed`/`salt_removed` + output key order + `display_path()` when base is None, the default `dict(usage)`+sequential-set merge matching jq `$usage + {...}`, and no shadowing of the imported `usage` function.

**Suite:** 359 -> 368 tests, all green. ASCII-clean on `metrics.py` + tests.
