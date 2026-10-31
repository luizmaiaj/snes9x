# Next steps — snes9x (luizmaiaj fork)
_Last updated: 2026-10-31 by github-issue-fix_

## Queue (do next, roughly in order)
- [ ] Luiz checks #17 in the installed build: click Save State and Load State, pick a slot with the arrow keys and Return, then Esc to cancel; Claudio could not click toolbar buttons
- [ ] Luiz checks #13 in the installed build: open a non-ROM file, press OK, and the game carries on
- [ ] Luiz checks #18's prototype in the installed build: Open Second ROM beside Open ROM, then File → Close Second Game. The open panel and both buttons were never clicked; Claudio drove them from the debugger
- [ ] #18 — Gamepads per game, swap gamepads, move the sound, and which game Pause, Reset and the save buttons act on. Still open: keyboard and full screen
- [ ] #20 — Count the 8BitDo's buttons, then let them trigger any game or app command (needs the pad connected; settle how it fits #18 first)

## Blocked / waiting
- [ ] Input Monitoring — the fork's builds are signed with Luiz's Developer ID, so macOS treats them as a new app; Snes9x may need adding again in Privacy & Security → Input Monitoring for gamepads

## Recently done
- #18 prototype — Two games side by side, one process each, 60 fps; second game muted with no gamepad (2026-10-31, not released)
- #2 — Umbrella closed by hand, all 8 sub-issues done (2026-10-31)
- #16 — Open MultiCart checks the first file before stopping the game (2026-10-30, released in v26.10.31.7; closed 2026-10-31 without checking the alert or real Sufami Turbo files)
- #17 — Save State and Load State toolbar buttons (2026-10-30, released in v26.10.31.7)
- #13 — Non-ROM files are refused before the game stops (2026-10-30, merged in PR #15)
- #11 — Keyboard choice for Player 1 holds (2026-10-30, released in v26.10.30.5)
- #7 — Gamepads connecting and disconnecting after launch (2026-10-30, released in v26.10.30.4)
- #8 — Controls pane stops the previous gamepad straight away (2026-10-30, released in v26.10.30.4)
- #5 — Pause/Resume and Reset toolbar buttons (2026-10-30, released in v26.10.30.5)
- #6 — Player 1 gamepad menu and launch auto-assign (2026-10-30, released in v26.10.30.5)
- #1 — SwiftUI game window and EmulatorModel on top of S9xEngine (2026-10-30, released in v26.10.30.5)
- #3 — Open ROM toolbar button (2026-10-30, checked by Luiz; closed by PR #15)
