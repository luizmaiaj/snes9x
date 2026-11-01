/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import Foundation
import XCTest

/// Drives the real game window. These tests take over the mouse and keyboard
/// and quit any running Snes9x, so they have their own scheme, Snes9xUITests,
/// and don't run with the unit tests.
final class GameWindowUITests: XCTestCase {
    /// Each test gets its own saves. The test runner is sandboxed and can't
    /// delete them, so the scheme removes s9x-ui-test-* after the run.
    private let romName = "s9x-ui-test-" + UUID().uuidString
    private var app: XCUIApplication!
    private var folder: URL!

    /// The real folder, not the sandboxed runner's container.
    private var freezes: URL {
        URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir))
            .appendingPathComponent("Library/Application Support/Snes9x/Freezes")
    }

    private var openROMButton: XCUIElement { app.toolbars.buttons["Open ROM"] }
    private var pauseButton: XCUIElement { app.toolbars.buttons["Pause"] }
    private var resumeButton: XCUIElement { app.toolbars.buttons["Resume"] }
    private var saveStateButton: XCUIElement { app.toolbars.buttons["Save State"] }
    private var loadStateButton: XCUIElement { app.toolbars.buttons["Load State"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try FileManager.default.removeItem(at: folder)
    }

    func testSaveStateWritesASlotAndLoadStateKeepsTheGameRunning() throws {
        try startGame()
        XCTAssertEqual(try saves().count, 0)

        saveStateButton.click()
        _ = pressInSlotPicker(.return) { self.hasSave() }
        let saved = NSPredicate { _, _ in self.hasSave() }
        wait(for: [expectation(for: saved, evaluatedWith: nil)], timeout: 10)

        loadStateButton.click()
        _ = pressInSlotPicker(.return) { false }
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(pauseButton.isEnabled)
    }

    func testEscapeLeavesTheSlotPickerWithoutSaving() throws {
        try startGame()

        saveStateButton.click()
        // Esc pauses the game once the picker has closed, which proves it closed.
        XCTAssertTrue(pressInSlotPicker(.escape) { self.resumeButton.waitForExistence(timeout: 1) })
        resumeButton.click()

        // With the picker closed, Return can't save anything.
        _ = pressInSlotPicker(.return) { self.hasSave() }
        XCTAssertEqual(try saves().count, 0)
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(pauseButton.isEnabled)
    }

    func testAFileThatIsNotAROMIsRefusedAndTheGameCarriesOn() throws {
        try startGame()
        let file = folder.appendingPathComponent("not-a-rom.sfc")
        try Data("this is not a rom\n".utf8).write(to: file)

        open(file)

        let alert = app.dialogs.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["“not-a-rom.sfc” can't be opened."].exists)
        alert.buttons["OK"].click()

        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(pauseButton.isEnabled)
    }

    /// Opens a small ROM through the toolbar and waits for it to run.
    private func startGame() throws {
        let rom = folder.appendingPathComponent(romName + ".sfc")
        try makeROM().write(to: rom)

        open(rom)

        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        wait(for: [expectation(for: enabled, evaluatedWith: pauseButton)], timeout: 10)
    }

    /// Picks a file in the panel that Open ROM shows.
    private func open(_ file: URL) {
        XCTAssertTrue(openROMButton.waitForExistence(timeout: 10))
        openROMButton.click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(.return, modifierFlags: [])

        let openButton = app.buttons["OKButton"].firstMatch
        let enabled = NSPredicate(format: "isEnabled == true")
        wait(for: [expectation(for: enabled, evaluatedWith: openButton)], timeout: 10)
        openButton.click()
    }

    /// The slot picker polls for held keys, so it can miss one tap of a
    /// synthesized key. Presses again until `done`, up to five times.
    private func pressInSlotPicker(_ key: XCUIKeyboardKey, until done: () -> Bool) -> Bool {
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.5)
            app.typeKey(key, modifierFlags: [])

            if done() {
                return true
            }
        }

        return false
    }

    private func hasSave() -> Bool {
        ((try? saves().count) ?? 0) > 0
    }

    private func saves() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: freezes.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(at: freezes, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(romName) }
    }

    /// A LoROM image of NOPs with a valid header, so nothing copyrighted is needed.
    private func makeROM() -> Data {
        var rom = Data(repeating: 0xEA, count: 0x80000)
        let header = 0x7FC0
        rom[header + 0x15] = 0x20
        rom[header + 0x17] = 0x09
        rom[header + 0x1C] = 0xCB
        rom[header + 0x1D] = 0xED
        rom[header + 0x1E] = 0x34
        rom[header + 0x1F] = 0x12
        rom[header + 0x3C] = 0x00
        rom[header + 0x3D] = 0x80
        return rom
    }
}
