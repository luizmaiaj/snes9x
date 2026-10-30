## Unreleased

### Added
- macOS: an Open ROM button in the game window's toolbar opens a ROM file and starts it, the same as File → Open… (#3, part of #2)
- macOS: in full screen the toolbar hides and comes back, with the window buttons, when the pointer reaches the top of the screen (part of #2)
- macOS: unit tests for the new SwiftUI layer (`Snes9xTests` target, run with the `snes9x` scheme)

### Changed
- macOS: the game window's content is now SwiftUI, driven by a new `EmulatorModel` on top of `S9xEngine`; menus, Preferences and Cheats are unchanged (#1)
- macOS: the menu, the toolbar and opening a file from Finder all load ROMs through one shared path (#1)
- macOS: requires macOS 14 or later (was 10.12); current Xcode no longer builds for 10.12 (#1)
- macOS: Release builds sign with the fork's own Developer ID instead of upstream's (#1)
- macOS: the game window is 40 pt taller to fit the toolbar; the game area grows from 512×452 to 512×480 (#3)
