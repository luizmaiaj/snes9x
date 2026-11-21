## Unreleased

### Fixed
- macOS tests: the toolbar tests wait for SwiftUI to give each button its action instead of a fixed 0.2 seconds, so the Pause, Reset and Open ROM tests no longer fail now and then (#27)
- macOS: no build warnings left in the app and test targets
