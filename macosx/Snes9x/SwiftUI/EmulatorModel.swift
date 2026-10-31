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

    /// Opens the slot picker to save the game, like the Freeze key.
    func saveState()

    /// Opens the slot picker to load a saved game, like the Defrost key.
    func loadState()

    /// Silences the game, or brings its sound back.
    func setMuted(_ muted: Bool)
}

/// Runs a second game beside the first. Two games can't share a process, as
/// the core keeps its state in globals.
protocol SecondGameRunner: AnyObject {
    /// Starts `url` and returns the view showing it, or nil when it can't start.
    /// `onPausedChange` runs when the game pauses or resumes, however that
    /// happened; `onExit` runs if the game ends without `stop()` being called.
    func start(_ url: URL, onPausedChange: @escaping @MainActor (Bool) -> Void, onExit: @escaping @MainActor () -> Void) -> NSView?

    /// Ends the game, which saves it first.
    func stop()

    func togglePause()

    /// Restarts the game and resumes it.
    func reset()

    func saveState()
    func loadState()
    func setMuted(_ muted: Bool)

    /// Gives the game the input with `key`: a gamepad's, `EmulatorModel.keyboardKey`,
    /// or nil for none.
    func setInput(_ key: String?)
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

    /// The view showing the second game, or nil when there's only one game.
    @Published private(set) var secondGameView: NSView?

    /// Whether the second game is paused.
    @Published private(set) var isSecondGamePaused = false

    /// Whether the second game has the sound. Only one game ever does.
    @Published private(set) var secondGameHasSound = false

    /// The second game's gamepad key, `keyboardKey`, or nil for no input.
    @Published private(set) var secondGameInput: String?

    /// The gamepads connected now.
    @Published private(set) var gamepads: [Gamepad] = []

    /// Player 1's gamepad, or nil when Player 1 uses the keyboard only.
    @Published private(set) var player1Gamepad: Gamepad?

    /// Loads a ROM and returns whether it worked. Set by the app delegate so
    /// every entry point goes through `-[AppDelegate openURL:]`.
    @objc public var openHandler: ((URL) -> Bool)?

    /// Tells the user a file can't be opened as the second game.
    @objc public var cantOpenHandler: ((URL) -> Void)?

    /// Reads and saves which gamepad each player uses.
    @objc public weak var gamepadAssignments: GamepadAssignments? {
        didSet {
            refreshGamepads()
        }
    }

    /// Asks the user for a ROM file; returns nil when they cancel.
    var chooseROM: () -> URL? = EmulatorModel.runOpenPanel

    /// Runs the second game.
    var secondGameRunner: SecondGameRunner = SecondGameProcess()

    /// What Preferences → Controls saves for a player on the keyboard.
    static let keyboardKey = "0:0:0"

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

    // MARK: - The second game

    /// Whether a second game is showing beside the first.
    @objc public var hasSecondGame: Bool {
        secondGameView != nil
    }

    /// Lets the user pick a ROM to show beside the running game.
    func openSecondROM() {
        if let url = chooseROM() {
            openSecondGame(url)
        }
    }

    /// Shows `url` beside the running game, which carries on. The same ROM is
    /// fine: the second game has its own saves.
    @objc public func openSecondGame(_ url: URL) {
        guard isRunning, secondGameView == nil else {
            return
        }

        secondGameView = secondGameRunner.start(url) { [weak self] paused in
            self?.isSecondGamePaused = paused
        } onExit: { [weak self] in
            self?.secondGameDidEnd()
        }

        if secondGameView == nil {
            cantOpenHandler?(url)
            return
        }

        assignSecondGameGamepadIfNeeded()
    }

    /// Ends the second game and gives the window back to the first.
    @objc public func closeSecondGame() {
        guard secondGameView != nil else {
            return
        }

        secondGameRunner.stop()
        secondGameDidEnd()
    }

    /// The first game takes back the window and the sound.
    private func secondGameDidEnd() {
        secondGameView = nil
        isSecondGamePaused = false
        secondGameInput = nil

        if secondGameHasSound {
            secondGameHasSound = false
            engine.setMuted(false)
        }

        refreshGamepads()
    }

    func toggleSecondGamePause() {
        if hasSecondGame {
            secondGameRunner.togglePause()
        }
    }

    /// Restarts the second game. Like `reset()`, only while it's paused.
    func resetSecondGame() {
        if isSecondGamePaused {
            secondGameRunner.reset()
        }
    }

    func saveSecondGameState() {
        if hasSecondGame {
            secondGameRunner.saveState()
        }
    }

    func loadSecondGameState() {
        if hasSecondGame {
            secondGameRunner.loadState()
        }
    }

    /// Moves the sound to the other game.
    func swapSound() {
        guard hasSecondGame else {
            return
        }

        secondGameHasSound.toggle()
        engine.setMuted(secondGameHasSound)
        secondGameRunner.setMuted(!secondGameHasSound)
    }

    // MARK: - The second game's input

    /// Whether Player 1 is on the keyboard, not a gamepad.
    private var firstGameUsesKeyboard: Bool {
        let key = gamepadAssignments?.gamepadKey(forPlayer: 0)
        return key == nil || key == EmulatorModel.keyboardKey
    }

    /// Whether the first game holds the input with `key`.
    private func firstGameHolds(_ key: String) -> Bool {
        if key == EmulatorModel.keyboardKey {
            return firstGameUsesKeyboard
        }

        return (gamepadAssignments?.player(forGamepadKey: key) ?? -1) >= 0
    }

    /// Whether the second game can take the input with `key`; nil is always fine.
    func secondGameCanUse(_ key: String?) -> Bool {
        guard let key else {
            return true
        }

        return !firstGameHolds(key)
    }

    /// Whether Player 1 can take the gamepad with `key`; nil is the keyboard.
    func player1CanUse(_ key: String?) -> Bool {
        (key ?? EmulatorModel.keyboardKey) != secondGameInput
    }

    /// Gives the second game an input the first game isn't using.
    func chooseSecondGameInput(_ key: String?) {
        guard hasSecondGame, secondGameCanUse(key) else {
            return
        }

        setSecondGameInput(key)
    }

    private func setSecondGameInput(_ key: String?) {
        secondGameInput = key
        secondGameRunner.setInput(key)
    }

    /// Whether the games have different inputs to swap. The first game always
    /// has one, so only a keyboard and nothing can't swap.
    var canSwapGamepads: Bool {
        hasSecondGame && !(firstGameUsesKeyboard && secondGameInput == nil)
    }

    /// Swaps the two games' inputs in one step; both games keep running.
    func swapGamepads() {
        guard canSwapGamepads, let assignments = gamepadAssignments else {
            return
        }

        let firstInput = firstGameUsesKeyboard ? EmulatorModel.keyboardKey : assignments.gamepadKey(forPlayer: 0)
        let secondInput = secondGameInput

        setSecondGameInput(nil)
        assignments.assignGamepad(withKey: secondInput == EmulatorModel.keyboardKey ? nil : secondInput, toPlayer: 0)
        setSecondGameInput(firstInput)
        refreshGamepads()
    }

    /// A gamepad no game uses does nothing, so the second game takes the first
    /// free one. The keyboard stays with the first game until it's asked for.
    private func assignSecondGameGamepadIfNeeded() {
        guard hasSecondGame, secondGameInput == nil, let assignments = gamepadAssignments else {
            return
        }

        if let free = assignments.connectedGamepads().first(where: { assignments.player(forGamepadKey: $0.key) < 0 }) {
            setSecondGameInput(free.key)
        }
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

    // MARK: - Save states

    /// Saves the game to a slot the player picks.
    func saveState() {
        guard engine.isRunning() else {
            return
        }

        engine.saveState()
    }

    /// Loads a slot the player picks.
    func loadState() {
        guard engine.isRunning() else {
            return
        }

        engine.loadState()
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
        guard player1CanUse(gamepad?.key) else {
            return
        }

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
            assignSecondGameGamepadIfNeeded()
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
              let free = connected.first(where: { assignments.player(forGamepadKey: $0.key) < 0 && $0.key != secondGameInput }) else {
            refreshGamepads()
            return
        }

        choosePlayer1Gamepad(free)
    }
}
