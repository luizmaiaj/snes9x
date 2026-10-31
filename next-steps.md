# Next steps — snes9x (luizmaiaj fork)
_Last updated: 2026-10-30 by github-issue-fix_

## Queue (do next, roughly in order)
- [ ] Luiz checks #17 in the installed build: click Save State and Load State, pick a slot with the arrow keys and Return, then Esc to cancel; Claudio could not click toolbar buttons
- [ ] Luiz checks #13 in the installed build: open a non-ROM file, press OK, and the game carries on
- [ ] #2 — Luiz closes it by hand once #17 closes with the next release (umbrella, GitHub won't close it on its own)
- [ ] Luiz checks #16 in the installed build: File → Open MultiCart with a non-ROM file shows the error, and the game carries on; then closes #16 by hand. Claudio could not see the alert, and real Sufami Turbo files are still untested
- [ ] #18 — Two games side by side in one window, with a gamepad each and swappable sound and gamepads (large: the core runs one game per process, so the approach needs agreeing first)

## Blocked / waiting
- [ ] Input Monitoring — the fork's builds are signed with Luiz's Developer ID, so macOS treats them as a new app; Snes9x may need adding again in Privacy & Security → Input Monitoring for gamepads

## Recently done
- #16 — Open MultiCart checks the first file before stopping the game (2026-10-30)
- #17 — Save State and Load State toolbar buttons (2026-10-30)
- #13 — Non-ROM files are refused before the game stops (2026-10-30, merged in PR #15)
- #11 — Keyboard choice for Player 1 holds (2026-10-30, released in v26.10.30.5)
- #7 — Gamepads connecting and disconnecting after launch (2026-10-30, released in v26.10.30.4)
- #8 — Controls pane stops the previous gamepad straight away (2026-10-30, released in v26.10.30.4)
- #5 — Pause/Resume and Reset toolbar buttons (2026-10-30, released in v26.10.30.5)
- #6 — Player 1 gamepad menu and launch auto-assign (2026-10-30, released in v26.10.30.5)
- #1 — SwiftUI game window and EmulatorModel on top of S9xEngine (2026-10-30, released in v26.10.30.5)
- #3 — Open ROM toolbar button (2026-10-30, checked by Luiz; closed by PR #15)
