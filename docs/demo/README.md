# docs/demo — the kimiflow demo GIF

The README's **30-second demo** links here. The goal is a short loop showing the three hard stops:
the **diagnose-gate** (no proven cause → no fix), the **plan-gate** (fail-closed blocker count), and
the **commit-gate** (stops for your OK).

Two ways to produce it. **Prefer A** — a real recording is the honest, credible artifact. B is a
cosmetic placeholder, clearly labelled.

## A — record a real run (recommended)

A genuine capture of `/kimiflow` driving an actual bug fix. This is what should ship in the README.

**Tools:** [`asciinema`](https://asciinema.org) to record, [`agg`](https://github.com/asciinema/agg)
to convert to GIF.
```bash
brew install asciinema agg     # macOS · or see each project's install docs
```

**A reproducible demo bug** (so the recording is repeatable): reuse the
[`02-risky-bugfix`](../../examples/02-risky-bugfix.md) scenario — a token refresh that throws on a
rotated refresh token — or any small real bug in a throwaway repo where the diagnose-gate and a
plan-gate round actually fire. A run where every gate passes first try is a boring demo; pick one
that makes a gate *work*.

**Record → convert:**
```bash
asciinema rec kimiflow.cast -c "claude"        # then, inside: /kimiflow --fix <the bug>
# drive the run; Ctrl-D to stop recording when the commit-gate STOPs
agg --theme monokai --font-size 18 kimiflow.cast kimiflow.gif
```

**Tips:** terminal ~100×30, a high-contrast theme, and *stop at the commit-gate* — the whole point is
showing it waits for you. `kimiflow.cast` is plain JSON; trim dead air before converting if a phase
ran long.

## B — branded illustration (placeholder, clearly labelled)

A deterministic, scripted reconstruction for a clean branded loop **before** a real capture exists.
It is **not** a model run — [`play.sh`](play.sh) just prints the demo block with phase pacing.

**Tool:** [`vhs`](https://github.com/charmbracelet/vhs).
```bash
brew install vhs
vhs kimiflow-demo.tape          # → kimiflow.gif
```

If you ship B, caption it as an illustration in the README. Replace it with an A capture as soon as
you have one.

## Embedding

Drop `kimiflow.gif` next to this file and reference it from the top README, e.g.:
```markdown
![kimiflow demo](docs/demo/kimiflow.gif)
```
Keep it under ~3 MB so GitHub renders it inline; `agg` (`--font-size`, `--speed`) and `vhs`
(`Set Width/Height`, `Set PlaybackSpeed`) both expose size/speed knobs.

> **No `kimiflow.gif` is committed yet** — record A (or render B) and add it. Until then the README's
> text demo stands on its own, so nothing references a missing image.
