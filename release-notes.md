## Unreleased

### Added
- macOS: Pause/Resume and Reset buttons in the game window's toolbar. Pause follows Esc and the Emulation menu; Reset restarts a paused game, the same as Emulation → Software Reset (#5, part of #2)
- macOS: a Player 1 menu in the toolbar shows whether Player 1 uses a gamepad or only the keyboard and lets you pick the gamepad; the choice is saved with Preferences → Controls (#6, part of #2)
- macOS: at launch, when Player 1 has no connected gamepad, the first connected gamepad no other player uses becomes Player 1, so a new pad works without opening Preferences (#6)

### Fixed
- macOS: choosing a different Player 1 device from the toolbar stops the old gamepad driving Player 1 straight away, instead of only after a relaunch (#6)
- macOS: Preferences → Controls shows the current device each time it opens, including a change made from the toolbar (#6)
