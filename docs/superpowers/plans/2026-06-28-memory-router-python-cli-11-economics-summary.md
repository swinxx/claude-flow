# memory-router Python CLI - Plan 11: `economics_summary_json`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `economics_summary_json` (Bash 243-364, ~122 lines) - the `MEMORY-ECONOMICS.jsonl` aggregator. It normalizes each run row (recompute `estimated_avoided_scan_tokens = used_hit_count * avoided_per_hit` and `net = avoided - always_on - user_memory - recall_tokens`), classifies a per-row `result` (saving/waste/neutral/unknown), then aggregates totals/averages plus a `confidence`/`verdict`/`action_required`/`note` assessment. Consumed later by `status_json`.

**Architecture:** Extend `hooks/memory_router/summaries.py` (Plans 9-10) with `economics_summary_json` + helpers: `_n` (jq `tonumber? // 0`), `_field_n` (`(.k // 0) | n`), `_avoided_per_hit` (env-var parse), `_economics_absent` (absent literal). Reuses `store.read_jsonl`, `_jq_or`, `_max_present`, and `math.floor`. Returns a Python **dict** (serialized at the `contracts.dumps` boundary later). No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `math`); no new deps.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** changes exactly: `summaries.py` (extend), `tests/test_summaries.py` (extend), one §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash `economics_summary_json` (243-364) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (key order + values) against the real extracted Bash function across 9 fixtures + 6 env-override values - see Self-Review.
- **`avoided_per_hit`:** `${KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT:-1200}` then `case ''|*[!0-9]* -> 1200`. Port: honor the env var only when non-empty and all ASCII digits (so `"0"` is valid; `"-5"`/`"1.5"`/`"abc"`/unset/`""` -> 1200).
- **`_n` = jq `tonumber? // 0`:** numbers pass through (int vs float preserved, e.g. `5.0` stays `5.0`); numeric strings parse (whitespace-tolerant); bool / null / non-numeric string / container -> 0. The `(.field // 0) | n` chain means missing/null/false -> 0 first.
- **Per-row normalization** (Bash `normalized_row`): `avoided = used * avoided_per_hit`; `net = avoided - always - user - recall_tokens`; `result`: `hits == 0 -> "unknown"`, `used > 0 and net > 0 -> "saving"`, `net < 0 -> "waste"`, else `"neutral"`. Aggregated sums (`totals`) are the sums of these recomputed per-row values.
- **Assessment thresholds (exact):** `confidence`: `0 -> none`, `<8 -> low`, `<20 -> medium`, else `high`. `verdict`: `0 -> no_data`, `<8 -> insufficient_data`, `net>0 and saving>=waste -> saving_likely`, `waste>saving or net<0 -> waste_risk`, else `neutral`. `action_required`: `n>=8 and (waste>saving or net<0)`. `note`: 4 fixed strings keyed on the same branches.
- **`normalized_legacy_rows`:** count rows where the row's stored `estimated_avoided_scan_tokens` or `net_estimated_tokens_saved` (each via `_field_n`) differs from the recomputed value (numeric equality, so `6000 == 6000.0`).
- **`estimated_savings_percent`:** `floor(net*100/avoided)` when `avoided > 0`, else `null`. `averages`: `floor(net/n)`, `floor(hits/n)`, `floor(used/n)` when `n>0` else `0`. `math.floor` matches jq `floor` (toward -inf; negatives included).
- **Ordering:** `by_result` is jq `reduce` -> first-appearance order. Output, `totals`, and `averages` key order match the Bash object literals exactly.
- **Missing vs empty:** missing file -> the absent shape (`present:false`, note "No run-level memory economics recorded yet."). An existing **empty** file goes through the row path: `present:true`, `runs_tracked:0`, `verdict:no_data`, `confidence:none`, but `note` = the "Too few runs..." text.
- **Divergence (spec §12, unreachable):** a scientific-notation **string** field (e.g. `"1e3"`) renders as Python `"1000.0"` vs jq `"1E+3"`. Economics fields are JSON numbers, so this is unreachable; `_n` matches jq for all real inputs (ints, floats, int/float strings).
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/summaries.py` | add `_ECONOMICS_PATH`/`_DEFAULT_AVOIDED_PER_HIT`, `import math`, `_n`, `_field_n`, `_avoided_per_hit`, `_economics_absent`, `economics_summary_json`. |
| `hooks/memory_router/tests/test_summaries.py` | add `EconomicsSummaryCase` (+ `from unittest import mock`). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (sci-notation string). |

---

### Task 1: `economics_summary_json`

**Files:** Edit `summaries.py`, `tests/test_summaries.py`; Edit spec §12.

**Interfaces:** Produces `summaries.economics_summary_json(path) -> dict`. Consumes `store.read_jsonl`, `_jq_or`, `_max_present`, `math.floor`.

- [ ] **Step 1: Add the tests** - add `from unittest import mock` to the imports, then append `EconomicsSummaryCase`:

```python
class EconomicsSummaryCase(_FixtureCase):
    PATH = ".kimiflow/project/MEMORY-ECONOMICS.jsonl"
    # Deterministic mixed fixture (default avoided_per_hit = 1200):
    #  A: avoided=3600 net=3250 -> saving | B: avoided=1200 net=-3800 -> waste
    #  C: all-zero hits=0 -> unknown      | D: avoided=1200 net=0 -> neutral
    MIXED = [
        '{"always_on_tokens":100,"user_memory_tokens":50,"recall_tokens":200,'
        '"recall_hit_count":5,"used_hit_count":3,"recorded_at":"2026-06-10T00:00:00Z"}',
        '{"always_on_tokens":5000,"recall_hit_count":2,"used_hit_count":1}',
        '{"recall_hit_count":0,"used_hit_count":0}',
        '{"always_on_tokens":1200,"recall_hit_count":3,"used_hit_count":1}',
    ]

    def econ(self, name, lines):
        return summaries.economics_summary_json(self.write(name, lines))

    def test_missing_file_absent_shape(self):
        r = summaries.economics_summary_json(self.missing("none.jsonl"))
        self.assertFalse(r["present"])
        self.assertEqual(r["verdict"], "no_data")
        self.assertEqual(r["note"], "No run-level memory economics recorded yet.")
        self.assertEqual(list(r.keys()), [
            "present", "path", "runs_tracked", "confidence", "verdict", "action_required",
            "normalized_legacy_rows", "by_result", "totals", "estimated_savings_percent",
            "averages", "last_recorded_at", "note",
        ])
        self.assertEqual(list(r["totals"].keys()), [
            "always_on_tokens", "user_memory_tokens", "recall_tokens", "recall_hit_count",
            "used_hit_count", "estimated_avoided_scan_tokens", "net_estimated_tokens_saved",
        ])
        self.assertEqual(list(r["averages"].keys()), [
            "net_estimated_tokens_saved_per_run", "recall_hit_count_per_run",
            "used_hit_count_per_run",
        ])

    def test_empty_file_present_but_zero_runs(self):
        # Existing-but-empty file goes through the row path (present:true, n=0), and its
        # note is the "too few runs" text -- NOT the missing-file note.
        r = self.econ("e.jsonl", [])
        self.assertTrue(r["present"])
        self.assertEqual(r["runs_tracked"], 0)
        self.assertEqual(r["verdict"], "no_data")
        self.assertEqual(r["confidence"], "none")
        self.assertEqual(r["estimated_savings_percent"], None)
        self.assertTrue(r["note"].startswith("Too few runs"))

    def test_mixed_classification_and_aggregates(self):
        r = self.econ("m.jsonl", self.MIXED)
        self.assertEqual(r["runs_tracked"], 4)
        self.assertEqual(r["confidence"], "low")
        self.assertEqual(r["verdict"], "insufficient_data")
        self.assertFalse(r["action_required"])
        self.assertEqual(list(r["by_result"].keys()), ["saving", "waste", "unknown", "neutral"])
        self.assertEqual(r["by_result"], {"saving": 1, "waste": 1, "unknown": 1, "neutral": 1})
        self.assertEqual(r["totals"], {
            "always_on_tokens": 6300, "user_memory_tokens": 50, "recall_tokens": 200,
            "recall_hit_count": 10, "used_hit_count": 5,
            "estimated_avoided_scan_tokens": 6000, "net_estimated_tokens_saved": -550,
        })
        self.assertEqual(r["estimated_savings_percent"], -10)   # floor(-550*100/6000)
        self.assertEqual(r["averages"], {
            "net_estimated_tokens_saved_per_run": -138,   # floor(-550/4)
            "recall_hit_count_per_run": 2,                # floor(10/4)
            "used_hit_count_per_run": 1,                  # floor(5/4)
        })
        self.assertEqual(r["normalized_legacy_rows"], 3)   # A,B,D recomputed; C unchanged
        self.assertEqual(r["last_recorded_at"], "2026-06-10T00:00:00Z")

    def test_legacy_rows_counted(self):
        r = self.econ("l.jsonl", [
            '{"always_on_tokens":10,"used_hit_count":2,"recall_hit_count":2,'
            '"estimated_avoided_scan_tokens":99999,"net_estimated_tokens_saved":-7}',
        ])
        self.assertEqual(r["normalized_legacy_rows"], 1)

    def test_string_and_float_fields_normalized(self):
        r = self.econ("s.jsonl", [
            '{"always_on_tokens":"100","used_hit_count":"2","recall_hit_count":3,"recall_tokens":1.5}',
        ])
        # avoided=2*1200=2400; net=2400-100-1.5=2298.5
        self.assertEqual(r["totals"]["always_on_tokens"], 100)
        self.assertEqual(r["totals"]["estimated_avoided_scan_tokens"], 2400)
        self.assertEqual(r["totals"]["net_estimated_tokens_saved"], 2298.5)

    def test_malformed_lines_skipped(self):
        r = self.econ("b.jsonl", ['{"recall_hit_count":1,"used_hit_count":1}', 'GARBAGE'])
        self.assertEqual(r["runs_tracked"], 1)

    def test_confidence_high_at_20_runs(self):
        r = self.econ("h.jsonl", ['{"used_hit_count":5,"recall_hit_count":5,"always_on_tokens":10}'] * 20)
        self.assertEqual(r["confidence"], "high")
        self.assertEqual(r["verdict"], "saving_likely")

    def test_waste_risk_action_required(self):
        r = self.econ("w.jsonl", ['{"used_hit_count":1,"recall_hit_count":2,"always_on_tokens":99999}'] * 10)
        self.assertEqual(r["verdict"], "waste_risk")
        self.assertTrue(r["action_required"])

    def test_env_override_changes_avoided(self):
        with mock.patch.dict(os.environ, {"KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT": "600"}):
            r = self.econ("o.jsonl", ['{"used_hit_count":2,"recall_hit_count":2}'])
        self.assertEqual(r["totals"]["estimated_avoided_scan_tokens"], 1200)   # 2*600

    def test_env_zero_is_honored(self):
        with mock.patch.dict(os.environ, {"KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT": "0"}):
            r = self.econ("z.jsonl", ['{"used_hit_count":5,"recall_hit_count":5}'])
        self.assertEqual(r["totals"]["estimated_avoided_scan_tokens"], 0)
        self.assertEqual(r["estimated_savings_percent"], None)   # avoided not > 0

    def test_env_invalid_falls_back_to_default(self):
        for bad in ("abc", "1.5", "-5", ""):
            with mock.patch.dict(os.environ, {"KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT": bad}):
                r = self.econ("d.jsonl", ['{"used_hit_count":1,"recall_hit_count":1}'])
            self.assertEqual(r["totals"]["estimated_avoided_scan_tokens"], 1200, bad)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: FAIL - `AttributeError: ... has no attribute 'economics_summary_json'`.

- [ ] **Step 3: Extend `summaries.py`** - update the module docstring to mention `economics_summary_json`; add `import math`; add the constants `_ECONOMICS_PATH = ".kimiflow/project/MEMORY-ECONOMICS.jsonl"` and `_DEFAULT_AVOIDED_PER_HIT = 1200` (next to the other path constants); then append at end of file:

```python
def _n(value):
    # jq `tonumber? // 0`: numbers pass through (int/float preserved); numeric strings
    # parse (whitespace-tolerant); bool / null / non-numeric string / container -> 0.
    # Scientific-notation strings (e.g. "1e3") render differently than jq (Python json
    # "1000.0" vs jq "1E+3") -- unreachable: economics fields are JSON numbers, not strings.
    if isinstance(value, bool):
        return 0
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            try:
                return float(value)
            except ValueError:
                return 0
    return 0


def _field_n(row, key):
    # Bash `(.key // 0) | n`: null/false/missing -> 0, then tonumber-normalize.
    return _n(_jq_or(row.get(key), 0))


def _avoided_per_hit():
    # Bash: ${KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT:-1200} then case ''|*[!0-9]* -> 1200.
    # Only a non-empty all-ASCII-digit value is honored (so "0" is valid; "-5"/"1.5" -> 1200).
    raw = os.environ.get("KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT")
    if raw and all(c in "0123456789" for c in raw):
        return int(raw)
    return _DEFAULT_AVOIDED_PER_HIT


def _economics_absent():
    return {
        "present": False,
        "path": _ECONOMICS_PATH,
        "runs_tracked": 0,
        "confidence": "none",
        "verdict": "no_data",
        "action_required": False,
        "normalized_legacy_rows": 0,
        "by_result": {},
        "totals": {
            "always_on_tokens": 0,
            "user_memory_tokens": 0,
            "recall_tokens": 0,
            "recall_hit_count": 0,
            "used_hit_count": 0,
            "estimated_avoided_scan_tokens": 0,
            "net_estimated_tokens_saved": 0,
        },
        "estimated_savings_percent": None,
        "averages": {
            "net_estimated_tokens_saved_per_run": 0,
            "recall_hit_count_per_run": 0,
            "used_hit_count_per_run": 0,
        },
        "last_recorded_at": None,
        "note": "No run-level memory economics recorded yet.",
    }


def economics_summary_json(path):
    # Bash economics_summary_json (243-364): normalizes each MEMORY-ECONOMICS.jsonl row
    # (recompute avoided = used * avoided_per_hit; net = avoided - always - user - recall),
    # classifies a per-row `result`, then aggregates totals/averages/verdict/confidence.
    if not os.path.isfile(path):
        return _economics_absent()

    avoided_per_hit = _avoided_per_hit()
    rows = []
    for raw in store.read_jsonl(path):
        always = _field_n(raw, "always_on_tokens")
        user = _field_n(raw, "user_memory_tokens")
        recall_tokens = _field_n(raw, "recall_tokens")
        hits = _field_n(raw, "recall_hit_count")
        used = _field_n(raw, "used_hit_count")
        avoided = used * avoided_per_hit
        net = avoided - always - user - recall_tokens
        if hits == 0:
            result = "unknown"
        elif used > 0 and net > 0:
            result = "saving"
        elif net < 0:
            result = "waste"
        else:
            result = "neutral"
        rows.append({
            "always": always, "user": user, "recall_tokens": recall_tokens,
            "hits": hits, "used": used, "avoided": avoided, "net": net, "result": result,
            "raw_avoided": _field_n(raw, "estimated_avoided_scan_tokens"),
            "raw_net": _field_n(raw, "net_estimated_tokens_saved"),
            "recorded_at": raw.get("recorded_at"),
        })

    n = len(rows)
    net = sum(r["net"] for r in rows)
    hits = sum(r["hits"] for r in rows)
    used = sum(r["used"] for r in rows)
    avoided = sum(r["avoided"] for r in rows)
    always = sum(r["always"] for r in rows)
    user = sum(r["user"] for r in rows)
    recall_tokens = sum(r["recall_tokens"] for r in rows)
    saving = sum(1 for r in rows if r["result"] == "saving")
    waste = sum(1 for r in rows if r["result"] == "waste")

    if n == 0:
        confidence = "none"
    elif n < 8:
        confidence = "low"
    elif n < 20:
        confidence = "medium"
    else:
        confidence = "high"

    if n == 0:
        verdict = "no_data"
    elif n < 8:
        verdict = "insufficient_data"
    elif net > 0 and saving >= waste:
        verdict = "saving_likely"
    elif waste > saving or net < 0:
        verdict = "waste_risk"
    else:
        verdict = "neutral"

    action_required = n >= 8 and (waste > saving or net < 0)

    normalized_legacy_rows = sum(
        1 for r in rows if r["raw_avoided"] != r["avoided"] or r["raw_net"] != r["net"]
    )

    by_result = {}
    for r in rows:
        by_result[r["result"]] = by_result.get(r["result"], 0) + 1

    if n < 8:
        note = "Too few runs for a reliable savings claim; treat this as directional telemetry."
    elif net > 0 and saving >= waste:
        note = "Run telemetry suggests memory is likely saving tokens."
    elif waste > saving or net < 0:
        note = ("Run telemetry suggests memory may cost more than it saves; "
                "review recall/always-on budget.")
    else:
        note = "Run telemetry is roughly neutral."

    return {
        "present": True,
        "path": _ECONOMICS_PATH,
        "runs_tracked": n,
        "confidence": confidence,
        "verdict": verdict,
        "action_required": action_required,
        "normalized_legacy_rows": normalized_legacy_rows,
        "by_result": by_result,
        "totals": {
            "always_on_tokens": always,
            "user_memory_tokens": user,
            "recall_tokens": recall_tokens,
            "recall_hit_count": hits,
            "used_hit_count": used,
            "estimated_avoided_scan_tokens": avoided,
            "net_estimated_tokens_saved": net,
        },
        "estimated_savings_percent": (
            math.floor(net * 100 / avoided) if avoided > 0 else None
        ),
        "averages": {
            "net_estimated_tokens_saved_per_run": math.floor(net / n) if n > 0 else 0,
            "recall_hit_count_per_run": math.floor(hits / n) if n > 0 else 0,
            "used_hit_count_per_run": math.floor(used / n) if n > 0 else 0,
        },
        "last_recorded_at": _max_present([r["recorded_at"] for r in rows]),
        "note": note,
    }
```

- [ ] **Step 4: Run the focused tests**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: PASS - 32 tests (21 prior + 11 `EconomicsSummaryCase`).

- [ ] **Step 5: Full suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (196 tests: 185 prior + 11 new).

- [ ] **Step 6: Append spec §12 row** to `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md`:

```
| `economics_summary_json` `_n` sci-notation strings | jq `tonumber` on a scientific-notation string (e.g. `"1e3"`) yields a number rendered `"1E+3"` | Python parses to `1000.0` -> json `"1000.0"` | Unreachable: `MEMORY-ECONOMICS.jsonl` fields are JSON numbers, not strings. `_n` matches jq for all real inputs (ints, floats, plain int/float strings, whitespace-padded); only exotic sci-notation/underscore strings differ. |
```

- [ ] **Step 7: Commit**

```bash
git add hooks/memory_router/summaries.py hooks/memory_router/tests/test_summaries.py docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "feat(memory_router): economics_summary_json (MEMORY-ECONOMICS.jsonl aggregator)"
```

---

## Self-Review

**1. Spec coverage:** every Bash branch maps - the env-var `avoided_per_hit` parse, `_n`/`_field_n` normalization, per-row `avoided`/`net`/`result`, the aggregate sums, `confidence`/`verdict`/`action_required`/`note` threshold ladders (sharing identical boolean conditions), `normalized_legacy_rows` (raw-vs-recomputed diff), `by_result` (first-appearance), `estimated_savings_percent` + `averages` (`floor`), `last_recorded_at` (`_max_present`), and exact key order (outer + `totals` + `averages`). Reuses `_jq_or`/`_max_present`; adds `_n`/`_field_n`/`_avoided_per_hit`.

**2. Empirical grounding (decisive):** the real Bash function was extracted and run on 9 fixtures (missing / empty / mixed-classification / legacy-normalize / string+float fields / malformed / n=8 / n=20 / waste-heavy) plus 6 `KIMIFLOW_ECONOMICS_AVOIDED_TOKENS_PER_HIT` values (`600`/`0`/`abc`/`""`/`1.5`/`-5`). Each Bash output normalized via `jq -c .` and diffed against the Python `contracts.dumps`: **all identical (9/9 + 6/6)** - confirming the floor math (incl. negative `net`), the threshold ladders, `normalized_legacy_rows`, `by_result` order, and the env parse.

**3. Placeholder scan:** complete code; no TBD; pure ASCII.

**4. Type consistency:** `economics_summary_json(path) -> dict`; helpers return numbers/dicts. Serialization at the `contracts.dumps` boundary later.

## Notes for later plans (not part of this plan)
- **`global_efficiency_summary_json`** (483-597, ~115L): the cross-run/global economics pipeline - next.
- **`learning_lifecycle_json`** (599-651) + **`learning_usefulness_json`** (653-712).
- **provider/vault subsystem**, then **`status_json`** (1399-1568) composing all summaries, then `cmd_status`, `curate`, `record`.
