# kimiflow-demo.tape — render the SCRIPTED ILLUSTRATION (play.sh) to a GIF.
# This is a reconstruction for a clean branded loop, NOT a captured model session.
# For a real run, follow the asciinema steps in README.md.
#
# Render:  vhs kimiflow-demo.tape        →   kimiflow.gif

Output kimiflow.gif

Require bash
Set Shell bash
Set FontSize 17
Set Width 1180
Set Height 660
Set Padding 28
Set Theme "Catppuccin Mocha"
Set PlaybackSpeed 1.0

Hide
Type "clear" Enter
Show
Sleep 400ms

Type "bash play.sh" Sleep 500ms Enter
Sleep 9s
