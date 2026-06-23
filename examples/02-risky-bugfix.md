# Example 02 — risky bugfix: auth token refresh throws after expiry

> **Illustrative walkthrough — not a captured transcript.** Phase order, gate behaviour, finding
> format and artifact names match the skill spec; the project, paths and `file:line` refs are
> invented. See [`README.md`](README.md) for why.

This is the run the README's 30-second demo summarises. It's deliberately *risky*: it touches auth,
the obvious fix is wrong, and the plan-gate earns its keep by catching a real HIGH before any code is
written. Full loop, `large` scope.

---

```
/kimiflow --fix  users get logged out at random — token refresh throws once the access token expires
```

### ⚪ Phase 0 — Setup, routing & scope-gate

- `--fix` → **fix mode** (forced).
- Scope-gate: touches the auth/session path, security-sensitive, reproducible → **`large`**.
  Announced: *"Scope: large — 2 reviewers, plan-gate loop, verify with regression + cold-start,
  test-gate auto-armed."*
- State dir: `.kimiflow/token-refresh-throws/`.

### 🔵 Phase 1 — Clarify (problem)

- *Symptom?* intermittent forced logouts.
- *Repro?* let the access token expire (TTL 15 min), then make any authed request → a throw, session
  cleared.
- *Expected?* the refresh token silently mints a new access token; the request succeeds.

→ `PROBLEM.md`. ✋ **"Does this match?"** → confirmed: *"the refresh path should be transparent."*

### 🟣 Phase 2 — Understand & research / diagnose

Memory-first: checks `.kimiflow/DECISIONS.md` and the vault (if a notes MCP is present) for prior
auth findings → none relevant. Then reproduces and **proves** the cause:

- Reproduction test: advance the clock past the access-token TTL, call `api.get('/me')` → throws
  `TokenError: refresh response missing access_token`.
- Traced:

  ```
  src/auth/refresh.ts:88
    const res = await fetch(REFRESH_URL, { method: 'POST', body: cookieRefreshToken });
    return res.json().access_token;          // ← unguarded: assumes 200 + a body
  ```

  The provider returns **`401` + an empty body** when the *refresh* token itself has rotated
  (sliding-window rotation, enabled provider-side 3 weeks ago). `res.json()` on an empty body
  rejects; the rejection isn't caught, so the caller treats it as "auth broken" and clears the
  session — instead of re-authenticating.
- ⚠ The naive fix ("wrap in try/catch, return null") would **mask a real expired-session case** and
  log users out *silently* — worse UX, same logout. Researched the provider's rotation contract
  (context7 / provider docs): on a rotated refresh token the client must **restart the auth code
  flow**, not retry the refresh.
- ⛔ **Diagnose-gate cleared:** cause proven at `refresh.ts:88` + the provider contract named. Without
  this, no fix.

→ `DIAGNOSIS.md` (root cause · provider rotation contract · why the naive fix is wrong). One reusable
finding saved back to project memory / vault.

### ⚫ Phase 3 — Plan

- `PLAN.md`:
  1. Guard the refresh response: on non-200 or missing `access_token`, **distinguish** "refresh
     token rotated/expired" (→ trigger re-auth) from "transient 5xx" (→ one bounded retry).
  2. Surface a typed `ReauthRequired` signal the session layer already understands — no silent
     session-clear.
- `ACCEPTANCE.md` (EARS + `AC-N → test`):
  - `AC-1` — *WHEN the refresh endpoint returns 401, THE client SHALL emit `ReauthRequired` and
    SHALL NOT clear the session.* → `refresh.spec.ts › 401 triggers reauth, keeps session`
  - `AC-2` — *WHEN the refresh endpoint returns 200 with a new access token, THE original request
    SHALL be retried once and succeed.* → `refresh.spec.ts › transparent refresh on expiry`
  - `AC-3` — *WHEN the refresh endpoint returns 503, THE client SHALL retry once, then surface a
    transient error (NOT a logout).* → `refresh.spec.ts › transient 5xx is not a logout`
  - Central fix-mode criterion: the Phase-2 reproduction no longer throws; no regression.

### 🟡 Phase 4 — Plan-gate (loop, binary, cap 3)

**Round 1** — 2 independent reviewers, fresh context, adversarial framing ("you did NOT write this;
assume it's flawed"):

`findings/r1-A.md` (goal/completeness):
```
NONE
```
`findings/r1-B.md` (risk):
```
FINDING HIGH src/auth/refresh.ts :: AC-3 retries 503 but does not bound the retry — a provider stuck at 503 becomes an infinite refresh loop hammering the auth endpoint. Specify max 1 retry + surfaced error.
FINDING LOW  ACCEPTANCE.md :: AC-2 says "retried once and succeed" but doesn't pin the retry to the *same* request idempotently; clarify.
```

Gate: `resolve-review-gate.sh findings --round 1 --expect A,B` → `open-findings⇥1⇥open-findings⇥…`
→ **1 open BLOCKER/HIGH → gate CLOSED.** Revise narrowly (don't re-architect): pin AC-3 to **exactly
one** retry then a typed transient error; tighten AC-2's idempotency wording. `REVIEW.md` gets the
narrative.

**Round 2** — same two reviewers re-examine. A finding counts as resolved only when the next round's
reviewer no longer raises it:

`findings/r2-A.md` → `NONE` · `findings/r2-B.md` → `NONE`

Gate: `resolve-review-gate.sh findings --round 2 --expect A,B` → `clean⇥0⇥clean⇥…` → **0 open ✅**.
Anti-oscillation check: open HIGH count went 1 → 0 (strictly decreased), nothing reappeared → healthy.
(Cap is 3; had round 3 still shown an open blocker, the gate would **stop and ask**, never
auto-proceed.)

### 🟠 Phase 5 — Implement (TDD)

- Red first: the three AC tests + the Phase-2 reproduction, all failing.
- Fix `refresh.ts`: status-aware handling — `401 → throw ReauthRequired` (caught by the session layer,
  which restarts the code flow), `>=500 → one bounded retry → typed transient error`, `200 →` parse
  guarded, retry the original request once.
- Surgical: only `refresh.ts` + its test; the session layer already handled `ReauthRequired`, so no
  change there. No unrelated cleanup.

### 🟤 Phase 6 — Verify (goal-backward)

- Each criterion's method run, decisive line shown:
  - `✓ 401 triggers reauth, keeps session` (AC-1)
  - `✓ transparent refresh on expiry` (AC-2) — the **reproduction no longer throws**
  - `✓ transient 5xx is not a logout` (AC-3)
- Regression: full auth suite green.
- Cold-start smoke test (diff touches the auth path): boot once, expire a token, confirm a live
  request transparently refreshes. Passes.
- Goal-backward: every AC artifact Exists / Substantive / Wired.

### 🟢 Phase 7 — Code-review → commit-gate

1. `code-review-audit` (fresh, adversarial) over the diff + specs: correctness/security only; also
   *"were tests weakened to go green?"* → no. Runs the bundled `test-weakening-scan.sh` and the
   optional `secret-content-scan.sh` → both append any `FLAG`s to `ADVISORIES.md` (here: none).
   → `CODE-REVIEW.md`: clean.
2. Same findings-file + `resolve-review-gate.sh` loop as Phase 4 — round 1 clean, gate open.
3. ✋ **Commit-gate — STOP.** Advisory triage first (no flags to dismiss). Then:

   ```
   fix(auth): handle rotated/expired refresh token without clearing the session

    src/auth/refresh.ts        | 31 +++++++++++++----
    src/auth/refresh.spec.ts   | 58 +++++++++++++++++++++++++++++++
   ```

   Shows `git status` + `git diff --staged`, **waits for your explicit OK**. On OK → commits the two
   named paths only. Because scope is `large` and tests are green, it writes a local untracked
   `.kimiflow/test-gate` (the verified test command) so future runs in this repo can't finish red —
   and announces it. **Never auto-commits.**
4. Project memory: appends the provider's refresh-rotation contract to `.kimiflow/STANDARDS.md` and a
   3–5 line decision entry; optional one-line `LEDGER.md` run record (slug, scope=large, rounds=2,
   gate=open).

---

**Why the loop paid off here:** the obvious fix (swallow the error) would have shipped a *silent*
logout. The plan-gate's round-1 HIGH forced bounding the retry before a line of code was written, and
the diagnose-gate forced proving the provider's rotation contract instead of guessing. Cost: 2
reviewers × 2 rounds + a verifier. That's the trade the scope-gate reserves for `large`, risky work —
and the honest question of whether it buys fewer post-merge bugs lives in
[`../evals/outcomes.md`](../evals/outcomes.md).
