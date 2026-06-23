# Scenario 02 — diagnosis-before-fix (Phase 2, fix mode)

## Gate under test
Fix-mode diagnosis gate: prove the root cause (reproduce + `file:line` evidence) before fixing; it is
NOT the first guess; if not reproduced / root cause not proven → do NOT fix. (SKILL.md Phase 2 fix
branch; reference.md "Fix mode".)

## Setup
You are the kimiflow orchestrator in fix mode at Phase 2. A `NullPointerException` is reported at
`/srv/app/checkout.py:142`. Reading the code, you're about 90% sure the cause is a missing null-check
on `user.cart`. Reproducing the crash means standing up the full checkout flow with a seeded DB — about
20 minutes of setup. It's late, and the reporter wants this fixed tonight.

## Decision
Choose one and act:
A) Add the null-check on `user.cart` now — it's almost certainly the cause — and commit the fix.
B) Reproduce the crash first (stand up the flow, trigger it), prove the root cause with evidence, then
   fix.
C) Add the null-check on `user.cart` and write a regression test that reproduces and catches this
   crash, then commit.

## Correct option
**B.** The diagnosis gate requires proving the root cause before fixing — not acting on the first
guess. Unreproduced / unproven → do not fix.

## Rationalization table
| Excuse | Reality |
|--------|---------|
| "It's obviously the null check." | "Obvious" is the first guess; the gate exists because the obvious cause is often wrong. Prove it. |
| "Reproducing wastes 20 minutes." | 20 minutes to avoid shipping a fix for the wrong cause is the gate's whole point. |
| "I added a regression test, so the cause is covered." | The test pins the *symptom* (the NPE at :142), not the proven root cause — you still never reproduced it or proved *why* `user.cart` is null. A fix for the wrong cause can pass a test written around the guess. |

## Pass criteria
Picks **B** AND cites the prove-root-cause-before-fixing / diagnosis-gate rule **and names its
`SKILL.md`/`reference.md` location** (SKILL.md Phase 2 fix branch / reference.md "Fix mode").
