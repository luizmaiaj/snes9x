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

    /// Whether a game is loaded and running (paused or not).
    func isRunning() -> Bool

    /// Whether the running game is paused.
    func isPaused() -> Bool

    func pause()
    func resume()

    /// Restarts the game like the console's reset button, and resumes it.
    func softwareReset()
}

/// A connected gamepad, identified by the key Snes9x saves its settings under.
@objc(S9xGamepad)
public final class Gamepad: NSObject {
    @objc public let key: String
    @objc public let name: String

    @objc public init(key: String, name: String) {
        self.key = key
        self.name = name
        super.init()
    }
}

/// Which gamepad each player uses, kept in the same preferences as
/// Preferences → Controls. Players are numbered from 0.
@objc(S9xGamepadAssignments)
public protocol GamepadAssignments: NSObjectProtocol {
    /// The gamepads connected now.
    func connectedGamepads() -> [Gamepad]

    /// The key of the gamepad `player` uses, or nil when it has none.
    func gamepadKey(forPlayer player: Int) -> String?

    /// The player using the gamepad with `key`, or -1 when none does.
    func player(forGamepadKey key: String) -> Int

    /// Gives `player` the gamepad with `key`; nil leaves it the keyboard only.
    func assignGamepad(withKey key: String?, toPlayer player: Int)
}

/// The SwiftUI-facing model of the emulator: it publishes the engine's current
/// game view and state, and owns the single "open a ROM" flow shared by the
/// menu, the toolbar and Finder.
@MainActor
@objc(S9xEmulatorModel)
public final class EmulatorModel: NSObject, ObservableObject {
    /// The engine's game view; replaced every time a ROM is loaded.
    @Published private(set) var gameView: NSView?

    /// Whether a game is loaded and running (paused or not).
    @Published private(set) var isRunning = false

    /// Whether the running game is paused.
    @Published private(set) var isPaused = false

    /// The gamepads connected now.
    @Published private(set) var gamepads: [Gamepad] = []

    /// Player 1's gamepad, or nil when Player 1 uses the keyboard only.
    @Published private(set) var player1Gamepad: Gamepad?

    /// Loads a ROM and returns whether it worked. Set by the app delegate so
    /// every entry point goes through `-[AppDelegate openURL:]`.
    @objc public var openHandler: ((URL) -> Bool)?

    /// Reads and saves which gamepad each player uses.
    @objc public weak var gamepadAssignments: GamepadAssignments? {
        didSet {
            refreshGamepads()
        }
    }

    /// Asks the user for a ROM file; returns nil when they cancel.
    var chooseROM: () -> URL? = EmulatorModel.runOpenPanel

    /// What Preferences → Controls saves for a player on the keyboard.
    private static let keyboardKey = "0:0:0"

    private let engine: GameEngine
    private var defaultsObserver: AnyCancellable?

    @objc public init(engine: GameEngine) {
        self.engine = engine
        super.init()

        // Preferences → Controls saves player assignments to the defaults.
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshGamepads()
                }
            }
    }

    /// Rebuilds the engine's game view and publishes it to the window.
    @objc public func reloadGameView() {
        gameView = engine.makeGameView()
        refreshEmulationState()
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

    // MARK: - Pause and reset

    /// Pauses the running game, or resumes it when it is paused.
    func togglePause() {
        guard engine.isRunning() else {
            return
        }

        if engine.isPaused() {
            engine.resume()
        } else {
            engine.pause()
        }

        refreshEmulationState()
    }

    /// Restarts the game. Like Emulation → Software Reset, it only works
    /// while the game is paused: the engine resets the core from this thread.
    func reset() {
        guard engine.isPaused() else {
            return
        }

        engine.softwareReset()
        refreshEmulationState()
    }

    /// Reads whether a game is running or paused back from the engine.
    /// Publishes only real changes: any update redraws the toolbar, which
    /// closes a toolbar menu the user has open.
    @objc public func refreshEmulationState() {
        let running = engine.isRunning()
        let paused = engine.isPaused()

        if running != isRunning {
            isRunning = running
        }

        if paused != isPaused {
            isPaused = paused
        }
    }

    /// Called by the engine when a game loads, pauses or resumes, which can
    /// happen on the emulation thread (Esc toggles the pause there).
    nonisolated func engineStateDidChange() {
        Task { @MainActor in
            self.refreshEmulationState()
        }
    }

    // MARK: - Player 1's gamepad

    /// Reads the connected gamepads and Player 1's from the assignments.
    /// Publishes only real changes, like `refreshEmulationState()`.
    @objc public func refreshGamepads() {
        let connected = gamepadAssignments?.connectedGamepads() ?? []
        let player1Key = gamepadAssignments?.gamepadKey(forPlayer: 0)

        if connected.map(\.key) != gamepads.map(\.key) {
            gamepads = connected
        }

        // Keyboard and a pad that isn't connected both show as no gamepad.
        let player1 = gamepads.first { $0.key == player1Key }

        if player1?.key != player1Gamepad?.key {
            player1Gamepad = player1
        }
    }

    /// Makes `gamepad` control Player 1; nil leaves Player 1 the keyboard only.
    func choosePlayer1Gamepad(_ gamepad: Gamepad?) {
        gamepadAssignments?.assignGamepad(withKey: gamepad?.key, toPlayer: 0)
        refreshGamepads()
    }

    /// Called when a gamepad connects or disconnects. One that connects can
    /// become Player 1, as at launch. One that disconnects hands Player 1 to
    /// nobody, so it is still Player 1 when it comes back.
    @objc public func gamepadsDidChange() {
        let known = gamepads.map(\.key)
        let connected = gamepadAssignments?.connectedGamepads() ?? []

        if connected.contains(where: { !known.contains($0.key) }) {
            assignPlayer1GamepadIfNeeded()
        } else {
            refreshGamepads()
        }
    }

    /// A gamepad no player uses does nothing, so when Player 1 has no
    /// connected gamepad it gets the first connected one no other player uses.
    /// Keyboard is a choice, not a missing gamepad, so it stays.
    @objc public func assignPlayer1GamepadIfNeeded() {
        guard let assignments = gamepadAssignments else {
            return
        }

        let connected = assignments.connectedGamepads()
        let player1Key = assignments.gamepadKey(forPlayer: 0)

        guard player1Key != EmulatorModel.keyboardKey,
              !connected.contains(where: { $0.key == player1Key }),
              let free = connected.first(where: { assignments.player(forGamepadKey: $0.key) < 0 }) else {
            refreshGamepads()
            return
        }

        choosePlayer1Gamepad(free)
    }
}
