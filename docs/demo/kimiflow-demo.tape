# kimiflow-demo.tape — render the SCRIPTED ILLUSTRATION (play.sh) to a GIF.
# play.sh walks a feature build (dark-mode toggle) through the 8 phases to the
# commit-gate. This is a reconstruction for a clean branded loop, NOT a captured
# model session. For a real run, see the asciinema steps in README.md.
#
# Render:  vhs kimiflow-demo.tape        →   kimiflow.gif

Output kimiflow.gif

Require bash
Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 900
Set Padding 28
Set Theme "Catppuccin Mocha"
Set PlaybackSpeed 1.0

Hide
Type "clear" Enter
Show
Sleep 400ms

Type "bash play.sh" Sleep 500ms Enter
# play.sh prints for ~14s; then hold the completed frame ~7s so the last line
# is readable before the loop restarts (static frames cost ~nothing in a GIF).
Sleep 14s
Sleep 7s
