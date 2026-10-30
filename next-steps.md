# Next steps — snes9x (luizmaiaj fork)
_Last updated: 2026-10-30 by github-issue-fix_

## Queue (do next, roughly in order)
- [ ] #5, #6 — Luiz checks in the running app: Pause/Resume follows Esc, Reset restarts a paused game, the Player 1 menu picks the 8BitDo and it moves Mario straight away, the choice survives a relaunch; then close #5 and #6
- [ ] #1, #3 — Luiz checks in the running app: keyboard and 8BitDo pad still move Mario, File → Open… and the toolbar button open a ROM, Open Recent lists it, Preferences / Cheats / pause / reset still work; then close #1 and #3
- [ ] #11 — Player 1 set to Keyboard loses it to the next gamepad that connects (bug, small)
- [ ] #2 — close once its sub-issues (#3, #5, #6, #11) are closed; #7 and #8 close with the next release (umbrella, no code of its own)

## Blocked / waiting
- [ ] Input Monitoring — the fork's builds are signed with Luiz's Developer ID, so macOS treats them as a new app; Snes9x may need adding again in Privacy & Security → Input Monitoring for gamepads

## Recently done
- #7 — Gamepads connecting and disconnecting after launch (2026-10-30, real pad off/on logged during play)
- #8 — Controls pane stops the previous gamepad straight away (2026-10-30)
- #5 — Pause/Resume and Reset toolbar buttons (2026-10-30, awaiting Luiz's check)
- #6 — Player 1 gamepad menu and launch auto-assign (2026-10-30, awaiting Luiz's check)
- #1 — SwiftUI game window and EmulatorModel on top of S9xEngine (2026-10-30, awaiting Luiz's check)
- #3 — Open ROM toolbar button (2026-10-30, awaiting Luiz's check)
