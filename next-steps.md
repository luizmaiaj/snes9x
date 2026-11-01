# Next steps — snes9x (luizmaiaj fork)
_Last updated: 2026-11-01 by github-issue-fix_

## Queue (do next, roughly in order)
- [ ] #27 — Fix the intermittent failure in testThePauseButtonPausesAndResumesTheGame; a clean main can show red
- [ ] #20 — Repeat the map in S, A and X modes and over USB; needs Luiz at the pad
- [ ] #20 — Try Swap Gamepads and Open Second ROM from a real pad, and a command on a stick; Claudio drives the app, and Luiz only presses the pad

## Blocked / waiting
- [ ] #18 — Two pads at once; needs a second pad

## Recently done
- #23 — No code needed: macOS 27 ignores an app's Home request until the user changes the Home button settings. Luiz changed them, and Home now works as a plain button in Snes9x, with Pause/Resume bound to it (2026-11-01, closed without a code change)
- #20 GCController — Sees the pad in D mode and declares nothing beyond IOHIDManager's map; presses not compared one by one (2026-11-01)
- #17 and #13 hand checks — Luiz checked both in v26.11.01.11 (2026-11-01)
- UI tests — `Snes9xUITests` scheme drives the real window for #17 and #13; 3 pass. Runs take over the mouse and keyboard, so ask Luiz before each run (2026-11-01, not released)
- #25 — Game 1 uses the saved frame skip at launch (2026-11-01, released in v26.11.01.11)
- #18 hand checks — Toolbar buttons, sound, Swap Gamepads, menus, keyboard, full screen and a pad going off and on all checked by Luiz on a Release build; found and fixed four faults (2026-11-01, released in v26.11.01.11). Two pads at once not tried: only one pad here
- #20 hand checks — Binding, rebinding and relaunch checked by Luiz in the real Preferences fields (2026-11-01). Swap Gamepads and Open Second ROM from a pad, and a command on a stick, not tried
- #20 commands — Five toolbar commands bindable from a pad (2026-10-31, released by v26.11.01.11)
- #18 game 2 settings — The second game uses Preferences (2026-10-31, released by v26.11.01.11)
- #20 control map — All Pro 2 controls in D-input over Bluetooth; Star sends nothing, profile button shows nothing (2026-10-31); S/A/X modes, USB and GCController not tried
- #18 per-game controls — Pads, keyboard, sound swap and game 2's own buttons (2026-10-31, released by v26.11.01.11)
- #18 prototype — Two games side by side, one process each, 60 fps (2026-10-31, released in v26.10.31.8)
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
