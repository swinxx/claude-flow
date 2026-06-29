# memory-router Python CLI - Plan 8: `index` subcommand + first stdout parity harness

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the first stateful subcommand end-to-end: `index` (Bash `cmd_index`, 3988-4030) - build / inspect the RECALL.sqlite FTS index. This proves the subcommand-dispatch path and establishes the **shared wiring scaffolding** (`resolve_root`, `json_print`) and the **first stdout-parity harness** that every later subcommand reuses.

**Why `index` and not curate/record (scope correction):** the deep-read found that `cmd_curate` depends on the full `status_json` aggregator (~170 lines, ~13 summary helpers) and `cmd_record` calls `cmd_curate` - both are blocked behind the "do near last" status work. `index` depends only on the already-ported `build_recall_index` (Plan 7), so it is the only independently-wireable subcommand and the natural vehicle to build the wiring + parity infrastructure first.

**Architecture:** New module `hooks/memory_router/index.py` (the subcommand). Two shared helpers added: `resolve_root` in `cli.py` (the `--root` resolver, used by all stateful subcommands) and `json_print` in `contracts.py` (the `jq .` / `jq -c .` stdout writer). Registered in `__main__.COMMANDS`. `need_jq` is a no-op (the port uses no jq; spec 12). First committed **stdout-parity harness** (`tests/test_index.py::IndexParityCase`), gated by `skipUnless` so minimal environments skip it.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `sqlite3`, `subprocess` for the git-toplevel in `resolve_root`); no new third-party deps.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** no edits to `hooks/memory-router.sh`, SKILL.md, reference.md, manifests, or the `recall_index`/`writes`/`memory_md`/`rows`/`classify` modules. This plan changes exactly: new `index.py`, new `tests/test_index.py`, `cli.py` (+`resolve_root`), `contracts.py` (+`json_print`), `__main__.py` (register `index`), `tests/test_contracts.py` (+`json_print` tests), `tests/test_dispatch.py` (+`resolve_root` tests), and one §12 row.
- **Source of truth:** Bash `cmd_index` @ `kimiflow--v0.1.50` (3988-4030); `resolve_root` (35-42), `json_print` (61-68), `die`/`need_jq` (26-33). Grounded byte-for-byte against the real full Bash script (not an extracted fn) - see Self-Review.
- **`cmd_index` output contract (exact key order):**
  - FTS5 available: `{schema_version:1, status, path:".kimiflow/project/RECALL.sqlite", written:(write==1), sqlite_available:true, documents:<count>}`.
  - FTS5 unavailable: `{schema_version:1, status:"unavailable", path, sqlite_available:false, documents:0}` - **no `written` key**.
  - `status`: `"indexed"` when `--write`; else `"available"` when the db file exists; else `"preview"`.
  - `documents`: `SELECT count(*) FROM recall_fts` when the db exists (else 0); any sqlite error -> 0 (Bash `|| printf '0'`).
- **`resolve_root` (Bash 35-42):** with `--root`, absolutize via `(cd "$root" && pwd)`, falling back to the literal when `cd` fails; without `--root`, `git rev-parse --show-toplevel`, falling back to bare `pwd`. Port: `os.path.abspath(root)` when `os.path.isdir(root)` else the literal; else the git subprocess, else `_logical_cwd()`. Both branches keep symlinks unresolved to match bash's logical handling: `os.path.abspath` matches `cd && pwd` for real roots (normalizes `..` lexically, keeps symlinks), and `_logical_cwd()` returns `$PWD` when it still names the cwd (mirroring bare `pwd -L`) rather than the symlink-resolving `os.getcwd()`; see §12.
- **`json_print` (Bash 61-68):** pretty -> `jq .` (2-space indent); else `jq -c .` (compact); each via `printf '%s\n'` so output carries a trailing newline. Port = `contracts.dumps(obj, pretty) + "\n"` to the stream.
- **Errors:** unknown arg -> `die("index: unknown argument: %s", 2)` (stderr `memory-router: ...`, exit 2); `--help`/`-h` -> `usage()` + exit 0. Byte-identical to Bash.
- **`need_jq` is a no-op:** Bash `cmd_index` calls `need_jq`; the port needs no jq (spec 12).
- **`cli.py` stays package-import-free:** `resolve_root` uses only stdlib (`os`, `subprocess`); `json_print` lives in `contracts.py` (the serialization module) to avoid a package import in `cli.py`.
- **Parity harness:** `tests/test_index.py::IndexParityCase` materializes the pinned Bash (`git show kimiflow--v0.1.50:hooks/memory-router.sh`) and asserts the Python `index.run` stdout equals the Bash stdout byte-for-byte across preview/indexed/available x compact/pretty x empty/populated. `index` stdout is timestamp-free, so **no normalization is needed**. `skipUnless(bash, jq, sqlite3, git, and the tag resolvable)`.
- **Nondeterminism:** none on `index` stdout. The db file's `recall_meta.updated_at` is nondeterministic but is not part of stdout; db-content parity (already covered by Plan 7) holds modulo that timestamp and the documented run-artifact order.
- **Commits:** named paths only; no co-author / AI-attribution trailer.
- **Branch:** continue on `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/index.py` | new: `index.run(argv)` + `_document_count`. |
| `hooks/memory_router/cli.py` | add `resolve_root` (+`import os, subprocess`). |
| `hooks/memory_router/contracts.py` | add `json_print` (+`import sys`). |
| `hooks/memory_router/__main__.py` | register `"index": _index.run`. |
| `hooks/memory_router/tests/test_index.py` | new: `IndexRunCase` (unit) + `IndexParityCase` (Bash parity, skip-gated). |
| `hooks/memory_router/tests/test_contracts.py` | add `TestJsonPrint`. |
| `hooks/memory_router/tests/test_dispatch.py` | add `ResolveRootCase` + `LogicalCwdCase`. |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (`resolve_root` + `need_jq`). |

---

### Task 1: shared wiring helpers (`resolve_root`, `json_print`)

**Files:** Edit `cli.py`, `contracts.py`; Test `tests/test_dispatch.py`, `tests/test_contracts.py`.

- [ ] **Step 1: `cli.py`** - widen the import and add `resolve_root` after `die`:

```python
import os
import subprocess
import sys
```

```python
def _logical_cwd():
    # Bash bare `pwd` is logical (-L): it prints $PWD when that still names the cwd
    # (symlinks preserved), else the physical path. os.getcwd() is always physical, so
    # use $PWD when it resolves to the cwd, matching the --root branch's symlink handling.
    pwd = os.environ.get("PWD")
    if pwd and os.path.isabs(pwd):
        try:
            if os.path.samefile(pwd, "."):
                return pwd
        except OSError:
            pass
    return os.getcwd()


def resolve_root(root):
    # Bash resolve_root: with --root, absolutize via `(cd "$root" && pwd)` and fall
    # back to the literal when cd fails (missing / not a dir); without --root, use
    # `git rev-parse --show-toplevel`, falling back to the logical cwd.
    if root:
        if os.path.isdir(root):
            return os.path.abspath(root)
        return root
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        top = proc.stdout.decode("utf-8", "replace").strip()
        if proc.returncode == 0 and top:
            return top
    except OSError:
        pass
    return _logical_cwd()
```

- [ ] **Step 2: `contracts.py`** - add `import sys` and `json_print`:

```python
def json_print(obj, pretty=False, stream=None):
    # Bash json_print: `jq .` (pretty) or `jq -c .` (compact), each via `printf '%s\n'`
    # so the output carries a trailing newline.
    if stream is None:
        stream = sys.stdout
    stream.write(dumps(obj, pretty) + "\n")
```

- [ ] **Step 3: tests** - add `ResolveRootCase` + `LogicalCwdCase` to `tests/test_dispatch.py` (imports: `os, shutil, tempfile, mock, cli`) and `TestJsonPrint` to `tests/test_contracts.py` (import `io`):

```python
# tests/test_dispatch.py  (append before __main__)
class ResolveRootCase(unittest.TestCase):
    def test_existing_dir_absolutized(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        self.assertEqual(cli.resolve_root(d), os.path.abspath(d))

    def test_missing_root_returns_literal(self):
        self.assertEqual(cli.resolve_root("/no/such/dir/xyz"), "/no/such/dir/xyz")

    def test_no_root_uses_git_toplevel(self):
        proc = mock.Mock(returncode=0, stdout=b"/repo/top\n")
        with mock.patch("memory_router.cli.subprocess.run", return_value=proc):
            self.assertEqual(cli.resolve_root(""), "/repo/top")

    def test_no_root_falls_back_to_logical_cwd_when_git_fails(self):
        proc = mock.Mock(returncode=128, stdout=b"")
        with mock.patch("memory_router.cli.subprocess.run", return_value=proc):
            self.assertEqual(cli.resolve_root(""), cli._logical_cwd())

    def test_no_root_falls_back_to_logical_cwd_when_git_absent(self):
        with mock.patch("memory_router.cli.subprocess.run", side_effect=OSError("no git")):
            self.assertEqual(cli.resolve_root(""), cli._logical_cwd())


class LogicalCwdCase(unittest.TestCase):
    def test_uses_pwd_when_it_names_the_cwd_via_symlink(self):
        # Bash bare `pwd` (-L) keeps the symlinked path; _logical_cwd must too.
        base = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, base, ignore_errors=True)
        real = os.path.join(base, "real")
        link = os.path.join(base, "link")
        os.mkdir(real)
        os.symlink(real, link)
        cwd = os.getcwd()
        try:
            os.chdir(link)
            with mock.patch.dict(os.environ, {"PWD": link}):
                self.assertEqual(cli._logical_cwd(), link)           # symlink preserved
                self.assertNotEqual(cli._logical_cwd(), os.getcwd())  # not the physical path
        finally:
            os.chdir(cwd)

    def test_ignores_stale_pwd(self):
        with mock.patch.dict(os.environ, {"PWD": "/definitely/not/the/cwd"}):
            self.assertEqual(cli._logical_cwd(), os.getcwd())

    def test_falls_back_to_physical_when_pwd_unset(self):
        env = {k: v for k, v in os.environ.items() if k != "PWD"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(cli._logical_cwd(), os.getcwd())
```

```python
# tests/test_contracts.py  (append before __main__; add `io` to the import line)
class TestJsonPrint(unittest.TestCase):
    def out(self, obj, pretty=False):
        stream = io.StringIO()
        contracts.json_print(obj, pretty, stream)
        return stream.getvalue()

    def test_compact_has_trailing_newline(self):
        self.assertEqual(self.out({"a": 1}), '{"a":1}\n')

    def test_pretty_has_trailing_newline_and_indent(self):
        self.assertEqual(self.out({"a": 1}, pretty=True), '{\n  "a": 1\n}\n')
```

---

### Task 2: `index` subcommand + dispatch + parity harness

**Files:** Create `index.py`, `tests/test_index.py`; Edit `__main__.py`; Edit spec §12.

- [ ] **Step 1: Write the failing tests** - create `tests/test_index.py` (full file):

```python
# hooks/memory_router/tests/test_index.py
import contextlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from memory_router import index, recall_index
from memory_router.__main__ import main

TAG = "kimiflow--v0.1.50"


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def _capture(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = index.run(argv)
    return code, out.getvalue(), err.getvalue()


class IndexRunCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def out(self, argv):
        code, out, err = _capture(["--root", self.root] + argv)
        self.assertEqual(err, "")
        self.assertEqual(code, 0)
        return out

    def test_preview_when_no_db_no_write(self):
        out = self.out([])
        self.assertEqual(json.loads(out), {
            "schema_version": 1, "status": "preview",
            "path": ".kimiflow/project/RECALL.sqlite",
            "written": False, "sqlite_available": True, "documents": 0,
        })

    def test_compact_key_order(self):
        # compact JSON must preserve the Bash key order exactly.
        out = self.out([])
        self.assertEqual(
            out.rstrip("\n"),
            '{"schema_version":1,"status":"preview","path":".kimiflow/project/RECALL.sqlite",'
            '"written":false,"sqlite_available":true,"documents":0}',
        )

    def test_indexed_on_write(self):
        obj = json.loads(self.out(["--write"]))
        self.assertEqual(obj["status"], "indexed")
        self.assertTrue(obj["written"])
        self.assertTrue(os.path.isfile(recall_index.recall_db_path(self.root)))

    def test_available_when_db_exists_no_write(self):
        self.out(["--write"])
        obj = json.loads(self.out([]))
        self.assertEqual(obj["status"], "available")
        self.assertFalse(obj["written"])

    def test_documents_counts_rows(self):
        os.makedirs(os.path.join(self.root, ".kimiflow", "project"))
        with open(os.path.join(self.root, ".kimiflow", "project", "MEMORY.md"), "w") as fh:
            fh.write("hello\n")
        obj = json.loads(self.out(["--write"]))
        self.assertEqual(obj["documents"], 1)

    def test_pretty_indents(self):
        out = self.out(["--pretty"])
        self.assertIn('"schema_version": 1', out)  # space after colon

    def test_unavailable_branch_omits_written(self):
        with mock.patch("memory_router.recall_index.fts5_available", return_value=False):
            code, out, err = _capture(["--root", self.root])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {
            "schema_version": 1, "status": "unavailable",
            "path": ".kimiflow/project/RECALL.sqlite",
            "sqlite_available": False, "documents": 0,
        })
        self.assertNotIn("written", out)

    def test_unknown_arg_dies_exit_2(self):
        code, out, err = _capture(["--bogus"])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertEqual(err, "memory-router: index: unknown argument: --bogus\n")

    def test_help_exit_0(self):
        code, out, err = _capture(["--help"])
        self.assertEqual(code, 0)
        self.assertEqual(out, "")
        self.assertTrue(err.startswith("#!/usr/bin/env bash"))

    def test_dispatch_registration(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(["index", "--root", self.root])
        self.assertEqual(code, 0)
        self.assertIn('"status":"preview"', out.getvalue())


def _tools_present():
    if not all(shutil.which(t) for t in ("bash", "jq", "sqlite3", "git")):
        return False
    probe = subprocess.run(
        ["git", "-C", _repo_root(), "cat-file", "-e", TAG + ":hooks/memory-router.sh"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return probe.returncode == 0


@unittest.skipUnless(_tools_present(), "bash/jq/sqlite3/git or pinned tag unavailable")
class IndexParityCase(unittest.TestCase):
    """Grounds the Python `index` stdout byte-for-byte against the real Bash at the
    pinned tag. This is the first stdout-parity harness; `index` stdout is timestamp
    free, so no normalization is needed."""

    @classmethod
    def setUpClass(cls):
        src = subprocess.run(
            ["git", "-C", _repo_root(), "show", TAG + ":hooks/memory-router.sh"],
            stdout=subprocess.PIPE, check=True,
        ).stdout
        fd, cls.script = tempfile.mkstemp(suffix=".sh")
        with os.fdopen(fd, "wb") as fh:
            fh.write(src)

    @classmethod
    def tearDownClass(cls):
        os.unlink(cls.script)

    def _bash(self, root, argv):
        return subprocess.run(
            ["bash", self.script, "index", "--root", root] + argv,
            stdout=subprocess.PIPE, text=True, check=True,
        ).stdout

    def _py(self, root, argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(index.run(["--root", root] + argv), 0)
        return out.getvalue()

    def assert_parity(self, argv, populate=False):
        rb, rp = tempfile.mkdtemp(), tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, rb, ignore_errors=True)
        self.addCleanup(shutil.rmtree, rp, ignore_errors=True)
        if populate:
            for root in (rb, rp):
                proj = os.path.join(root, ".kimiflow", "project")
                os.makedirs(proj)
                with open(os.path.join(proj, "MEMORY.md"), "w") as fh:
                    fh.write("line one\nline two\n")
        self.assertEqual(self._bash(rb, argv), self._py(rp, argv), "argv=%r" % argv)

    def test_preview(self):
        self.assert_parity([])

    def test_preview_pretty(self):
        self.assert_parity(["--pretty"])

    def test_indexed(self):
        self.assert_parity(["--write"])

    def test_indexed_pretty(self):
        self.assert_parity(["--write", "--pretty"])

    def test_indexed_populated(self):
        self.assert_parity(["--write"], populate=True)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_index -v`
Expected: FAIL - `ModuleNotFoundError: No module named 'memory_router.index'`.

- [ ] **Step 3: Write `index.py`** (full file):

```python
# hooks/memory_router/index.py
"""`index` subcommand: build / inspect the RECALL.sqlite FTS index. Behavioral port
of the Bash cmd_index @ kimiflow--v0.1.50 (3988-4030). need_jq is a no-op (the port
uses no jq, spec 12)."""
import os
import sqlite3

from . import contracts, recall_index
from .cli import die, resolve_root, usage

_PATH = ".kimiflow/project/RECALL.sqlite"


def _document_count(db):
    # Bash: sqlite3 "$db" 'SELECT count(*) FROM recall_fts;' 2>/dev/null || printf '0'
    try:
        con = sqlite3.connect(db)
    except sqlite3.Error:
        return 0
    try:
        return con.execute("SELECT count(*) FROM recall_fts").fetchone()[0]
    except sqlite3.Error:
        return 0
    finally:
        con.close()


def run(argv):
    root = ""
    pretty = False
    write = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--root":
            i += 1
            root = argv[i] if i < len(argv) else ""
        elif arg == "--write":
            write = True
        elif arg == "--pretty":
            pretty = True
        elif arg in ("--help", "-h"):
            usage()
            return 0
        else:
            return die("index: unknown argument: %s" % arg, 2)
        i += 1

    root = resolve_root(root)
    db = recall_index.recall_db_path(root)

    # Bash gates on sqlite_available (CLI); the port probes the stdlib module's FTS5.
    if not recall_index.fts5_available():
        contracts.json_print({
            "schema_version": 1,
            "status": "unavailable",
            "path": _PATH,
            "sqlite_available": False,
            "documents": 0,
        }, pretty)
        return 0

    status = "preview"
    if write:
        recall_index.build_recall_index(root, db)
        status = "indexed"
    elif os.path.isfile(db):
        status = "available"

    documents = _document_count(db) if os.path.isfile(db) else 0

    contracts.json_print({
        "schema_version": 1,
        "status": status,
        "path": _PATH,
        "written": write,
        "sqlite_available": True,
        "documents": documents,
    }, pretty)
    return 0
```

- [ ] **Step 4: Register in `__main__.py`**:

```python
from . import classify as _classify
from . import index as _index

COMMANDS = {
    "classify": _classify.run,
    "index": _index.run,
}
```

- [ ] **Step 5: Run the focused tests**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest memory_router.tests.test_index -v`
Expected: PASS - 15 tests (10 `IndexRunCase` + 5 `IndexParityCase`). The parity cases **run** (do not skip) when bash/jq/sqlite3/git + the tag are present.

- [ ] **Step 6: Full suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (164 tests: 139 prior + 15 index + 2 json_print + 8 resolve_root/logical_cwd - the parity 5 run in-repo, skip elsewhere).

- [ ] **Step 7: Append spec §12 row** to `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md`:

```
| `resolve_root` + `need_jq` (cmd_index wiring) | `(cd "$root" && pwd)` (shells out; logical pwd) with git `rev-parse --show-toplevel`/`pwd` fallback; `need_jq` dies if jq absent | `os.path.abspath(root)` when `os.path.isdir(root)` else literal, with a `git rev-parse` subprocess / logical-cwd (`$PWD`-validated) fallback; `need_jq` is a no-op | Both branches keep symlinks unresolved to match bash's *logical* path handling: `os.path.abspath` matches `cd && pwd` for real roots (normalizes `..` lexically, keeps symlinks), and the no-`--root` fallback uses `$PWD` when it still names the cwd (mirroring bare `pwd -L`) instead of the symlink-resolving `os.getcwd()`. The only edge is a `--root` that exists-but-`cd`-fails (e.g. no-exec permission), unobservable for normal roots. The port needs no jq (engine uses the stdlib sqlite3 module), so `need_jq` is dropped for every ported subcommand (generalizes the classify-jq row). |
```

- [ ] **Step 8: Commit**

```bash
git add hooks/memory_router/index.py hooks/memory_router/cli.py hooks/memory_router/contracts.py hooks/memory_router/__main__.py hooks/memory_router/tests/test_index.py hooks/memory_router/tests/test_contracts.py hooks/memory_router/tests/test_dispatch.py docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "feat(memory_router): wire index subcommand + first stdout parity harness"
```

---

## Self-Review

**1. Spec coverage:** `cmd_index` maps verbatim - arg parse (`--root/--write/--pretty/--help`), the FTS5 gate (unavailable branch with no `written` key), the `indexed`/`available`/`preview` status ladder, `documents` via `count(*)` with error->0, and the exact output key order in both branches. `resolve_root`/`json_print`/`need_jq`/`die`/`usage` are the shared wiring. No other module touched.

**2. Empirical grounding (decisive):** the Python `index.run` stdout was diffed **byte-for-byte against the real full Bash script** (`bash memory-router.sh index ...`, not an extracted fn) across 7 scenarios: preview / indexed / available x compact/pretty x empty/populated (documents=14 on the Plan-7 fixture). All identical. Error path (`--bogus` -> exit 2, identical stderr) and `--help` (exit 0, identical usage) also match. db-file content is identical modulo the documented run-artifact order + `updated_at` (Plan 7). This grounding is institutionalized as `IndexParityCase` (skip-gated), which **runs green in-repo**. An independent review then flagged one marginal divergence: the no-`--root` fallback used `os.getcwd()` (symlink-resolving) where bash bare `pwd` is logical - fixed by `_logical_cwd()` (`$PWD`-validated), making both `resolve_root` branches consistently symlink-preserving; verified against bash `pwd` on a symlinked cwd.

**3. Placeholder scan:** complete code in every step; no TBD; added code is pure ASCII (the only non-ASCII in touched files are the pre-existing verbatim Bash `-` em-dash in the `USAGE` header and the `u`-umlaut UTF-8 fixture in `test_contracts.py`, neither introduced here).

**4. Type consistency:** `index.run(argv: list[str]) -> int`; `resolve_root(str) -> str`; `contracts.json_print(obj, pretty=False, stream=None) -> None`. `cli.py` stays package-import-free (`json_print` lives with serialization in `contracts.py`).

## Notes for later plans (not part of this plan)
- **Summary helpers** (`read_jsonl_summary`, `usage_summary_json`, `economics_summary_json`, `learning_lifecycle_json`, `learning_usefulness_json`, `global_efficiency_summary_json`, `proposal_summary_json`): pure data aggregators, unit-testable; the next chunk.
- **`status_json`** (Bash 1399-1568) composes the summaries + `provider_status_json`/`vault_status_json`; then `cmd_status` wiring.
- **`curate`** (needs `status_json` + the topics builder + the inline `MEMORY-INDEX.json` writer at Bash 4109) then **`record`** (needs `curate` + `append_learning_row` + `write_bounded_memory`). Both reuse `resolve_root`/`json_print`/the parity harness from this plan.
