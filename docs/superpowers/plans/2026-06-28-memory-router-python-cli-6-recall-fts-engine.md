# memory-router Python CLI — Plan 6: RECALL.sqlite FTS5 engine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the RECALL.sqlite **FTS5 engine** — the queryable full-text index machinery: FTS5-availability detection, schema init (`recall_meta` + `recall_fts`), single-row insert, the term→`MATCH`-query builder, and the hit query with graceful degradation. This is the risk-heavy core of the recall subsystem; `recall`/`status`/`economics` (later plans) compose it.

**Architecture:** New module `hooks/memory_router/recall_index.py`. Behavioral port of the Bash `sqlite_available` / `fts_query_from_terms` / `insert_fts_row` / the recall schema / `fts_hits_json` at `kimiflow--v0.1.50` (2527-2644), using the Python **stdlib `sqlite3` module** instead of shelling to the `sqlite3` CLI. The multi-source `build_recall_index` population (Bash 2547-2621) is deliberately deferred to **Plan 7** — this plan delivers the engine it will call, tested standalone by building a small index inline.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `re`, `sqlite3` — FTS5 confirmed available in the macOS system `python3`'s sqlite 3.51.0); no new third-party deps; **no `sqlite3` CLI dependency**.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** no edits to `hooks/memory-router.sh`, SKILL.md, reference.md, manifests, existing tests, or unrelated modules. This plan adds exactly: `recall_index.py`, `tests/test_recall_index.py`, and one row appended to spec §12. **No subcommand wiring** (Plan 8); **`build_recall_index` population is Plan 7**.
- **Source of truth:** Bash @ `kimiflow--v0.1.50`:
  - `sqlite_available` (2527-2529), `fts_query_from_terms` (2531-2540), `insert_fts_row` (2542-2545), the recall schema (2559-2565), `fts_hits_json` (2623-2644).
  - depends on already-ported `clock.iso_now`.
- **Schema is exact** (Bash 2562-2563): `recall_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)` + `CREATE VIRTUAL TABLE recall_fts USING fts5(kind, source, title, body, ref)`; `init` stamps `recall_meta.updated_at = iso_now`.
- **`fts_query_from_terms` is exact** (Bash 2531-2540): for each input term, strip every char not in `[A-Za-z0-9_]`; keep terms whose **stripped** length `>= 3`; `unique` (jq `unique` SORTS by codepoint then dedups — case-sensitive ASCII, uppercase before lowercase); quote each as `"<term>"`; join with `" OR "`. Returns `""` when nothing survives. Input `terms` is a Python `list`.
- **`fts_hits_json` query is exact** (Bash 2635): `SELECT kind, source, title, ref, substr(body, 1, 420) AS summary FROM recall_fts WHERE recall_fts MATCH '<query>' LIMIT <max>`. Returns a `list[dict]` (Python objects — serialization stays at the `contracts.dumps` boundary in the calling subcommand). The `summary` is the first 420 chars of `body` (sqlite `substr` is 1-indexed).
- **Graceful degradation → `[]`** (Bash 2627-2643): when FTS5 is unavailable, the db file is missing, the built query is empty, or any sqlite error occurs.
- **Engine divergence (stdlib module vs CLI), spec §12:** Bash gates on `command -v sqlite3` (the CLI binary) and shells out per operation with `sql_quote` string interpolation. This port uses the stdlib `sqlite3` module: it **probes FTS5** (the module is always importable but FTS5 may not be compiled in) and binds **parameters** instead of quoting. Equivalent on targets where both have FTS5; the port additionally works where only the module has FTS5, and degrades gracefully where FTS5 is absent. The module's bundled sqlite version may differ from the system CLI, so FTS5 tokenization/ranking could differ at the margin — parity is verified on the harness host (default `unicode61` tokenizer, simple quoted-OR queries are stable).
- **Nondeterminism:** `recall_meta.updated_at = clock.iso_now()` — unit tests monkeypatch it.
- **Commits:** named paths only; no co-author / AI-attribution trailer.
- **Branch:** continue on `feat/memory-router-py-foundation`.

## Module placement rationale

The FTS engine is a distinct subsystem (sqlite/FTS5 machinery) with one responsibility — own module `recall_index.py`, depending only on `clock` + stdlib. Splitting the engine (this plan) from the multi-source `build_recall_index` population (Plan 7) keeps each piece independently testable and isolates the highest-risk part (sqlite/FTS5 parity) for focused review. Matches the Plan 2/3/4/5 precedent of cohesive helper modules.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/recall_index.py` | `fts5_available`, `recall_db_path`, `init_recall_db`, `insert_fts_row`, `fts_query_from_terms`, `fts_hits_json`. |
| `hooks/memory_router/tests/test_recall_index.py` | unit tests (term-query parity, FTS5 probe, schema/insert/query roundtrip, OR-match, LIMIT, summary truncation, all four degradation paths). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (sqlite stdlib-module-vs-CLI engine divergence). |

---

### Task 1: RECALL.sqlite FTS5 engine (`recall_index.py`)

**Files:**
- Create: `hooks/memory_router/recall_index.py`
- Test: `hooks/memory_router/tests/test_recall_index.py`
- Edit: spec §12 (append one divergence row)

**Interfaces:**
- Consumes: `clock.iso_now`.
- Produces (Plan 7/8 consume):
  - `recall_index.fts5_available() -> bool`
  - `recall_index.recall_db_path(root) -> str`
  - `recall_index.init_recall_db(con) -> None` (drops+creates schema, stamps `updated_at`)
  - `recall_index.insert_fts_row(con, kind, source, title, body, ref) -> None`
  - `recall_index.fts_query_from_terms(terms: list) -> str`
  - `recall_index.fts_hits_json(root, terms: list, max_hits: int) -> list[dict]`

- [ ] **Step 1: Write the failing tests**

```python
# hooks/memory_router/tests/test_recall_index.py
import os
import shutil
import sqlite3
import tempfile
import unittest
from unittest import mock

from memory_router import recall_index

ISO = "2026-06-29T00:00:00Z"


class FtsQueryFromTermsCase(unittest.TestCase):
    def q(self, terms):
        return recall_index.fts_query_from_terms(terms)

    def test_basic_sorted_and_quoted(self):
        self.assertEqual(self.q(["build", "auth"]), '"auth" OR "build"')

    def test_strips_non_term_chars(self):
        self.assertEqual(self.q(["foo-bar!"]), '"foobar"')

    def test_drops_terms_shorter_than_three(self):
        self.assertEqual(self.q(["ab", "abc", "x"]), '"abc"')

    def test_unique_dedups_and_sorts(self):
        self.assertEqual(self.q(["zoo", "abc", "abc", "zoo"]), '"abc" OR "zoo"')

    def test_underscore_kept(self):
        self.assertEqual(self.q(["foo_bar"]), '"foo_bar"')

    def test_empty_when_all_filtered(self):
        self.assertEqual(self.q(["a", "b!", ""]), "")

    def test_length_measured_after_stripping(self):
        # "a-b" strips to "ab" (len 2) -> dropped.
        self.assertEqual(self.q(["a-b"]), "")


class FtsEngineCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.project = os.path.join(self.root, ".kimiflow", "project")
        os.makedirs(self.project, exist_ok=True)
        self.db = recall_index.recall_db_path(self.root)
        p = mock.patch("memory_router.clock.iso_now", return_value=ISO)
        p.start()
        self.addCleanup(p.stop)

    def build(self, rows):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        for r in rows:
            recall_index.insert_fts_row(con, *r)
        con.commit()
        con.close()

    def test_fts5_available(self):
        self.assertTrue(recall_index.fts5_available())

    def test_init_stamps_updated_at(self):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        con.commit()
        value = con.execute(
            "SELECT value FROM recall_meta WHERE key = 'updated_at'"
        ).fetchone()[0]
        con.close()
        self.assertEqual(value, ISO)

    def test_query_roundtrip_returns_hit_shape(self):
        self.build([
            ("learning", ".kimiflow/project/LEARNINGS.jsonl", "build flow",
             "we fixed the build flow and release convention", "src/foo.py:5"),
            ("memory", ".kimiflow/project/MEMORY.md", "Project Memory",
             "auth token rotation chosen", ".kimiflow/project/MEMORY.md"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0], {
            "kind": "learning",
            "source": ".kimiflow/project/LEARNINGS.jsonl",
            "title": "build flow",
            "ref": "src/foo.py:5",
            "summary": "we fixed the build flow and release convention",
        })

    def test_or_query_matches_multiple(self):
        self.build([
            ("learning", "L", "t1", "build pipeline", "r1"),
            ("memory", "M", "t2", "auth rotation", "r2"),
            ("fact", "F", "t3", "unrelated text", "r3"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build", "auth"], 10)
        self.assertEqual({h["ref"] for h in hits}, {"r1", "r2"})

    def test_limit_respected(self):
        self.build([("learning", "L", "t%d" % i, "build flow", "r%d" % i) for i in range(5)])
        self.assertEqual(len(recall_index.fts_hits_json(self.root, ["build"], 2)), 2)

    def test_summary_truncated_to_420(self):
        self.build([("learning", "L", "t", "build " + "x" * 500, "r")])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits[0]["summary"]), 420)

    def test_missing_db_returns_empty(self):
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_empty_query_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        self.assertEqual(recall_index.fts_hits_json(self.root, ["ab", "x"], 10), [])

    def test_corrupt_db_returns_empty(self):
        with open(self.db, "w", encoding="utf-8") as fh:
            fh.write("this is not a sqlite database")
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_unavailable_fts5_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        with mock.patch("memory_router.recall_index.fts5_available", return_value=False):
            self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_recall_index -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'memory_router.recall_index'` (import error before tests run).

- [ ] **Step 3: Write `recall_index.py`**

```python
# hooks/memory_router/recall_index.py
"""RECALL.sqlite FTS5 engine: availability probe, schema init, row insert, term ->
MATCH-query construction, and the hit query with graceful degradation. Behavioral
port of the Bash sqlite_available / fts_query_from_terms / insert_fts_row / the
recall schema / fts_hits_json at kimiflow--v0.1.50 (2527-2644). Uses the Python
stdlib `sqlite3` module instead of shelling to the `sqlite3` CLI."""
import os
import re
import sqlite3

from . import clock

# Source of truth: Bash 2562-2563.
_SCHEMA = (
    "DROP TABLE IF EXISTS recall_meta;\n"
    "DROP TABLE IF EXISTS recall_fts;\n"
    "CREATE TABLE recall_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);\n"
    "CREATE VIRTUAL TABLE recall_fts USING fts5(kind, source, title, body, ref);"
)

_NON_TERM = re.compile(r"[^A-Za-z0-9_]")


def fts5_available():
    # Bash gates on `command -v sqlite3` (the CLI). The stdlib sqlite3 module is
    # always importable, but FTS5 may not be compiled in, so we probe it. See spec 12.
    try:
        con = sqlite3.connect(":memory:")
    except sqlite3.Error:
        return False
    try:
        con.execute("CREATE VIRTUAL TABLE _probe USING fts5(x)")
        return True
    except sqlite3.Error:
        return False
    finally:
        con.close()


def recall_db_path(root):
    return os.path.join(root, ".kimiflow", "project", "RECALL.sqlite")


def init_recall_db(con):
    # Bash 2559-2565: drop+create the schema, then stamp recall_meta.updated_at.
    con.executescript(_SCHEMA)
    con.execute(
        "INSERT INTO recall_meta(key, value) VALUES('updated_at', ?)", (clock.iso_now(),)
    )


def insert_fts_row(con, kind, source, title, body, ref):
    # Bash 2542-2545 uses sql_quote string interpolation; the stdlib module binds
    # parameters instead (equivalent result, no quoting bugs).
    con.execute(
        "INSERT INTO recall_fts(kind, source, title, body, ref) VALUES(?, ?, ?, ?, ?)",
        (kind, source, title, body, ref),
    )


def fts_query_from_terms(terms):
    # Bash 2531-2540 (jq): strip each term to [A-Za-z0-9_], keep length >= 3,
    # `unique` (jq sorts + dedups), quote each, join with " OR ".
    cleaned = {_NON_TERM.sub("", str(term)) for term in terms}
    kept = sorted(t for t in cleaned if len(t) >= 3)
    return " OR ".join('"' + t + '"' for t in kept)


def fts_hits_json(root, terms, max_hits):
    # Bash 2623-2644: graceful degradation -> [] when sqlite/fts5 absent, db missing,
    # query empty, or any sqlite error.
    db = recall_db_path(root)
    if not fts5_available() or not os.path.isfile(db):
        return []
    query = fts_query_from_terms(terms)
    if not query:
        return []
    try:
        con = sqlite3.connect(db)
    except sqlite3.Error:
        return []
    try:
        cur = con.execute(
            "SELECT kind, source, title, ref, substr(body, 1, 420) AS summary "
            "FROM recall_fts WHERE recall_fts MATCH ? LIMIT ?",
            (query, max_hits),
        )
        columns = [d[0] for d in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]
    except sqlite3.Error:
        return []
    finally:
        con.close()
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_recall_index -v`
Expected: PASS — 17 tests OK.

- [ ] **Step 5: Run the full package suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (120 tests: 103 prior + 17 new). `PATH` exports homebrew so the `contracts` test finds `jq`.

- [ ] **Step 6: Append spec §12 divergence row**

Append to the table in `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` §12:

```
| RECALL.sqlite engine (`sqlite_available` / `insert_fts_row` / `fts_hits_json`) | gates on `command -v sqlite3` (CLI), shells out per op with `sql_quote` string interpolation | uses the stdlib `sqlite3` module: probes FTS5 availability and binds parameters | The module is always importable, so the port probes FTS5 (catches a missing-FTS5 build) and degrades to `[]` when absent; parameter binding replaces `sql_quote` (equivalent, no quoting bugs). The module's bundled sqlite version may differ from the system CLI, so FTS5 tokenization/ranking could differ at the margin; parity verified on the harness host (default unicode61 tokenizer; simple quoted-OR queries). |
```

- [ ] **Step 7: Commit**

```bash
git add hooks/memory_router/recall_index.py hooks/memory_router/tests/test_recall_index.py docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "feat(memory_router): RECALL.sqlite FTS5 engine (availability, schema, query)"
```

---

## Self-Review

**1. Spec coverage:** the five Bash functions map verbatim — `sqlite_available`→`fts5_available` (probe), `fts_query_from_terms` (jq transform), `insert_fts_row` (parameterized), the schema (`init_recall_db`), `fts_hits_json` (query + degradation). `build_recall_index` (population) is explicitly out of scope (Plan 7). No subcommand touched.

**2. Placeholder scan:** complete code in every step; no TBD/vague items; no non-ASCII in the source.

**3. Parity nuances captured & tested:** (a) `fts_query_from_terms` strip→len≥3→unique-sort→quote→OR-join confirmed byte-for-byte against the real jq (8 inputs incl. mixed-case sort); (b) schema + `updated_at` stamp; (c) hit shape `{kind, source, title, ref, summary}` with `substr(body,1,420)` confirmed against `sqlite3 -json`; (d) OR-match across rows; (e) LIMIT; (f) summary 420-truncation; (g) all four degradation paths (missing db, empty query, corrupt db, FTS5 unavailable) → `[]`.

**4. Type consistency:** connection-taking helpers (`init_recall_db`, `insert_fts_row`) for the build path (Plan 7); `fts_hits_json(root, terms, max) -> list[dict]` returns Python objects (serialization at `contracts.dumps` later); `fts_query_from_terms(list) -> str`.

## Notes for later plans (not part of this plan)
- **Plan 7 — `build_recall_index`** (Bash 2547-2621): opens one connection, calls `init_recall_db`, then populates via `insert_fts_row` from MEMORY.md/USER.md (first 180 lines), current LEARNINGS.jsonl / USER.jsonl rows, FACTS.jsonl rows, and run-artifact `.md` files found under `.kimiflow` (excluding the project dir). The learning/user/fact titles use a ` · ` (middle dot) joiner — must be a byte-stable `·` escape. `return 2` when FTS5 unavailable.
- **Plan 8+ wiring:** `cmd_recall`/`status`/`recall_hits_for_economics_json` consume `fts_hits_json`; the harness compares its `contracts.dumps` output (compact JSON, matching `sqlite3 -json`) and must normalize `recall_meta.updated_at`.
