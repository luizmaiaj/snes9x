## Unreleased

### Added
- macOS: a gamepad switched on after launch works straight away, without a relaunch. It drives the player it is saved for, or becomes Player 1 if Player 1 has no connected pad, and it appears in the toolbar's Player 1 menu and in Preferences → Controls (#7)

### Fixed
- macOS: a gamepad that disconnects leaves the Player 1 menu and Preferences → Controls, doesn't leave a held button stuck, and keeps its player and button mapping for when it comes back (#7)
- macOS: changing a player's device in Preferences → Controls stops the previous gamepad driving that player straight away, instead of after a relaunch (#8)
