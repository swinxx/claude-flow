# memory-router Python CLI - Plan 9: foundational summary aggregators

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the two foundational JSONL summary aggregators - `read_jsonl_summary` (Bash 135-171) and `proposal_summary_json` (Bash 79-110). Each reads a JSONL file and returns a fixed-shape counts-by-status/type summary dict. These are the first members of the summary-helper family that `status_json` (and, for `read_jsonl_summary`, `cmd_curate`) compose; the larger aggregators (`usage`/`economics`/`global_efficiency`/`lifecycle`/`usefulness`) and the provider/vault subsystem follow in later plans.

**Why these two first (smallest coherent block):** they are the smallest, cleanest, mutually-independent aggregators (same "read a JSONL, count rows by a field" shape), so they establish the `summaries.py` module + the jq-aggregator grounding pattern before the 100+-line `economics`/`global_efficiency` pipelines. `usage_summary_json` is deliberately excluded - it reads a single JSON object (`MEMORY-USAGE.json`) with a nested `by_event` reduce, a different shape that warrants its own focused plan.

**Architecture:** New module `hooks/memory_router/summaries.py`. Behavioral ports using `store.read_jsonl` (malformed lines skipped, matching jq `fromjson? // empty`) and a private `_jq_or` (jq `//` null/false semantics, mirroring `recall_index._jq_or`). Each returns a Python **dict**; serialization stays at the `contracts.dumps` boundary in the calling subcommand (like `recall_index.fts_hits_json`). No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only (`os`); no new deps.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** changes exactly: new `summaries.py`, new `tests/test_summaries.py`. No edits to `hooks/memory-router.sh`, other modules, manifests, or the spec (no new §12 divergence - see below). No subcommand wiring.
- **Source of truth:** Bash `read_jsonl_summary` (135-171) + `proposal_summary_json` (79-110) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (key order + values) against the real extracted Bash functions across 7 fixture scenarios - see Self-Review.
- **`read_jsonl_summary(path) -> dict`, exact key order:** `total, current, stale, superseded, archived, private, security, by_topic`.
  - `total` = row count. `current` counts `_jq_or(.status, "current") == "current"` (missing/null/false status -> current). `stale`/`superseded`/`archived` count `_jq_or(.status, "") == <name>` (only explicit values; `""` status counts in none). `private`/`security` count `_jq_or(.sensitivity, "") == <name>`.
  - `by_topic`: count per `_jq_or(.topic, "uncategorized")`, emitted **sorted by topic key** (jq `sort_by | group_by | from_entries`; codepoint order -> uppercase before lowercase).
  - missing file -> the all-zero shape; an existing empty file yields the identical result through the row path.
- **`proposal_summary_json(path) -> dict`, exact key order:** `present, path, total, pending, approved, applied, rejected, needs_revalidation, by_type`.
  - `path` is always the literal `.kimiflow/project/PROPOSALS.jsonl`. Missing file -> `present:false` + all-zero. Present -> `present:true`.
  - `pending` counts `_jq_or(.status, "pending") == "pending"` (missing/null/false -> pending); other buckets default to `""`.
  - `by_type`: count per `_jq_or(.type, "unknown")`, emitted in **first-appearance order** (jq `reduce` - NOT sorted, unlike `by_topic`).
- **jq `//` semantics:** `_jq_or(value, default)` substitutes the default only when value is `None`/`False`; `""`/`0` pass through (truthy in jq).
- **Malformed lines:** `store.read_jsonl` skips unparseable lines - identical to jq `fromjson? // empty`. (No divergence, unlike the FACTS case in §12.)
- **No new §12 divergence:** jq `//`, `fromjson?`-skip, and sorted/first-appearance ordering are all replicated. The helpers' internal pretty (`jq -n`) vs compact (`jq -Rsc`) output is irrelevant - they return dicts serialized once at the subcommand boundary.
- **Commits:** named paths only; no co-author / AI-attribution trailer.
- **Branch:** continue on `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/summaries.py` | new: `read_jsonl_summary`, `proposal_summary_json`, private `_jq_or`. |
| `hooks/memory_router/tests/test_summaries.py` | new: `ReadJsonlSummaryCase` + `ProposalSummaryCase`. |

---

### Task 1: `summaries.py` (read_jsonl_summary + proposal_summary_json)

**Files:** Create `summaries.py`, `tests/test_summaries.py`.

**Interfaces:** Produces (status_json / cmd_curate consume): `summaries.read_jsonl_summary(path) -> dict`, `summaries.proposal_summary_json(path) -> dict`. Consumes: `store.read_jsonl`.

- [ ] **Step 1: Write the failing tests** - create `tests/test_summaries.py` (full file):

```python
# hooks/memory_router/tests/test_summaries.py
import os
import shutil
import tempfile
import unittest

from memory_router import summaries


class _FixtureCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def write(self, name, lines):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("".join(line + "\n" for line in lines))
        return path

    def missing(self, name="nope.jsonl"):
        return os.path.join(self.dir, name)


class ReadJsonlSummaryCase(_FixtureCase):
    EMPTY = {
        "total": 0, "current": 0, "stale": 0, "superseded": 0, "archived": 0,
        "private": 0, "security": 0, "by_topic": {},
    }

    def test_missing_file_empty_shape(self):
        result = summaries.read_jsonl_summary(self.missing())
        self.assertEqual(result, self.EMPTY)
        self.assertEqual(list(result.keys()), list(self.EMPTY.keys()))

    def test_empty_file_matches_missing_shape(self):
        self.assertEqual(summaries.read_jsonl_summary(self.write("e.jsonl", [])), self.EMPTY)

    def test_status_buckets_and_defaults(self):
        path = self.write("L.jsonl", [
            '{"status":"current","topic":"b"}',
            '{"topic":"b"}',            # missing status -> current
            '{"status":null,"topic":"b"}',   # null -> current
            '{"status":"","topic":"b"}',     # "" -> counted nowhere but total
            '{"status":"stale","topic":"a"}',
            '{"status":"superseded","topic":"a"}',
            '{"status":"archived","topic":"a"}',
        ])
        r = summaries.read_jsonl_summary(path)
        self.assertEqual(r["total"], 7)
        self.assertEqual(r["current"], 3)   # explicit + missing + null
        self.assertEqual((r["stale"], r["superseded"], r["archived"]), (1, 1, 1))

    def test_sensitivity_buckets(self):
        path = self.write("L.jsonl", [
            '{"sensitivity":"private"}', '{"sensitivity":"security"}',
            '{"sensitivity":"normal"}', '{}',
        ])
        r = summaries.read_jsonl_summary(path)
        self.assertEqual((r["private"], r["security"]), (1, 1))

    def test_by_topic_sorted_with_uncategorized_default(self):
        path = self.write("L.jsonl", [
            '{"topic":"banana"}', '{"topic":"Apple"}', '{"topic":"apple"}', '{}', '{"topic":"Apple"}',
        ])
        r = summaries.read_jsonl_summary(path)
        # jq sort_by -> codepoint order: uppercase before lowercase.
        self.assertEqual(list(r["by_topic"].keys()), ["Apple", "apple", "banana", "uncategorized"])
        self.assertEqual(r["by_topic"], {"Apple": 2, "apple": 1, "banana": 1, "uncategorized": 1})

    def test_malformed_lines_skipped(self):
        path = self.write("L.jsonl", ['{"status":"current","topic":"x"}', 'NOT JSON', '   '])
        self.assertEqual(summaries.read_jsonl_summary(path)["total"], 1)

    def test_key_order(self):
        path = self.write("L.jsonl", ['{"topic":"x"}'])
        self.assertEqual(list(summaries.read_jsonl_summary(path).keys()), list(self.EMPTY.keys()))


class ProposalSummaryCase(_FixtureCase):
    PATH = ".kimiflow/project/PROPOSALS.jsonl"

    def test_missing_file_present_false(self):
        r = summaries.proposal_summary_json(self.missing())
        self.assertEqual(r, {
            "present": False, "path": self.PATH, "total": 0, "pending": 0,
            "approved": 0, "applied": 0, "rejected": 0, "needs_revalidation": 0,
            "by_type": {},
        })

    def test_status_buckets_and_defaults(self):
        path = self.write("P.jsonl", [
            '{"status":"pending"}', '{}', '{"status":null}',   # missing/null -> pending
            '{"status":""}',                                    # "" -> nowhere but total
            '{"status":"approved"}', '{"status":"applied"}',
            '{"status":"rejected"}', '{"status":"needs_revalidation"}',
        ])
        r = summaries.proposal_summary_json(path)
        self.assertTrue(r["present"])
        self.assertEqual(r["total"], 8)
        self.assertEqual(r["pending"], 3)
        self.assertEqual((r["approved"], r["applied"], r["rejected"], r["needs_revalidation"]),
                         (1, 1, 1, 1))

    def test_by_type_first_appearance_order_not_sorted(self):
        path = self.write("P.jsonl", [
            '{"type":"zeta"}', '{"type":"alpha"}', '{"type":"zeta"}', '{}',
        ])
        r = summaries.proposal_summary_json(path)
        # reduce -> first-appearance order (NOT sorted): zeta, alpha, unknown.
        self.assertEqual(list(r["by_type"].keys()), ["zeta", "alpha", "unknown"])
        self.assertEqual(r["by_type"], {"zeta": 2, "alpha": 1, "unknown": 1})

    def test_malformed_lines_skipped(self):
        path = self.write("P.jsonl", ['{"status":"pending","type":"x"}', 'GARBAGE'])
        self.assertEqual(summaries.proposal_summary_json(path)["total"], 1)

    def test_key_order(self):
        path = self.write("P.jsonl", ['{"status":"pending","type":"x"}'])
        self.assertEqual(list(summaries.proposal_summary_json(path).keys()), [
            "present", "path", "total", "pending", "approved", "applied",
            "rejected", "needs_revalidation", "by_type",
        ])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: FAIL - `ModuleNotFoundError: No module named 'memory_router.summaries'`.

- [ ] **Step 3: Write `summaries.py`** (full file):

```python
# hooks/memory_router/summaries.py
"""JSONL summary aggregators (status/type counters). Behavioral ports of the Bash
read_jsonl_summary / proposal_summary_json at kimiflow--v0.1.50 (135-171, 79-110).
Each reads a JSONL file (malformed lines skipped, matching jq `fromjson? // empty`)
and returns a fixed-shape summary dict; serialization stays at the contracts.dumps
boundary in the calling subcommand."""
import os

from . import store

_PROPOSALS_PATH = ".kimiflow/project/PROPOSALS.jsonl"


def _jq_or(value, default):
    # jq `value // default`: substitute when value is null (None) or false; "" / 0
    # are truthy in jq and pass through. (Mirrors recall_index._jq_or.)
    return default if value is None or value is False else value


def read_jsonl_summary(path):
    # Bash read_jsonl_summary (135-171): counts by status/sensitivity plus a
    # topic->count map. Missing file -> the all-zero shape (identical to an empty
    # file through the jq branch). `current` defaults missing status to "current";
    # the other status/sensitivity buckets default to "" so only explicit values count.
    if not os.path.isfile(path):
        rows = []
    else:
        rows = store.read_jsonl(path)

    counts = {}
    for row in rows:
        topic = _jq_or(row.get("topic"), "uncategorized")
        counts[topic] = counts.get(topic, 0) + 1
    by_topic = {key: counts[key] for key in sorted(counts)}  # jq sort_by + group_by

    def status_is(value):
        return sum(1 for r in rows if _jq_or(r.get("status"), "") == value)

    def sensitivity_is(value):
        return sum(1 for r in rows if _jq_or(r.get("sensitivity"), "") == value)

    return {
        "total": len(rows),
        "current": sum(1 for r in rows if _jq_or(r.get("status"), "current") == "current"),
        "stale": status_is("stale"),
        "superseded": status_is("superseded"),
        "archived": status_is("archived"),
        "private": sensitivity_is("private"),
        "security": sensitivity_is("security"),
        "by_topic": by_topic,
    }


def proposal_summary_json(path):
    # Bash proposal_summary_json (79-110): PROPOSALS.jsonl counts by status, plus a
    # type->count map. by_type uses jq `reduce` -> first-appearance key order (NOT
    # sorted, unlike read_jsonl_summary's by_topic). `pending` defaults missing
    # status to "pending"; the other buckets default to "".
    if not os.path.isfile(path):
        return {
            "present": False,
            "path": _PROPOSALS_PATH,
            "total": 0,
            "pending": 0,
            "approved": 0,
            "applied": 0,
            "rejected": 0,
            "needs_revalidation": 0,
            "by_type": {},
        }

    rows = store.read_jsonl(path)
    by_type = {}
    for row in rows:
        kind = _jq_or(row.get("type"), "unknown")
        by_type[kind] = by_type.get(kind, 0) + 1

    def status_is(value, default=""):
        return sum(1 for r in rows if _jq_or(r.get("status"), default) == value)

    return {
        "present": True,
        "path": _PROPOSALS_PATH,
        "total": len(rows),
        "pending": status_is("pending", "pending"),
        "approved": status_is("approved"),
        "applied": status_is("applied"),
        "rejected": status_is("rejected"),
        "needs_revalidation": status_is("needs_revalidation"),
        "by_type": by_type,
    }
```

- [ ] **Step 4: Run the focused tests**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: PASS - 12 tests.

- [ ] **Step 5: Full suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (176 tests: 164 prior + 12 new).

- [ ] **Step 6: Commit**

```bash
git add hooks/memory_router/summaries.py hooks/memory_router/tests/test_summaries.py
git commit -m "feat(memory_router): foundational summary aggregators (read_jsonl_summary, proposal_summary_json)"
```

---

## Self-Review

**1. Spec coverage:** both Bash functions map verbatim - the status/sensitivity buckets with their distinct defaults (`current` -> "current"; others -> ""), the `by_topic` (sorted) vs `by_type` (first-appearance) ordering distinction, the missing-file shapes, and the exact output key order in every branch. No subcommand or other module touched.

**2. Empirical grounding (decisive):** the two real Bash functions were extracted into a harness and run on 7 fixture scenarios (missing / empty / mixed statuses incl. null + "" + missing / sensitivities / topic-sort with case+unicode+missing / malformed lines / by_type first-appearance). Each Bash output was normalized through `jq -c .` (preserving key order) and diffed against the Python `contracts.dumps` of the returned dict - **all identical** (7/7), confirming key order, values, the sorted-vs-first-appearance ordering, and the jq-`//` null/false defaults.

**3. Placeholder scan:** complete code in every step; no TBD; pure ASCII.

**4. Type consistency:** `read_jsonl_summary(path) -> dict`, `proposal_summary_json(path) -> dict` (Python objects; serialization at the `contracts.dumps` boundary later). `_jq_or` is a private 2-line replica of `recall_index._jq_or` - a future consolidation into a shared jq-helper module is noted but deferred (avoids touching the healed `recall_index`).

## Notes for later plans (not part of this plan)
- **`usage_summary_json`** (Bash 184-241): reads `MEMORY-USAGE.json` (single object), nested `by_event` reduce with per-kind accumulation + `last_at` max - its own plan.
- **`economics_summary_json`** (243-364, ~122 lines) and **`global_efficiency_summary_json`** (483-597, ~115 lines): the large economics pipelines.
- **`learning_lifecycle_json`** (599-651) + **`learning_usefulness_json`** (653-712).
- **provider/vault subsystem** (`provider_status_json` 1197-1292, `provider_sync_status_json` 1325-1351, `vault_status_json` 1353-1397).
- **`status_json`** (1399-1568) composes all the above; then `cmd_status`, then `curate`, then `record`.
- **Shared `_jq_or`:** once a 3rd+ consumer lands, consolidate the `_jq_or` replicas (recall_index, summaries) into a shared helper module.
