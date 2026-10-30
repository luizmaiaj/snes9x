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
final class FakeEngine: NSObject, GameEngine {
    private(set) var viewsMade = 0

    func makeGameView() -> NSView {
        viewsMade += 1
        let view = FakeGameView(frame: NSRect(x: 0, y: 0, width: 512, height: 478))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 478.0 / 512.0).isActive = true
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 512).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 478).isActive = true
        return view
    }
}

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

    private func openROMItem(in window: NSWindow) -> NSToolbarItem? {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return window.toolbar?.items.first { $0.label == "Open ROM" }
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
