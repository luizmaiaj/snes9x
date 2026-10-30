/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import AppKit
import Combine

/// What the SwiftUI layer needs from the emulator core.
@objc(S9xGameEngine)
public protocol GameEngine: NSObjectProtocol {
    /// Throws away the current game view and returns a freshly created one.
    func makeGameView() -> NSView
}

/// The SwiftUI-facing model of the emulator: it publishes the engine's current
/// game view and owns the single "open a ROM" flow shared by the menu, the
/// toolbar and Finder.
@MainActor
@objc(S9xEmulatorModel)
public final class EmulatorModel: NSObject, ObservableObject {
    /// The engine's game view; replaced every time a ROM is loaded.
    @Published private(set) var gameView: NSView?

    /// Loads a ROM and returns whether it worked. Set by the app delegate so
    /// every entry point goes through `-[AppDelegate openURL:]`.
    @objc public var openHandler: ((URL) -> Bool)?

    /// Asks the user for a ROM file; returns nil when they cancel.
    var chooseROM: () -> URL? = EmulatorModel.runOpenPanel

    private let engine: GameEngine

    @objc public init(engine: GameEngine) {
        self.engine = engine
        super.init()
    }

    /// Rebuilds the engine's game view and publishes it to the window.
    @objc public func reloadGameView() {
        gameView = engine.makeGameView()
    }

    /// Lets the user pick a ROM and loads it. Cancelling, or a file that does
    /// not load, leaves the current game as it is.
    @objc @discardableResult
    public func openROM() -> Bool {
        guard let url = chooseROM(), let openHandler else {
            return false
        }

        return openHandler(url)
    }

    static func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        return panel.runModal() == .OK ? panel.url : nil
    }
}
