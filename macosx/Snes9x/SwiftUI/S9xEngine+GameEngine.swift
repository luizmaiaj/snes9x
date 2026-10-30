/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import AppKit
import snes9x_framework

extension S9xEngine: GameEngine {
    public func makeGameView() -> NSView {
        recreateS9xView()

        return s9xView
    }
}

/// Keeps the toolbar's pause state in step with pauses from Esc, a click on
/// the game and the Emulation menu.
extension EmulatorModel: S9xEmulationDelegate {
    public nonisolated func gameLoaded() {
        engineStateDidChange()
    }

    public nonisolated func emulationPaused() {
        engineStateDidChange()
    }

    public nonisolated func emulationResumed() {
        engineStateDidChange()
    }
}
