/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import AppKit
import XCTest

/// Takes keyboard focus, like S9xView.
final class FakeGameView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// Stands in for S9xEngine: hands out a new 512×478 view with the SNES aspect
/// constraint, as -[S9xEngine recreateS9xView] does.
final class FakeEngine: NSObject, GameEngine, @unchecked Sendable {
    private(set) var viewsMade = 0
    private(set) var resets = 0
    var running = false
    var paused = false

    func makeGameView() -> NSView {
        viewsMade += 1
        let view = FakeGameView(frame: NSRect(x: 0, y: 0, width: 512, height: 478))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 478.0 / 512.0).isActive = true
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 512).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 478).isActive = true
        return view
    }

    // Like S9xEngine: paused only while running.
    func isRunning() -> Bool { running }
    func isPaused() -> Bool { running && paused }
    func pause() { paused = true }
    func resume() { paused = false }

    // Like -[S9xEngine softwareReset], which resumes the game.
    func softwareReset() {
        resets += 1
        paused = false
    }
}

/// Stands in for the app delegate's player assignments in the preferences.
final class FakeGamepadAssignments: NSObject, GamepadAssignments {
    var connected: [Gamepad] = []
    var keysByPlayer: [Int: String] = [:]

    func connectedGamepads() -> [Gamepad] { connected }
    func gamepadKey(forPlayer player: Int) -> String? { keysByPlayer[player] }

    func player(forGamepadKey key: String) -> Int {
        keysByPlayer.first { $0.value == key }?.key ?? -1
    }

    func assignGamepad(withKey key: String?, toPlayer player: Int) {
        keysByPlayer[player] = key ?? "0:0:0"
    }
}

let pro2 = Gamepad(key: "11720:24582:0", name: "8BitDo Pro 2")
let sn30 = Gamepad(key: "11720:12345:0", name: "8BitDo SN30")

@MainActor
final class EmulatorModelTests: XCTestCase {
    func testReloadGameViewPublishesAFreshEngineView() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)

        model.reloadGameView()
        let first = model.gameView
        model.reloadGameView()

        XCTAssertEqual(engine.viewsMade, 2)
        XCTAssertNotNil(model.gameView)
        XCTAssertFalse(model.gameView === first)
    }

    func testOpenROMLoadsTheChosenFile() {
        let model = EmulatorModel(engine: FakeEngine())
        let rom = URL(fileURLWithPath: "/tmp/Super Mario World (USA).zip")
        var opened: [URL] = []
        model.chooseROM = { rom }
        model.openHandler = { url in
            opened.append(url)
            return true
        }

        XCTAssertTrue(model.openROM())
        XCTAssertEqual(opened, [rom])
    }

    func testCancellingTheOpenPanelLoadsNothing() {
        let model = EmulatorModel(engine: FakeEngine())
        var opened: [URL] = []
        model.chooseROM = { nil }
        model.openHandler = { url in
            opened.append(url)
            return true
        }

        XCTAssertFalse(model.openROM())
        XCTAssertEqual(opened, [])
    }

    func testAFileThatDoesNotLoadIsReportedAndKeepsTheCurrentView() {
        let model = EmulatorModel(engine: FakeEngine())
        model.reloadGameView()
        let current = model.gameView
        model.chooseROM = { URL(fileURLWithPath: "/tmp/notes.txt") }
        model.openHandler = { _ in false }

        XCTAssertFalse(model.openROM())
        XCTAssertTrue(model.gameView === current)
    }

    // MARK: Pause and reset (#5)

    func testPauseAndResumeTheRunningGame() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()
        XCTAssertTrue(model.isRunning)
        XCTAssertFalse(model.isPaused)

        model.togglePause()
        XCTAssertTrue(engine.paused)
        XCTAssertTrue(model.isPaused)

        model.togglePause()
        XCTAssertFalse(engine.paused)
        XCTAssertFalse(model.isPaused)
    }

    func testPauseDoesNothingWithoutAGame() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)

        model.togglePause()

        XCTAssertFalse(engine.paused)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isPaused)
    }

    func testResetOnlyRestartsAPausedGameAndResumesIt() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()

        model.reset()
        XCTAssertEqual(engine.resets, 0, "reset while running")

        model.togglePause()
        model.reset()
        XCTAssertEqual(engine.resets, 1)
        XCTAssertFalse(model.isPaused)
    }

    func testAPauseFromTheEmulationThreadReachesTheModel() {
        // Esc pauses on the emulation thread, which then tells the delegate.
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()

        let reported = expectation(description: "state change reported")
        DispatchQueue.global().async {
            engine.paused = true
            model.engineStateDidChange()
            reported.fulfill()
        }
        wait(for: [reported], timeout: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(model.isPaused)
    }

    // MARK: Player 1's gamepad (#6)

    func testPlayer1ShowsItsGamepadOrTheKeyboard() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: sn30.key]

        model.gamepadAssignments = assignments
        XCTAssertEqual(model.gamepads.map(\.key), [pro2.key, sn30.key])
        XCTAssertEqual(model.player1Gamepad?.name, "8BitDo SN30")

        assignments.keysByPlayer = [0: "0:0:0"]
        model.refreshGamepads()
        XCTAssertNil(model.player1Gamepad)
    }

    func testChoosingAGamepadMakesItPlayer1AndKeyboardRemovesIt() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        model.gamepadAssignments = assignments

        model.choosePlayer1Gamepad(pro2)
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, pro2.key)

        model.choosePlayer1Gamepad(nil)
        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
        XCTAssertNil(model.player1Gamepad)
    }

    func testAtLaunchAnUnassignedPlayer1GetsTheFirstConnectedGamepad() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        model.gamepadAssignments = assignments

        model.assignPlayer1GamepadIfNeeded()

        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, pro2.key)
    }

    func testAtLaunchAPlayer1GamepadThatIsNotConnectedIsReplaced() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [sn30]
        assignments.keysByPlayer = [0: pro2.key]
        model.gamepadAssignments = assignments

        model.assignPlayer1GamepadIfNeeded()

        XCTAssertEqual(assignments.keysByPlayer[0], sn30.key)
    }

    func testAtLaunchAConnectedPlayer1GamepadIsKept() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: sn30.key]
        model.gamepadAssignments = assignments

        model.assignPlayer1GamepadIfNeeded()

        XCTAssertEqual(assignments.keysByPlayer[0], sn30.key)
    }

    func testAtLaunchAGamepadAnotherPlayerUsesIsNeverTaken() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [1: pro2.key]
        model.gamepadAssignments = assignments

        model.assignPlayer1GamepadIfNeeded()
        XCTAssertEqual(assignments.keysByPlayer[0], sn30.key)

        assignments.connected = [pro2]
        assignments.keysByPlayer = [1: pro2.key]
        model.assignPlayer1GamepadIfNeeded()
        XCTAssertNil(assignments.keysByPlayer[0])
        XCTAssertEqual(assignments.keysByPlayer[1], pro2.key)
    }

    // MARK: No needless updates (an open toolbar menu closes on any update)

    private func changesPublished(by model: EmulatorModel, during action: () -> Void) -> Int {
        var count = 0
        let subscription = model.objectWillChange.sink { count += 1 }
        action()
        subscription.cancel()
        return count
    }

    func testRefreshingUnchangedGamepadsPublishesNothing() {
        // Player 1 on the keyboard ("0:0:0"), on a pad that is off, and on a
        // connected pad: the toolbar must not redraw while nothing changed.
        for player1Key in ["0:0:0", "11720:99999:0", sn30.key] {
            let model = EmulatorModel(engine: FakeEngine())
            let assignments = FakeGamepadAssignments()
            assignments.connected = [pro2, sn30]
            assignments.keysByPlayer = [0: player1Key]
            model.gamepadAssignments = assignments

            let published = changesPublished(by: model) {
                model.refreshGamepads()
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }

            XCTAssertEqual(published, 0, "Player 1 on \(player1Key)")
        }
    }

    func testRefreshingAnUnchangedGamePublishesNothing() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()

        let published = changesPublished(by: model) {
            model.refreshEmulationState()
            model.engineStateDidChange()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertEqual(published, 0)
    }
}

@MainActor
final class GameWindowTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 478),
                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                 backing: .buffered, defer: false)
    }

    func testContainerSwapsInTheNewGameViewAndDropsTheOldOne() {
        let engine = FakeEngine()
        let container = GameContainerView(frame: NSRect(x: 0, y: 0, width: 512, height: 478))
        let old = engine.makeGameView()
        let new = engine.makeGameView()

        container.show(old)
        container.show(new)

        XCTAssertEqual(container.subviews, [new])
        XCTAssertNil(old.superview)
        XCTAssertEqual(container.minimumSize, NSSize(width: 512, height: 478))
    }

    func testGameFillsTheHeightCentredWithTheSNESAspectRatio() {
        let container = GameContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 478))
        let view = FakeEngine().makeGameView()

        container.show(view)
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.frame.height, 478, accuracy: 0.5)
        XCTAssertEqual(view.frame.width, 512, accuracy: 0.5)
        XCTAssertEqual(view.frame.midX, 400, accuracy: 0.5)
    }

    func testGameFillsAWindowShorterThanTheMinimumWithNoBlackBand() {
        // A saved 512×480 window frame leaves 452 pt of content without a
        // toolbar and 440 pt with one; the game filled it edge to edge before.
        for height in [480.0, 452.0, 440.0] {
            let container = GameContainerView(frame: NSRect(x: 0, y: 0, width: 512, height: height))
            let view = FakeEngine().makeGameView()

            container.show(view)
            container.layoutSubtreeIfNeeded()

            XCTAssertEqual(view.frame, container.bounds, "content height \(height)")
        }
    }

    func testInstallingKeepsTheWindowFrame() {
        let window = makeWindow()
        let before = window.frame

        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))

        XCTAssertEqual(window.frame, before)
    }

    func testTheToolbarHasAnOpaqueBackground() throws {
        // The toolbar draws the window background behind its buttons, so a
        // clear window shows the desktop through the toolbar.
        let window = makeWindow()
        window.backgroundColor = .clear

        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))

        let background = try XCTUnwrap(window.backgroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(background.alphaComponent, 1)
    }

    func testTheToolbarHidesInFullScreenUntilThePointerReachesTheTop() throws {
        let window = makeWindow()
        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))
        // What AppKit proposes for a window entering full screen.
        let proposed: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]

        let delegate = try XCTUnwrap(window.delegate, "the game window has no delegate")
        let options = try XCTUnwrap(delegate.window?(window, willUseFullScreenPresentationOptions: proposed))

        XCTAssertTrue(options.contains(.autoHideToolbar))
        XCTAssertTrue(options.isSuperset(of: proposed))
    }

    private func toolbarItem(labelled label: String, in window: NSWindow) -> NSToolbarItem? {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return window.toolbar?.items.first { $0.label == label }
    }

    private func openROMItem(in window: NSWindow) -> NSToolbarItem? {
        toolbarItem(labelled: "Open ROM", in: window)
    }

    private func toolbarLabels(in window: NSWindow) -> [String] {
        window.toolbar?.items.map(\.label) ?? []
    }

    /// Runs a toolbar item's action through its menu form, as the overflow
    /// menu does; SwiftUI draws the button itself.
    private func click(_ item: NSToolbarItem) throws {
        let menuItem = try XCTUnwrap(item.menuFormRepresentation, "\(item.label) has no menu form")
        let action = try XCTUnwrap(menuItem.action)
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: menuItem.target ?? menuItem, from: menuItem))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    func testThePauseButtonPausesAndResumesTheGame() throws {
        let window = makeWindow()
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        GameWindowHosting.install(in: window, model: model)
        model.reloadGameView()

        let pause = try XCTUnwrap(toolbarItem(labelled: "Pause", in: window), "no Pause item in \(toolbarLabels(in: window))")
        XCTAssertEqual(pause.toolTip, "Pause the game")
        try click(pause)
        XCTAssertTrue(engine.paused)

        let resume = try XCTUnwrap(toolbarItem(labelled: "Resume", in: window), "no Resume item in \(toolbarLabels(in: window))")
        XCTAssertEqual(resume.toolTip, "Resume the game")
        try click(resume)
        XCTAssertFalse(engine.paused)
    }

    func testTheResetButtonRestartsAPausedGame() throws {
        let window = makeWindow()
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        engine.paused = true
        GameWindowHosting.install(in: window, model: model)
        model.reloadGameView()

        let reset = try XCTUnwrap(toolbarItem(labelled: "Reset", in: window), "no Reset item in \(toolbarLabels(in: window))")
        try click(reset)

        XCTAssertEqual(engine.resets, 1)
    }

    func testThePlayer1MenuNamesPlayer1sGamepad() throws {
        let window = makeWindow()
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        model.gamepadAssignments = assignments
        GameWindowHosting.install(in: window, model: model)

        let keyboard = try XCTUnwrap(toolbarItem(labelled: "Player 1: Keyboard", in: window), "toolbar: \(toolbarLabels(in: window))")
        XCTAssertEqual(keyboard.toolTip, "Player 1: Keyboard. Choose the gamepad that controls Player 1.")

        model.choosePlayer1Gamepad(pro2)

        let item = try XCTUnwrap(toolbarItem(labelled: "Player 1: 8BitDo Pro 2", in: window), "toolbar: \(toolbarLabels(in: window))")
        XCTAssertEqual(item.toolTip, "Player 1: 8BitDo Pro 2. Choose the gamepad that controls Player 1.")
    }

    func testTheWindowToolbarHasAnOpenROMButtonWithATooltip() throws {
        let window = makeWindow()
        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))

        let item = try XCTUnwrap(openROMItem(in: window), "no Open ROM item in \(window.toolbar?.items.map(\.label) ?? [])")

        XCTAssertEqual(item.toolTip, "Open a ROM file and start the game")
    }

    func testOpenROMToolbarItemRunsTheSameOpenFlowAsTheMenu() throws {
        let window = makeWindow()
        let model = EmulatorModel(engine: FakeEngine())
        let rom = URL(fileURLWithPath: "/tmp/Super Mario World (USA).zip")
        var opened: [URL] = []
        model.chooseROM = { rom }
        model.openHandler = { url in
            opened.append(url)
            return true
        }
        GameWindowHosting.install(in: window, model: model)
        let item = try XCTUnwrap(openROMItem(in: window))

        // SwiftUI draws the button itself; its menu form (shown when the
        // toolbar overflows) runs the same SwiftUI action.
        let menuItem = try XCTUnwrap(item.menuFormRepresentation)
        let action = try XCTUnwrap(menuItem.action)
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: menuItem.target ?? menuItem, from: menuItem))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(opened, [rom])
    }

    func testReloadedGameViewIsInTheWindowStraightAway() {
        // The engine makes the new view first responder right after loading a
        // ROM, so it has to be in the window before SwiftUI's next update.
        let window = makeWindow()
        let model = EmulatorModel(engine: FakeEngine())
        GameWindowHosting.install(in: window, model: model)
        window.contentView?.layoutSubtreeIfNeeded()

        model.reloadGameView()

        XCTAssertTrue(model.gameView?.window === window)
        XCTAssertTrue(window.makeFirstResponder(model.gameView))
    }
}
