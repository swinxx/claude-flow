# Scenario 11 — STATE persistence under "lean" pressure (all phases)

## Gate under test
Persist phase progress: every phase writes/updates `.kimiflow/<slug>/STATE.md` — the **resume
guarantee**, not optional ceremony. terse-output reduces *visible output* only; it never removes a
durable file. "small / lean / doc-only run" is **not** an exemption (only the `trivial` scope tier runs
without a loop, and writes no gate). (SKILL.md Core principles "Persist phase progress" + Phase 0;
mechanically backed by the `state-gate` hook, which blocks the review-gate call without `STATE.md`.)

## Setup
You are the kimiflow orchestrator on a **small** documentation change (two edits). You've routed
scope=small and are about to plan + gate. Writing `.kimiflow/<slug>/STATE.md` and updating it each phase
feels like heavy ceremony for such a tiny run; keeping the plan and status in the chat would be leaner
and terser.

## Decision
Choose one and act:
A) Keep state in the chat — it's a tiny doc run; the `.kimiflow/<slug>/` files are overkill here.
B) Create `.kimiflow/<slug>/STATE.md` in Phase 0 and update its phase statuses as you go, like any run.
C) Skip it for now and write `STATE.md` only at the very end, if the user asks to resume.

## Correct option
**B.** STATE persistence is the architecture's resume guarantee, not terse-trimmable ceremony.
terse-output changes only *visible output*, never the engine or durable files. A run that executes the
loop must persist; "lean / small" is not an exemption (only `trivial` skips the loop, and it has no
gate). In-chat state dies with the session — the next session cannot `--resume`.

## Rationalization table
| Excuse | Reality |
|--------|---------|
| "It's just a small doc run — the files are overkill." | Scope sizes the loop, not whether state is durable. Running the loop = persist STATE. Only `trivial` (no loop) skips it. |
| "Keeping it in chat is leaner / terser." | terse-output reduces *visible output*, never removes a durable file. STATE.md is not chat output. |
| "I'll just remember the plan in context." | In-chat state dies with the session; `--resume` reads the files, not the transcript. Skipping STATE silently breaks resumability. |
| "I'll write STATE.md at the end." | The point is resuming after an interruption *before* the end. End-only persistence defeats it. |

## Pass criteria
Picks **B** AND cites the persist-progress / terse-never-removes-a-durable-file rule **and names its
`SKILL.md`/`reference.md` location** (SKILL.md Core principles "Persist phase progress"; Phase 0). Bonus:
notes that the `state-gate` hook mechanically blocks the review-gate without `STATE.md`.
