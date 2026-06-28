# Handoff — memory-router Bash→Python port (and 0.1.50 release)

**Date:** 2026-06-28 · **Repo:** kimiflow · **Author of work:** this session

---

## TL;DR

- Shipped **release 0.1.50** (ShellCheck fixes) — done, pushed, GitHub release live.
- Started the **`hooks/memory-router.sh` → stdlib-Python port** (the review's #1 recommendation). Foundation + `classify` subcommand + shared primitives are built, tested, and green on a feature branch. The Bash original is **untouched** (no cutover yet).
- This is a **multi-session effort**. Clean pause point reached before the hard sqlite/FTS + write-path core.
- Resume by saying **"weiter mit Plan 3"**.

---

## Git state (verified 2026-06-28)

| Ref | Commit | Meaning |
|---|---|---|
| `origin/main` | `a9bf10d` | Release 0.1.50 (pushed) |
| local `main` | `6e41728` | **2 unpushed commits** ahead of origin: `d89c0e3` (design spec) + `6e41728` (Plan 0 doc) |
| `feat/memory-router-py-foundation` | `1fbc8b7` | **17 commits** ahead of local main: Plan 1 doc, Plan 2 doc, and all port code (Plan 0/1/2 impl) |
| tag | `kimiflow--v0.1.50` | the parity baseline + the release |

**Nothing on the feature branch is merged or pushed.** Working tree is clean.

Note the split: the design **spec** and **Plan 0 doc** live on local `main` (unpushed); **Plan 1 + Plan 2 docs** and **all code** live on the feature branch. Merging the branch into main brings the code + plans 1/2; main already carries the spec + plan 0.

---

## What this session did

1. **Evaluated an external review** of kimiflow against the real code: confirmed SC2318 (exactly 9×, in the 3 named files), the dead `case` patterns (SC2221/2222), `pretty`/`handoff` SC2034; found the review **misattributed SC1102** (it's in two *test* files, not `project-map-status.sh`) and slightly misplaced `handoff`. Judged the architectural conflict-of-interest claim (orchestrator promotes candidate→confirmed; SKILL.md:182 / README:137) as **well-founded**, noting the recorded-rejection audit trail as a partial mitigation the review missed.
2. **Fixed all 9 ShellCheck items** (SC2318 latent path-derivation bug confirmed via `bash -c 'local a=x b=$a'` → empty), committed `4029111`, then ran **`/release` → 0.1.50** (`a9bf10d`, tag pushed, GitHub release).
3. **Workflow-backed code review** of the fix commit (xhigh) — 4 candidates, all refuted, **0 confirmed**.
4. **Brainstormed → spec → planned → built** the Python port (see below).

---

## The port — decisions (locked with the user)

- **Strategy:** big-bang rewrite, single cutover at the end. De-risked by a parity harness + the existing test suite; the Bash stays the running impl until the cutover.
- **Fidelity:** drop-in (same subcommands/stdout/files/exit codes — no edits to SKILL.md/reference.md/manifests/`test-memory-router.sh`), **but fix latent bugs**; record every intentional divergence in spec §12 + a code comment + a harness whitelist.
- **Dependencies:** **stdlib-only** (no pip). Python **≥ 3.9** (macOS system python3 is 3.9.6). `jq` stays a project dep (other hooks need it) — the port adds python3, doesn't remove jq.
- **Architecture:** subsystem-modular package `hooks/memory_router/`; `hooks/memory-router.sh` becomes a thin shim.
- **Parity baseline:** the Bash at tag `kimiflow--v0.1.50` (`git show kimiflow--v0.1.50:hooks/memory-router.sh`).

Spec: `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` (§12 = known divergences).

---

## The port — what's DONE (all green)

Package `hooks/memory_router/`: `__init__`, `__main__`, `cli`, `contracts`, `store`, `paths`, `text`, `clock`, `classify`.

- **Plan 0 — Foundation** (`docs/.../plans/2026-06-28-...-foundation.md`): dispatch layer (usage/help/unknown → byte-exact 17-line header + exit codes), `contracts.dumps` (jq-faithful compact/pretty, tested vs real `jq`), `store` (atomic write + symlink guard + lenient readers), and the **parity harness** `hooks/test-memory-router-parity.sh`.
- **Plan 1 — `classify`** (`...-1-classify.md`): first real subcommand, stateless, drop-in; 17 parity cases; `cli.py` extracted (USAGE/usage/die) to keep imports acyclic and avoid `__main__` double-exec.
- **Plan 2 — primitives** (`...-2-primitives.md`): `paths` (rel_path / rows_path_for_scope / id_prefix_for_scope), `text` (slugify / sql_quote / word_count_file), `clock` (iso_now / date_now).

**Verification (re-run to confirm green):**
```bash
cd "<repo>" && export PATH="/opt/homebrew/bin:$PATH"   # jq for contracts test
( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )   # 45 tests, OK
bash hooks/test-memory-router-parity.sh                                              # ALL GREEN
( cd /tmp && bash "<repo>/hooks/test-memory-router-parity.sh" )                      # ALL GREEN (location-independent)
git diff --stat main HEAD -- hooks/memory-router.sh                                  # empty = Bash untouched
```

---

## The port — what's NEXT (the hard, entangled core)

Deep-reading revealed the dependency graph is **far more entangled** than the 13-subcommand list suggests: `classify` was a true leaf, but `record`/`status`/`curate`/`recall` all share a write+index+sqlite core. So the order is **layer-first**, smallest piece each time:

1. **Plan 3 — row validation:** `memory_security_json` (regex gate like classify), `sanitize_evidence_json` (rewrite outside-repo paths → `OUTSIDE_REPO`), `evidence_fingerprints_json` (content hashes). Leaf-ish, mostly deterministic. *Start here.*
2. **Plan 4 — `append_learning_row` write path** (Bash 2405-2512): dedup (return existing id) + supersession (mark old `current` rows superseded). **Nondeterminism**: `id` uses `$$`+`date`, `last_verified`=`date_now`, `source_commit`=git HEAD — the parity harness must **normalize** these (like it already normalizes paths).
3. **Plan 5 — `MEMORY-INDEX.json` builder + `write_bounded_memory`/`write_bounded_user_memory`** (Bash 2789-2885).
4. **Plan 6 — `RECALL.sqlite` / FTS5** (Bash ~2528-2650): schema `recall_meta` + `recall_fts USING fts5(...)`, `insert_fts_row`, `fts_query_from_terms`, `fts_hits_json`, graceful degradation when sqlite/fts5 absent. **This is the #1 risk flagged in Plan 0** — hardest parity (sqlite3 stdlib module, exact schema/queries).
5. **Plan 7 — `curate`** composition · **Plan 8 — thin `record`/`index`/`curate` subcommand wiring** on top.
6. Then the remaining subcommands: `recall`, `history`, `metrics`, `status` (aggregator over ~11 summary helpers — do near last), `review-run`, `verify-run`, `consolidate`, `propose`, `provider`.
7. **Cutover** (final plan): replace `hooks/memory-router.sh` body with the shim, delete the Bash, full suite + smokes green, update README/COMPATIBILITY (Python ≥3.9), CHANGELOG, `/release`.

**Progress: 3 of ~8 layer/subcommand building blocks done (foundation + classify + primitives).**

---

## Carry-forward findings (in the ledger + spec §12)

- **Shim launch is non-trivial** (relative imports): the cutover shim must be `exec env PYTHONPATH="$dir" python3 -m memory_router "$@"` (`$dir` = the `hooks/` dir). The naive `python3 "$dir/memory_router"` is **broken**. Already corrected in spec §6 + the harness.
- **`contracts.dumps` float parity:** `json.dumps(1.0)` → `"1.0"` but `jq` emits `1`. No float path exists yet; must add coverage **before the first numeric-stdout subcommand** (metrics/economics). Tracked in spec §12.
- **`classify` jq-absent divergence** (spec §12): Bash `need_jq` dies; Python needs no jq → classifies. Harness has jq, so no diff. Don't "fix" Python to require jq.
- **Nondeterminism** (next up in Plan 4): id/date/commit — normalize in the harness.
- **clock.iso_now/date_now** are nondeterministic — any subcommand emitting them needs harness normalization.

---

## How to resume (the proven loop)

Branch is `feat/memory-router-py-foundation`. The ledger `.superpowers/sdd/progress.md` (gitignored scratch) records Plan 0/1/2 complete with commit ranges — trust it + `git log` after any context reset.

Per building block:
1. **Deep-read** the Bash subsystem first (cite exact line ranges) — don't write plan code from memory.
2. **Write a tight plan** with complete TDD code → `docs/superpowers/plans/2026-06-28-...-N-<name>.md`; commit.
3. **Subagent-driven execution** (skill `superpowers:subagent-driven-development`):
   - implementer = **haiku** (plans contain complete code → transcription+testing)
   - task reviewer = **sonnet**; final whole-branch review = **opus**
   - helper scripts: `…/subagent-driven-development/scripts/{task-brief,review-package}` (pass explicit out-paths like `.superpowers/sdd/pN-task-M-brief.md` so they don't clobber).
4. **Parity** every subcommand against `git show kimiflow--v0.1.50:hooks/memory-router.sh`; add cases to `hooks/test-memory-router-parity.sh`. Internal helpers (no subcommand) get unit tests only.
5. Commit named paths only; **no AI-attribution/co-author trailer**; never `git add -A`.

This loop has reliably caught real defects this session: the broken shim launch path, a CRLF `--input` divergence, a bash-3.2 `set -u` false-green in the harness, and the SC2318 class.

---

## Open decisions for the user (when resuming)

- Merge `feat/memory-router-py-foundation` into main now (risk-low: Bash untouched, no cutover) or keep accumulating on the branch until the port is further along?
- Push local `main` (the 2 unpushed spec/plan-0 doc commits) or leave local until there's more to ship?
