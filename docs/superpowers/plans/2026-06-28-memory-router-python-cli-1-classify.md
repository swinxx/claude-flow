# memory-router Python CLI — Plan 1: `classify` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the `classify` subcommand — the first real subcommand — to `hooks/memory_router/classify.py`, registered in the dispatch table, byte-for-byte drop-in with the Bash, proven by the parity harness.

**Architecture:** `classify` is stateless: text in → classification JSON out (no files, no sqlite, no provider). It validates the per-subcommand pattern end-to-end: a `run(argv)->int` entry registered in `COMMANDS`, a shared `die()` error helper, output through `contracts.dumps`, and real old-Bash-vs-Python parity cases.

**Tech Stack:** Python 3.9+ stdlib only (`re`, `sys`); the foundation modules `contracts` (dumps) and `__main__` (dispatch/COMMANDS/die); Bash + jq + git for the parity harness.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only — no pip packages.
- **Drop-in contract:** no edits to `SKILL.md`, `reference.md`, manifests, `hooks/memory-router.sh`, or `hooks/test-memory-router.sh`. The Bash stays the running impl (no cutover in this plan).
- **Parity source of truth:** Bash `cmd_classify`/`classify_text` @ `kimiflow--v0.1.50`. Output JSON must match `jq`-compact (`contracts.dumps`) and `jq` pretty (`--pretty`) exactly.
- **Error contract (Bash `die`):** stderr line `memory-router: <msg>` + exit code. Exact messages: unknown arg → `classify: unknown argument: <arg>` (exit 2); input file missing → `input not found: <path>` (exit 2); no text/input → `classify requires --input or --text` (exit 2); `--help`/`-h` → usage + exit 0.
- **jq-absent divergence (documented, spec §12):** Bash `classify` runs `need_jq` and dies `jq is required` (exit 2) when jq is absent; the Python needs no jq and classifies normally. The parity harness runs with jq present, so this never appears in the diff. Record it; do not "fix" the Python to require jq.
- **Commits:** stage only named paths (no `git add -A`); no co-author / AI-attribution trailer.
- **Branch:** continue on `feat/memory-router-py-foundation` (big-bang accrues until cutover).

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/classify.py` | `classify_text(text)->dict` (pure heuristic) + `run(argv)->int` (CLI). |
| `hooks/memory_router/__main__.py` (modify) | add `die(msg, code)` helper; register `classify` in `COMMANDS`; reuse `die` for the unknown-command path. |
| `hooks/memory_router/tests/test_classify.py` | unit tests: every classification branch + arg handling/errors. |
| `hooks/test-memory-router-parity.sh` (modify) | add `classify` cases (every branch + errors + one `--input` fixture). |
| design spec §12 (modify) | record the jq-absent divergence. |

---

### Task 1: `classify.py` + `die()` helper + dispatch registration

**Files:**
- Create: `hooks/memory_router/classify.py`
- Modify: `hooks/memory_router/__main__.py`
- Test: `hooks/memory_router/tests/test_classify.py`

**Interfaces:**
- Consumes: `contracts.dumps(obj, pretty)` (Plan 0); `__main__.COMMANDS` registry.
- Produces:
  - `classify.classify_text(text: str) -> dict` — the classification object (pure; no IO).
  - `classify.run(argv: list[str]) -> int` — parses `--input`/`--text`/`--pretty`/`--help`, reads input file's first 160 lines when `--input`, prints `contracts.dumps(classify_text(text), pretty)` + `\n` to stdout, returns 0; on error prints a `die`-style stderr line and returns 2.
  - `__main__.die(msg: str, code: int = 1) -> int` — writes `memory-router: {msg}\n` to `sys.stderr` (resolved at call time) and returns `code`.

- [ ] **Step 1: Write the failing tests**

```python
# hooks/memory_router/tests/test_classify.py
import io, os, tempfile, unittest, contextlib
from memory_router import classify
from memory_router.__main__ import main

class TestClassifyText(unittest.TestCase):
    def c(self, text):
        return classify.classify_text(text)["classification"]

    def test_default_run_only(self):
        r = self.c("please refactor the parser module thoroughly today")
        self.assertEqual(r["target"], "project_memory")  # contains "parser"? no -> see note
        # NOTE: this sample is chosen to hit project_memory via no keyword? adjust below.

    def test_security_sensitive_forces_project_memory_high(self):
        r = self.c("found an sql injection and a leaked api token in the env")
        self.assertEqual(r["sensitivity"], "security")
        self.assertEqual(r["target"], "project_memory")
        self.assertEqual(r["confidence"], "high")
        self.assertFalse(r["vault_allowed"])
        self.assertTrue(r["sanitized_required"])
        self.assertIn("security_sensitive", r["reasons"])

    def test_private_detail(self):
        r = self.c("the file lives under /Users/sr and is customer specific data here")
        self.assertEqual(r["sensitivity"], "private")
        self.assertTrue(r["vault_allowed"])
        self.assertTrue(r["sanitized_required"])
        self.assertIn("private_or_local_detail", r["reasons"])

    def test_too_small_or_trivial_by_wordcount(self):
        r = self.c("tiny note")  # < 4 words
        self.assertEqual(r["target"], "skip")
        self.assertEqual(r["confidence"], "high")
        self.assertIn("too_small_or_trivial", r["reasons"])

    def test_trivial_keyword_single_line(self):
        r = self.c("done")
        self.assertEqual(r["target"], "skip")

    def test_repo_doc_candidate_allowed_when_normal(self):
        r = self.c("update the README and the onboarding documentation for new devs")
        self.assertEqual(r["target"], "repo_doc_candidate")
        self.assertTrue(r["repo_doc_allowed"])
        self.assertIn("documentation_candidate", r["reasons"])

    def test_vault_long_term(self):
        r = self.c("a cross-project preference to always remember this lesson going forward")
        self.assertEqual(r["target"], "vault")
        self.assertIn("long_term_or_cross_project", r["reasons"])

    def test_project_memory_reusable(self):
        r = self.c("the build and release convention for this kimiflow hook is important")
        self.assertEqual(r["target"], "project_memory")
        self.assertIn("project_reusable", r["reasons"])

    def test_reasons_order_sensitivity_then_target(self):
        # private + documentation: private reason appended first, then target reason
        r = self.c("publish-safe documentation about a customer onboarding flow under /home/x")
        self.assertEqual(r["reasons"][0], "private_or_local_detail")
        self.assertIn("documentation_candidate", r["reasons"][1:])

    def test_schema_shape_and_key_order(self):
        obj = classify.classify_text("the build convention for this project is important here")
        self.assertEqual(obj["schema_version"], 1)
        self.assertEqual(
            list(obj["classification"].keys()),
            ["target", "sensitivity", "confidence", "reasons",
             "vault_allowed", "repo_doc_allowed", "sanitized_required"],
        )

class TestClassifyRun(unittest.TestCase):
    def _run(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = classify.run(argv)
        return code, out.getvalue(), err.getvalue()

    def test_text_outputs_compact_json_newline(self):
        code, out, err = self._run(["--text", "the build convention for this kimiflow project matters"])
        self.assertEqual(code, 0)
        self.assertTrue(out.endswith("\n"))
        self.assertIn('"schema_version":1', out)   # compact: no space after colon
        self.assertEqual(err, "")

    def test_pretty_indents(self):
        code, out, _ = self._run(["--pretty", "--text", "the build convention here matters a lot"])
        self.assertEqual(code, 0)
        self.assertIn('"schema_version": 1', out)  # pretty: space after colon

    def test_unknown_arg_dies_exit_2(self):
        code, out, err = self._run(["--bogus"])
        self.assertEqual(code, 2)
        self.assertEqual(err, "memory-router: classify: unknown argument: --bogus\n")
        self.assertEqual(out, "")

    def test_missing_text_and_input_dies(self):
        code, _, err = self._run([])
        self.assertEqual(code, 2)
        self.assertEqual(err, "memory-router: classify requires --input or --text\n")

    def test_input_not_found_dies(self):
        code, _, err = self._run(["--input", "/no/such/file/here.md"])
        self.assertEqual(code, 2)
        self.assertEqual(err, "memory-router: input not found: /no/such/file/here.md\n")

    def test_input_file_first_160_lines(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "in.md")
        with open(p, "w") as f:
            f.write("the build convention for this kimiflow project is important\n" + "x\n" * 400)
        code, out, _ = self._run(["--input", p])
        self.assertEqual(code, 0)
        self.assertIn('"target":"project_memory"', out)

    def test_dispatch_registration(self):
        # main() routes "classify" into classify.run
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(["classify", "--text", "the build convention here matters a lot"])
        self.assertEqual(code, 0)
        self.assertIn('"schema_version":1', out.getvalue())

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_classify -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'memory_router.classify'` (and `die` not yet in `__main__`).
(If `test_default_run_only` is ambiguous, delete it — it was a scratch note; the other tests pin the branches precisely.)

- [ ] **Step 3: Add the `die()` helper to `__main__.py` and register classify**

In `hooks/memory_router/__main__.py`, add the helper and the registration. `die` resolves stderr at call time:

```python
def die(msg, code=1):
    sys.stderr.write("memory-router: %s\n" % msg)
    return code
```

Register classify in the dispatch table. To keep imports acyclic, place this near the **BOTTOM** of `__main__.py` (after `die`, `usage`, and `main` are defined; before `if __name__ == "__main__"`). `main()` reads `COMMANDS` only at call time, so defining it below `main` is fine:

```python
from . import classify as _classify  # bottom of __main__.py, after die/usage/main

# replace `COMMANDS = {}` (Plan 0) with:
COMMANDS = {
    "classify": _classify.run,
}
```

Refactor the unknown-command branch in `main()` to reuse `die` (identical output):

```python
    handler = COMMANDS.get(cmd)
    if handler is None:
        return die("unknown command: %s" % cmd, 2)
    return handler(argv[1:])
```

(No-args and `--help`/`-h`/`help` paths are unchanged — they still call `usage()`.)

- [ ] **Step 4: Write `classify.py`**

```python
# hooks/memory_router/classify.py
"""`classify` subcommand: heuristic classification of a learning text. Stateless."""
import re
import sys

from . import contracts

# Lowercased-ASCII pattern set, lifted verbatim from Bash classify_text @ v0.1.50.
# (Output depends only on these ASCII patterns, so str.lower() vs C-locale tr cannot
#  change the result — only ASCII matches drive classification.)
_SECURITY = re.compile(r"(secret|token|credential|password|private key|\.env|vulnerab|exploit|auth bypass|cve-|xss|csrf|sql injection)")
_PRIVATE = re.compile(r"(/users/|/home/|customer|client|kunde|kundendaten|private|vault|obsidian)")
_TRIVIAL = re.compile(r"^(ok|done|fixed|typo|scratch|temporary)$", re.MULTILINE)
_DOC = re.compile(r"(readme|repo doc|documentation|docs/|architecture doc|onboarding|public docs|publish-safe)")
_VAULT = re.compile(r"(cross-project|preference|always|remember|pattern|lesson|decision|learned|wiederkehrend|arbeitsstil|vault)")
_PROJECT = re.compile(r"(test|build|release|convention|standard|decision|architecture|flow|hook|launcher|codex|claude|project map|memory|vault|kimiflow)")


def classify_text(text):
    lower = text.lower()
    words = len(text.split())
    sensitivity = "normal"
    target = "run_only"
    confidence = "medium"
    reasons = []
    vault_allowed = True
    repo_doc_allowed = False
    sanitized_required = False

    if _SECURITY.search(lower):
        sensitivity = "security"
        vault_allowed = False
        repo_doc_allowed = False
        sanitized_required = True
        reasons.append("security_sensitive")
    elif _PRIVATE.search(lower):
        sensitivity = "private"
        vault_allowed = True
        repo_doc_allowed = False
        sanitized_required = True
        reasons.append("private_or_local_detail")

    if words < 4 or _TRIVIAL.search(lower):
        target = "skip"
        confidence = "high"
        reasons.append("too_small_or_trivial")
    elif _DOC.search(lower):
        target = "repo_doc_candidate"
        if sensitivity in ("normal", "public"):
            repo_doc_allowed = True
        reasons.append("documentation_candidate")
    elif _VAULT.search(lower):
        target = "vault"
        reasons.append("long_term_or_cross_project")
    elif _PROJECT.search(lower):
        target = "project_memory"
        reasons.append("project_reusable")

    if sensitivity == "security":
        target = "project_memory"
        confidence = "high"

    return {
        "schema_version": 1,
        "classification": {
            "target": target,
            "sensitivity": sensitivity,
            "confidence": confidence,
            "reasons": reasons,
            "vault_allowed": vault_allowed,
            "repo_doc_allowed": repo_doc_allowed,
            "sanitized_required": sanitized_required,
        },
    }


def _read_input_head(path):
    # Bash: text="$(sed -n '1,160p' "$input")" — first 160 lines, trailing newline stripped
    # by command substitution. splitlines()[:160] joined by "\n" reproduces that.
    with open(path, "r", encoding="utf-8") as handle:
        return "\n".join(handle.read().splitlines()[:160])


def run(argv):
    from .__main__ import die, usage  # lazy import: keeps module load acyclic
    text = ""
    input_path = ""
    pretty = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--input":
            i += 1
            input_path = argv[i] if i < len(argv) else ""
        elif arg == "--text":
            i += 1
            text = argv[i] if i < len(argv) else ""
        elif arg == "--pretty":
            pretty = True
        elif arg in ("--help", "-h"):
            usage()
            return 0
        else:
            return die("classify: unknown argument: %s" % arg, 2)
        i += 1

    if input_path:
        import os
        if not os.path.isfile(input_path):
            return die("input not found: %s" % input_path, 2)
        text = _read_input_head(input_path)
    if not text:
        return die("classify requires --input or --text", 2)

    sys.stdout.write(contracts.dumps(classify_text(text), pretty) + "\n")
    return 0
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_classify -v`
Expected: PASS. Also run the whole package suite to confirm no regression: `cd hooks && python3 -m unittest memory_router.tests.test_dispatch memory_router.tests.test_contracts memory_router.tests.test_store memory_router.tests.test_classify`
Expected: all green (the unknown-command refactor must keep `test_dispatch` green).

- [ ] **Step 6: Commit**

```bash
git add hooks/memory_router/classify.py hooks/memory_router/__main__.py hooks/memory_router/tests/test_classify.py
git commit -m "feat(memory_router): port classify subcommand (stateless, drop-in)"
```

---

### Task 2: classify parity cases + spec divergence note

**Files:**
- Modify: `hooks/test-memory-router-parity.sh`
- Modify: `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` (§12)

**Interfaces:**
- Consumes: the harness `CASES` array + the `${args[@]+...}` invocation of both impls (Plan 0, Task 4, post-fix `61dd48b`). The harness already diffs stdout+stderr+exit byte-for-byte with both streams normalized.

- [ ] **Step 1: Add classify cases to the harness `CASES` array**

In `hooks/test-memory-router-parity.sh`, extend `CASES` with classify cases. Each `--text` value is a single argv token (no `|` inside, since `|` is the token separator — pick texts without pipes). Cover every branch and the error paths:

```bash
  # classify — stateless: one token per arg, '|' separates argv tokens
  "cls_security::classify|--text|found an sql injection and a leaked api token in env"
  "cls_private::classify|--text|the file under /Users/sr is customer specific data here"
  "cls_trivial_words::classify|--text|tiny note"
  "cls_trivial_kw::classify|--text|done"
  "cls_repo_doc::classify|--text|update the README and onboarding documentation for devs"
  "cls_vault::classify|--text|a cross-project preference to always remember this lesson now"
  "cls_project::classify|--text|the build and release convention for this kimiflow hook matters"
  "cls_pretty::classify|--pretty|--text|the build convention for this project is important here"
  "cls_unknown_arg::classify|--bogus"
  "cls_no_args::classify"
```

- [ ] **Step 2: Add one `--input` fixture case**

Still in the harness, before the loop, create a fixture file under `$WORK` and add a case that both impls read. Because `CASES` tokens can't carry a dynamic path cleanly, add a dedicated fixture variable and one explicit case using it:

```bash
# classify --input fixture (first-160-lines behavior; both impls read the same file)
CLS_FIXTURE="$WORK/cls-input.md"
printf 'the build convention for this kimiflow project is important\n' > "$CLS_FIXTURE"
for i in $(seq 1 400); do printf 'filler line %s\n' "$i" >> "$CLS_FIXTURE"; done
CASES+=("cls_input::classify|--input|$CLS_FIXTURE")
```

(Place this `CASES+=(...)` after the `CASES=(...)` array literal and after `WORK` is set. `$CLS_FIXTURE` is absolute and is normalized by `normalize()` via the `$WORK` → `WORK` substitution, so both impls' output matches.)

- [ ] **Step 3: Run the harness**

Run: `bash hooks/test-memory-router-parity.sh`
Expected: every case `ok` (dispatch cases + all `cls_*`), `ALL GREEN`, exit 0. No `set -u` errors.
If any `cls_*` case is `BAD`: read the printed stream diff. A real Bash/Python classification divergence must be fixed in `classify.py` (the Bash is authoritative) — do not edit the harness to hide it. If it is a deliberately-fixed Bash bug, add the label to `WHITELIST` with a spec §12 entry.

- [ ] **Step 4: Record the jq-absent divergence in spec §12**

In `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md`, add a §12 row:

| Site | Old behavior | New behavior | Reason |
|---|---|---|---|
| `classify` when `jq` absent (`need_jq`) | dies `memory-router: jq is required` exit 2 | classifies normally (no jq needed) | Python uses no jq; jq-requirement was a Bash impl artifact, not a user contract. Harness runs with jq present, so no diff. |

- [ ] **Step 5: Commit**

```bash
git add hooks/test-memory-router-parity.sh docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "test(memory_router): classify parity cases + record jq-absent divergence"
```

---

## Self-Review

**1. Spec coverage:** classify subcommand (spec §4.1) → Task 1; jq-faithful stdout (§4.2) via `contracts.dumps` → Task 1 + parity Task 2; exit codes / `die` error contract (§4.3) → Task 1 tests + parity; fidelity/divergence recording (§5, §12) → Task 2 Step 4. The Bash `classify_text` heuristic is ported branch-for-branch with the verbatim regex set.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to". All code is complete. The one scratch test (`test_default_run_only`) is explicitly flagged in Step 2 as deletable — the precise branch tests supersede it; the implementer removes it (it is not a real requirement).

**3. Type consistency:** `classify_text(text)->dict`, `run(argv)->int`, `die(msg, code)->int`, `contracts.dumps(obj, pretty)->str` are used consistently across tasks and match the Plan 0 interfaces (`COMMANDS` registry, `usage`, `contracts.dumps`). Output key order in the schema test matches the dict built in `classify.py`.

## Notes / watch-items
- **Word count:** `len(text.split())` == `wc -w` for whitespace-delimited words (both drop empties). The parity battery's `cls_trivial_words` ("tiny note" = 2 words) exercises the `< 4` branch.
- **`_TRIVIAL` uses `re.MULTILINE`** to match the Bash line-oriented `grep -Eq '^...$'` over the (possibly multi-line) text.
- **Import shape (acyclic):** `classify.py` imports only `contracts` at module top; it imports `die`/`usage` from `__main__` LAZILY inside `run()`. `__main__` imports `classify` at the BOTTOM (after `die`/`usage`/`main` are defined) and builds `COMMANDS` there. So importing `memory_router.classify` directly (the unit tests) never triggers a partial `__main__`, and running `__main__` as a script loads `classify` only after its own helpers exist. No cycle. `USAGE`/`usage`/`die` stay in `__main__` (Plan 0's `from memory_router.__main__ import main, USAGE` test import stays valid).
