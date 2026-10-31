## Unreleased

### Added
- macOS: Preferences → Controls has new rows for Open ROM, Open Second ROM, Reset, Swap Sound and Swap Gamepads, so a gamepad button can trigger them. Each press does what the toolbar button does, and does nothing while that button is disabled or when Snes9x isn't the frontmost app. With two games open, Reset acts on the game that gamepad controls (#20)

### Changed
- macOS: the second game now uses the settings from Preferences, such as video mode and sound interpolation, instead of defaults. A change made while it's running applies the next time it opens (#18)

### Known issues
- macOS: the file panels Open ROM and Open Second ROM open still need a mouse or keyboard (#20)
- macOS: pressing a gamepad's Home button can also make macOS open its games app, which stops bound commands until Snes9x is back in front (#23)
