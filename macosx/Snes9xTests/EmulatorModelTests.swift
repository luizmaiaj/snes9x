/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import AppKit
import XCTest
import snes9x_framework

/// Takes keyboard focus, like S9xView.
final class FakeGameView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// Stands in for S9xEngine: hands out a new 512×478 view with the SNES aspect
/// constraint, as -[S9xEngine recreateS9xView] does.
final class FakeEngine: NSObject, GameEngine, @unchecked Sendable {
    private(set) var viewsMade = 0
    private(set) var resets = 0
    private(set) var saves = 0
    private(set) var loads = 0
    var running = false
    var paused = false
    var muted = false

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

    func saveState() { saves += 1 }
    func loadState() { loads += 1 }
    func setMuted(_ muted: Bool) { self.muted = muted }
}

/// Stands in for the process that runs a second game.
final class FakeSecondGameRunner: SecondGameRunner {
    var view: NSView? = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 478))
    private(set) var started: [URL] = []
    private(set) var stops = 0
    private(set) var onExit: (@MainActor () -> Void)?
    private(set) var onPausedChange: (@MainActor (Bool) -> Void)?
    private(set) var pauseToggles = 0
    private(set) var resets = 0
    private(set) var saves = 0
    private(set) var loads = 0
    private(set) var muted = true
    private(set) var input: String?

    func start(_ url: URL, onPausedChange: @escaping @MainActor (Bool) -> Void, onExit: @escaping @MainActor () -> Void) -> NSView? {
        started.append(url)
        self.onPausedChange = onPausedChange
        self.onExit = onExit
        return view
    }

    func stop() { stops += 1 }
    func togglePause() { pauseToggles += 1 }
    func reset() { resets += 1 }
    func saveState() { saves += 1 }
    func loadState() { loads += 1 }
    func setMuted(_ muted: Bool) { self.muted = muted }
    func setInput(_ key: String?) { input = key }
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

    func testSaveAndLoadStateReachTheEngineWhileAGameRuns() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()

        model.saveState()
        XCTAssertEqual(engine.saves, 1)
        XCTAssertEqual(engine.loads, 0)

        model.loadState()
        XCTAssertEqual(engine.saves, 1)
        XCTAssertEqual(engine.loads, 1)
    }

    func testSaveAndLoadStateWorkWhileAGameIsPaused() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        engine.running = true
        model.reloadGameView()
        model.togglePause()

        model.saveState()
        model.loadState()

        XCTAssertEqual(engine.saves, 1)
        XCTAssertEqual(engine.loads, 1)
    }

    func testSaveAndLoadStateDoNothingWithoutAGame() {
        let engine = FakeEngine()
        let model = EmulatorModel(engine: engine)
        model.reloadGameView()

        model.saveState()
        model.loadState()

        XCTAssertEqual(engine.saves, 0)
        XCTAssertEqual(engine.loads, 0)
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

    func testAtLaunchChoosingTheKeyboardForPlayer1Holds() {
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2]
        let chosenIn = EmulatorModel(engine: FakeEngine())
        chosenIn.gamepadAssignments = assignments
        chosenIn.choosePlayer1Gamepad(nil)

        let relaunched = EmulatorModel(engine: FakeEngine())
        relaunched.gamepadAssignments = assignments
        relaunched.assignPlayer1GamepadIfNeeded()

        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
        XCTAssertNil(relaunched.player1Gamepad)
        XCTAssertEqual(relaunched.gamepads.map(\.key), [pro2.key], "the menu still offers the pad")
    }

    // MARK: Gamepads that connect and disconnect after launch

    func testAGamepadConnectedAfterLaunchBecomesAnUnassignedPlayer1() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        model.gamepadAssignments = assignments
        XCTAssertTrue(model.gamepads.isEmpty)

        assignments.connected = [pro2]
        model.gamepadsDidChange()

        XCTAssertEqual(model.gamepads.map(\.key), [pro2.key])
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, pro2.key)
    }

    func testAGamepadConnectedAfterLaunchKeepsTheOtherPlayerItIsSavedFor() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.keysByPlayer = [1: sn30.key]
        model.gamepadAssignments = assignments

        assignments.connected = [sn30]
        model.gamepadsDidChange()

        XCTAssertNil(assignments.keysByPlayer[0])
        XCTAssertEqual(assignments.keysByPlayer[1], sn30.key)
        XCTAssertEqual(model.gamepads.map(\.key), [sn30.key])
    }

    func testAGamepadConnectedAfterLaunchLeavesAConnectedPlayer1Alone() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: pro2.key]
        model.gamepadAssignments = assignments

        assignments.connected = [pro2, sn30]
        model.gamepadsDidChange()

        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, pro2.key)
        XCTAssertEqual(model.gamepads.count, 2)
    }

    func testAGamepadConnectedAfterLaunchLeavesAPlayer1OnTheKeyboardAlone() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        model.gamepadAssignments = assignments
        model.choosePlayer1Gamepad(nil)

        assignments.connected = [pro2]
        model.gamepadsDidChange()

        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
        XCTAssertNil(model.player1Gamepad)
        XCTAssertEqual(model.gamepads.map(\.key), [pro2.key], "the menu still offers the pad")
    }

    func testPlayer1sGamepadDisconnectingThenReturningKeepsPlayer1() {
        let model = EmulatorModel(engine: FakeEngine())
        let assignments = FakeGamepadAssignments()
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: pro2.key]
        model.gamepadAssignments = assignments

        assignments.connected = [sn30]
        model.gamepadsDidChange()

        XCTAssertEqual(model.gamepads.map(\.key), [sn30.key])
        XCTAssertNil(model.player1Gamepad)
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key, "the other pad must not take Player 1")

        assignments.connected = [pro2, sn30]
        model.gamepadsDidChange()

        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, pro2.key)
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
final class SecondGameModelTests: XCTestCase {
    private let rom = URL(fileURLWithPath: "/roms/second.sfc")

    private func makeModel(running: Bool = true) -> (EmulatorModel, FakeEngine, FakeSecondGameRunner) {
        let engine = FakeEngine()
        engine.running = running
        let model = EmulatorModel(engine: engine)
        let runner = FakeSecondGameRunner()
        model.secondGameRunner = runner
        model.chooseROM = { [rom] in rom }
        model.refreshEmulationState()
        return (model, engine, runner)
    }

    func testOpeningASecondGameShowsItAndLeavesTheFirstRunning() {
        let (model, engine, runner) = makeModel()

        model.openSecondROM()

        XCTAssertEqual(runner.started, [rom])
        XCTAssertIdentical(model.secondGameView, runner.view)
        XCTAssertTrue(model.hasSecondGame)
        XCTAssertTrue(engine.isRunning())
        XCTAssertFalse(engine.isPaused())
        XCTAssertEqual(engine.viewsMade, 0, "the first game's view must not be rebuilt")
    }

    func testASecondGameNeedsAFirstGame() {
        let (model, _, runner) = makeModel(running: false)

        model.openSecondROM()

        XCTAssertTrue(runner.started.isEmpty)
        XCTAssertNil(model.secondGameView)
    }

    func testThereIsOnlyOneSecondGame() {
        let (model, _, runner) = makeModel()

        model.openSecondROM()
        model.openSecondROM()

        XCTAssertEqual(runner.started.count, 1)
    }

    func testCancellingTheOpenPanelStartsNothing() {
        let (model, _, runner) = makeModel()
        model.chooseROM = { nil }

        model.openSecondROM()

        XCTAssertTrue(runner.started.isEmpty)
    }

    func testAFileThatCantStartIsReportedAndShowsNothing() {
        let (model, _, runner) = makeModel()
        runner.view = nil
        var refused: [URL] = []
        model.cantOpenHandler = { refused.append($0) }

        model.openSecondROM()

        XCTAssertEqual(refused, [rom])
        XCTAssertFalse(model.hasSecondGame)
    }

    func testClosingStopsTheSecondGameAndKeepsTheFirst() {
        let (model, engine, runner) = makeModel()
        model.openSecondROM()

        model.closeSecondGame()

        XCTAssertEqual(runner.stops, 1)
        XCTAssertNil(model.secondGameView)
        XCTAssertTrue(engine.isRunning())
    }

    func testClosingWithNoSecondGameDoesNothing() {
        let (model, _, runner) = makeModel()

        model.closeSecondGame()

        XCTAssertEqual(runner.stops, 0)
    }

    func testASecondGameThatEndsOnItsOwnLeavesTheView() throws {
        let (model, _, runner) = makeModel()
        model.openSecondROM()

        try XCTUnwrap(runner.onExit)()

        XCTAssertNil(model.secondGameView)
    }
}

final class FrameChannelTests: XCTestCase {
    private func pixels(_ value: UInt8, width: Int, height: Int) -> [UInt8] {
        [UInt8](repeating: value, count: width * height * 4)
    }

    private func channels() throws -> (writer: S9xFrameChannel, reader: S9xFrameChannel) {
        let reader = try XCTUnwrap(S9xFrameChannel.create())
        let writer = try XCTUnwrap(S9xFrameChannel.open(withName: reader.name))
        return (writer, reader)
    }

    func testAFrameReachesTheOtherEnd() throws {
        let (writer, reader) = try channels()

        XCTAssertTrue(writer.writeFrame(pixels(200, width: 256, height: 224), width: 256, height: 224))

        let image = try XCTUnwrap(reader.copyNewestImage())
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 224)
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertEqual(bytes[0], 200)
        XCTAssertEqual(bytes[256 * 224 * 4 - 1], 200)
    }

    func testNoFrameYetGivesNothing() throws {
        XCTAssertNil(try channels().reader.copyNewestImage())
    }

    func testAFrameIsReadOnce() throws {
        let (writer, reader) = try channels()
        writer.writeFrame(pixels(1, width: 2, height: 2), width: 2, height: 2)

        XCTAssertNotNil(reader.copyNewestImage())
        XCTAssertNil(reader.copyNewestImage())
    }

    func testTheNewestFrameWins() throws {
        let (writer, reader) = try channels()
        for value: UInt8 in [10, 20, 30] {
            writer.writeFrame(pixels(value, width: 2, height: 2), width: 2, height: 2)
        }

        let image = try XCTUnwrap(reader.copyNewestImage())
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertEqual(bytes[0], 30)
    }

    func testTheLargestSNESFrameFitsAndALargerOneIsRefused() throws {
        let (writer, reader) = try channels()

        XCTAssertTrue(writer.writeFrame(pixels(1, width: 512, height: 478), width: 512, height: 478))
        XCTAssertFalse(writer.writeFrame(pixels(2, width: 513, height: 478), width: 513, height: 478))
        XCTAssertFalse(writer.writeFrame(pixels(2, width: 512, height: 479), width: 512, height: 479))
        XCTAssertFalse(writer.writeFrame(pixels(2, width: 2, height: 2), width: 0, height: 2))
        XCTAssertEqual(reader.copyNewestImage()?.width, 512)
    }

    func testAChannelThatDoesNotExistCantBeOpened() {
        XCTAssertNil(S9xFrameChannel.open(withName: "/s9x-no-such-channel"))
    }

    func testEachNewChannelHasItsOwnNameThatFitsTheSystemLimit() throws {
        let first = try XCTUnwrap(S9xFrameChannel.create())
        let second = try XCTUnwrap(S9xFrameChannel.create())

        XCTAssertNotEqual(first.name, second.name)
        XCTAssertLessThanOrEqual(first.name.utf8.count, 31)
    }

    func testTheNameIsGoneWithTheChannel() throws {
        var channel: S9xFrameChannel? = try XCTUnwrap(S9xFrameChannel.create())
        let name = try XCTUnwrap(channel?.name)

        channel = nil

        XCTAssertNil(S9xFrameChannel.open(withName: name))
    }
}

final class SecondGameSaveTests: XCTestCase {
    func testASecondGameSavesBesideTheFirstInItsOwnFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = folder.appendingPathComponent("Super Mario World (USA).srm").path
        let second: String = try XCTUnwrap(S9xEngine.secondGameSavePath(first))

        XCTAssertNotEqual(second, first)
        XCTAssertEqual(second, folder.appendingPathComponent("Second Game/Super Mario World (USA).srm").path)

        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: (second as NSString).deletingLastPathComponent, isDirectory: &isFolder))
        XCTAssertTrue(isFolder.boolValue)
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

    func testTwoGamesShareTheContainerInEqualHalves() {
        let engine = FakeEngine()
        let container = GameContainerView(frame: NSRect(x: 0, y: 0, width: 1072, height: 544))
        let first = engine.makeGameView()
        let second = NSView()

        container.show(first)
        container.showSecondGame(second)
        container.layout()

        XCTAssertEqual(first.frame, NSRect(x: 0, y: 0, width: 536, height: 544))
        XCTAssertEqual(second.frame, NSRect(x: 536, y: 0, width: 536, height: 544))
    }

    func testEachOfTwoGamesLooksLikeOneGameAlone() {
        let engine = FakeEngine()
        let alone = GameContainerView(frame: NSRect(x: 0, y: 0, width: 536, height: 544))
        let one = engine.makeGameView()
        alone.show(one)
        alone.layout()

        let shared = GameContainerView(frame: NSRect(x: 0, y: 0, width: 1072, height: 544))
        let first = engine.makeGameView()
        shared.show(first)
        shared.showSecondGame(NSView())
        shared.layout()

        XCTAssertEqual(first.frame, one.frame)
    }

    func testTheWindowDoublesForASecondGameAndGoesBackAfter() {
        let window = makeWindow()
        window.setFrame(NSRect(x: 40, y: 40, width: 536, height: 544), display: false)
        let engine = FakeEngine()
        let container = GameContainerView(frame: NSRect(x: 0, y: 0, width: 536, height: 544))
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        container.show(engine.makeGameView())
        let before = window.frame

        container.showSecondGame(NSView())

        XCTAssertEqual(window.frame.width, min(before.width * 2, window.screen?.visibleFrame.width ?? 1072))
        XCTAssertEqual(window.frame.height, before.height)

        container.showSecondGame(nil)

        XCTAssertEqual(window.frame, before)
        XCTAssertEqual(container.subviews.count, 1)
    }

    func testANarrowSavedWindowGrowsInProportionFromTheTopLeft() {
        let window = makeWindow()
        window.setFrame(NSRect(x: 100, y: 100, width: 512, height: 520), display: false)

        GameWindowHosting.applyMinimumWidth(to: window)

        XCTAssertEqual(window.frame.width, 536)
        XCTAssertEqual(window.frame.height, 520.0 * 536.0 / 512.0, accuracy: 1)
        XCTAssertEqual(window.frame.minX, 100)
        XCTAssertEqual(window.frame.maxY, 620, accuracy: 1)
        XCTAssertEqual(window.minSize.width, 536)
    }

    func testAWideEnoughSavedWindowIsLeftAlone() {
        let window = makeWindow()
        let frame = NSRect(x: 100, y: 100, width: 800, height: 700)
        window.setFrame(frame, display: false)

        GameWindowHosting.applyMinimumWidth(to: window)

        XCTAssertEqual(window.frame, frame)
    }

    func testTheSecondROMButtonSitsAfterOpenROMWithATooltip() throws {
        let window = makeWindow()
        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))

        let item = try XCTUnwrap(toolbarItem(labelled: "Open Second ROM", in: window), "items: \(toolbarLabels(in: window))")
        let labels = toolbarLabels(in: window)

        XCTAssertEqual(labels.firstIndex(of: "Open Second ROM"), try XCTUnwrap(labels.firstIndex(of: "Open ROM")) + 1)
        XCTAssertEqual(item.toolTip, "Open a ROM beside the running game. It starts muted.")
    }

    func testOneGameShowsNoneOfTheSecondGamesButtons() {
        let window = makeWindow()
        GameWindowHosting.install(in: window, model: EmulatorModel(engine: FakeEngine()))

        let labels = toolbarLabels(in: window)

        XCTAssertFalse(labels.contains("Swap Sound"), "items: \(labels)")
        XCTAssertFalse(labels.contains("Swap Gamepads"), "items: \(labels)")
        XCTAssertFalse(labels.contains("Pause Game 2"), "items: \(labels)")
    }

    func testTwoGamesShowEachGamesOwnButtons() throws {
        let engine = FakeEngine()
        engine.running = true
        let model = EmulatorModel(engine: engine)
        model.secondGameRunner = FakeSecondGameRunner()
        model.refreshEmulationState()
        model.openSecondGame(URL(fileURLWithPath: "/roms/two.smc"))
        let window = makeWindow()
        GameWindowHosting.install(in: window, model: model)

        let labels = toolbarLabels(in: window)

        for label in ["Pause", "Reset", "Save State", "Load State", "Swap Sound", "Swap Gamepads", "Pause Game 2", "Reset Game 2", "Save State Game 2", "Load State Game 2"] {
            XCTAssertTrue(labels.contains(label), "\(label) missing from \(labels)")
        }
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

@MainActor
final class SecondGameControlsTests: XCTestCase {
    private var engine: FakeEngine!
    private var runner: FakeSecondGameRunner!
    private var assignments: FakeGamepadAssignments!
    private var model: EmulatorModel!

    override func setUp() {
        super.setUp()
        engine = FakeEngine()
        engine.running = true
        runner = FakeSecondGameRunner()
        assignments = FakeGamepadAssignments()
        model = EmulatorModel(engine: engine)
        model.secondGameRunner = runner
        model.gamepadAssignments = assignments
        model.refreshEmulationState()
    }

    private func openSecondGame() {
        model.openSecondGame(URL(fileURLWithPath: "/roms/two.smc"))
    }

    func testSecondGameTakesAFreeGamepadAndLeavesTheFirstGamesAlone() {
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()

        openSecondGame()

        XCTAssertEqual(model.secondGameInput, sn30.key)
        XCTAssertEqual(runner.input, sn30.key)
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
    }

    func testWithNoFreeGamepadTheSecondGameHasNoInput() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()

        openSecondGame()

        XCTAssertNil(model.secondGameInput)
        XCTAssertNil(runner.input)
    }

    func testAGamepadInUseByOneGameCantBeChosenForTheOther() {
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()
        openSecondGame()

        XCTAssertFalse(model.secondGameCanUse(pro2.key))
        model.chooseSecondGameInput(pro2.key)
        XCTAssertEqual(model.secondGameInput, sn30.key)

        XCTAssertFalse(model.player1CanUse(sn30.key))
        model.choosePlayer1Gamepad(sn30)
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
    }

    func testTheKeyboardBelongsToOneGame() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: "0:0:0"]
        model.refreshGamepads()
        openSecondGame()
        model.chooseSecondGameInput(nil)

        // Player 1 is on the keyboard, so the second game can't have it.
        XCTAssertFalse(model.secondGameCanUse(EmulatorModel.keyboardKey))
        model.chooseSecondGameInput(EmulatorModel.keyboardKey)
        XCTAssertNil(model.secondGameInput)

        // With Player 1 on a pad it's free, and Player 1 can't go back to it.
        model.choosePlayer1Gamepad(pro2)
        model.chooseSecondGameInput(EmulatorModel.keyboardKey)
        XCTAssertEqual(runner.input, EmulatorModel.keyboardKey)
        XCTAssertFalse(model.player1CanUse(nil))
        model.choosePlayer1Gamepad(nil)
        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
    }

    func testSwapGamepadsSwapsBothGamesInOneStep() {
        assignments.connected = [pro2, sn30]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()
        openSecondGame()

        model.swapGamepads()

        XCTAssertEqual(assignments.keysByPlayer[0], sn30.key)
        XCTAssertEqual(runner.input, pro2.key)
        XCTAssertEqual(model.player1Gamepad?.key, sn30.key)
        XCTAssertEqual(runner.stops, 0)
    }

    func testSwapGamepadsMovesTheKeyboardToo() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()
        openSecondGame()
        model.chooseSecondGameInput(EmulatorModel.keyboardKey)

        model.swapGamepads()

        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
        XCTAssertEqual(runner.input, pro2.key)

        model.swapGamepads()

        XCTAssertEqual(assignments.keysByPlayer[0], pro2.key)
        XCTAssertEqual(runner.input, EmulatorModel.keyboardKey)
    }

    func testAGamepadSwapsIntoASecondGameWithNoInput() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: pro2.key]
        model.refreshGamepads()
        openSecondGame()
        XCTAssertTrue(model.canSwapGamepads)

        model.swapGamepads()

        XCTAssertEqual(runner.input, pro2.key)
        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
    }

    func testNothingToSwapWhenOnlyTheKeyboardIsInUse() {
        assignments.keysByPlayer = [0: "0:0:0"]
        openSecondGame()

        XCTAssertFalse(model.canSwapGamepads)
        model.swapGamepads()
        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
    }

    func testAGamepadThatDisconnectsStaysTheSecondGamesAndAFreeOneJoins() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: "0:0:0"]
        model.refreshGamepads()
        openSecondGame()
        XCTAssertEqual(model.secondGameInput, pro2.key)

        assignments.connected = []
        model.gamepadsDidChange()
        XCTAssertEqual(model.secondGameInput, pro2.key)
        XCTAssertTrue(engine.isRunning())

        assignments.connected = [pro2]
        model.gamepadsDidChange()
        XCTAssertEqual(model.secondGameInput, pro2.key)
        XCTAssertEqual(assignments.keysByPlayer[0], "0:0:0")
    }

    func testAPlayer1WithoutAGamepadDoesntTakeTheSecondGames() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [:]
        model.refreshGamepads()
        openSecondGame()
        XCTAssertEqual(model.secondGameInput, pro2.key)

        model.assignPlayer1GamepadIfNeeded()

        XCTAssertNil(assignments.keysByPlayer[0])
    }

    func testOnlyOneGameHasTheSound() {
        openSecondGame()
        XCTAssertFalse(engine.muted)
        XCTAssertTrue(runner.muted)

        model.swapSound()
        XCTAssertTrue(model.secondGameHasSound)
        XCTAssertTrue(engine.muted)
        XCTAssertFalse(runner.muted)

        model.swapSound()
        XCTAssertFalse(engine.muted)
        XCTAssertTrue(runner.muted)
    }

    func testClosingTheSecondGameGivesTheFirstItsSoundBack() {
        openSecondGame()
        model.swapSound()

        model.closeSecondGame()

        XCTAssertFalse(engine.muted)
        XCTAssertFalse(model.secondGameHasSound)
    }

    func testASecondGameThatEndsGivesBackTheSoundAndItsPad() {
        assignments.connected = [pro2]
        assignments.keysByPlayer = [0: "0:0:0"]
        model.refreshGamepads()
        openSecondGame()
        model.swapSound()

        runner.onExit?()

        XCTAssertFalse(engine.muted)
        XCTAssertNil(model.secondGameInput)
        XCTAssertFalse(model.hasSecondGame)
    }

    func testEachButtonReachesTheSecondGameAloneAndTheFirstGameCarriesOn() {
        openSecondGame()

        model.toggleSecondGamePause()
        model.saveSecondGameState()
        model.loadSecondGameState()

        XCTAssertEqual(runner.pauseToggles, 1)
        XCTAssertEqual(runner.saves, 1)
        XCTAssertEqual(runner.loads, 1)
        XCTAssertFalse(engine.isPaused())
        XCTAssertEqual(engine.saves, 0)
        XCTAssertEqual(engine.loads, 0)
    }

    func testTheFirstGamesButtonsLeaveTheSecondGameAlone() {
        openSecondGame()

        model.togglePause()
        model.saveState()

        XCTAssertTrue(engine.isPaused())
        XCTAssertEqual(engine.saves, 1)
        XCTAssertEqual(runner.pauseToggles, 0)
        XCTAssertEqual(runner.saves, 0)
    }

    func testResetOnlyRestartsAPausedSecondGame() {
        openSecondGame()

        model.resetSecondGame()
        XCTAssertEqual(runner.resets, 0)

        runner.onPausedChange?(true)
        XCTAssertTrue(model.isSecondGamePaused)

        model.resetSecondGame()
        XCTAssertEqual(runner.resets, 1)
        XCTAssertEqual(engine.resets, 0)
    }
}

final class SecondGameInputTests: XCTestCase {
    func testButtonsAndKeysCrossTheChannel() throws {
        let window = try XCTUnwrap(S9xFrameChannel.create())
        let game = try XCTUnwrap(S9xFrameChannel.open(withName: window.name))

        window.setGamepadButton(3, pressed: true)
        window.setGamepadButton(9, pressed: true)
        window.setGamepadButton(3, pressed: false)
        window.setKeyButton(4, player: 1, pressed: true)
        window.setRawKey(53, pressed: true)
        window.setRawKey(200, pressed: true)

        // The arrays CopyPressedKeys fills: 8 players by 29 buttons.
        let buttons = 29
        var keys = [UInt8](repeating: 0, count: 8 * buttons)
        var pads = [UInt8](repeating: 0, count: 8 * buttons)

        keys.withUnsafeMutableBytes { keysBytes in
            pads.withUnsafeMutableBytes { padsBytes in
                func rows<T>(_ bytes: UnsafeMutableRawBufferPointer) -> UnsafeMutablePointer<T> {
                    bytes.baseAddress!.assumingMemoryBound(to: T.self)
                }

                game.addKeys(rows(keysBytes), gamepadButtons: rows(padsBytes))
            }
        }

        XCTAssertEqual(pads[9], 1, "the pad drives the game's Player 1")
        XCTAssertEqual(pads[3], 0, "a released button stops")
        XCTAssertEqual(keys[buttons + 4], 1, "keys stay with their player")
        XCTAssertEqual(keys.reduce(0, +) + pads.reduce(0, +), 2)

        var raw = [UInt8](repeating: 0, count: 255)
        raw.withUnsafeMutableBufferPointer { game.copyRawKeys($0.baseAddress!) }
        XCTAssertEqual(raw[53], 1)
        XCTAssertEqual(raw[200], 1)
        XCTAssertEqual(raw[54], 0)

        window.releaseKeyboard()
        raw.withUnsafeMutableBufferPointer { game.copyRawKeys($0.baseAddress!) }
        XCTAssertEqual(raw[53], 0)
    }

    func testRequestsArriveOnceAndSoundStartsOff() throws {
        let window = try XCTUnwrap(S9xFrameChannel.create())
        let game = try XCTUnwrap(S9xFrameChannel.open(withName: window.name))

        XCTAssertTrue(game.isMuted)
        window.isMuted = false
        XCTAssertFalse(game.isMuted)

        window.add(.reset)
        window.add(.saveState)
        XCTAssertEqual(game.takeRequests(), [.reset, .saveState])
        XCTAssertEqual(game.takeRequests(), [])

        game.isPaused = true
        XCTAssertTrue(window.isPaused)
    }
}
