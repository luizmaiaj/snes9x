/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

import Foundation
import snes9x_framework
import XCTest

/// Builds a ROM image with a header at `offset`, as a dump of a cartridge has.
private func makeROM(size: Int, headerAt offset: Int, mapMode: UInt8, checksum: UInt16? = 0x1234) -> Data {
    var rom = Data(repeating: 0xEA, count: size)
    rom[offset + 0x15] = mapMode
    rom[offset + 0x17] = 0x09

    if let checksum {
        let complement = ~checksum
        rom[offset + 0x1C] = UInt8(complement & 0xFF)
        rom[offset + 0x1D] = UInt8(complement >> 8)
        rom[offset + 0x1E] = UInt8(checksum & 0xFF)
        rom[offset + 0x1F] = UInt8(checksum >> 8)
    } else {
        rom[offset + 0x1C..<offset + 0x20] = Data(repeating: 0, count: 4)
    }

    rom[offset + 0x3C] = 0x00
    rom[offset + 0x3D] = 0x80
    return rom
}

/// The same bytes every run, with no ROM header in them.
private func noise(size: Int) -> Data {
    var state: UInt32 = 0x1234_5678

    return Data((0..<size).map { _ in
        state = state &* 1_664_525 &+ 1_013_904_223
        return UInt8(state >> 24)
    })
}

final class ROMFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func zip(_ files: [URL], as name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-j", url.path] + files.map(\.path)
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)
        return url
    }

    // MARK: - Files that aren't ROMs

    func testAShortTextFileIsNotAROM() throws {
        XCTAssertFalse(S9xEngine.looksLikeROM(try write(Data("not a rom".utf8), as: "notarom.sfc")))
    }

    func testALongTextFileIsNotAROM() throws {
        let text = Data(repeating: UInt8(ascii: "a"), count: 0x80000)
        XCTAssertFalse(S9xEngine.looksLikeROM(try write(text, as: "notes.txt")))
    }

    func testAnImageIsNotAROM() throws {
        XCTAssertFalse(S9xEngine.looksLikeROM(try write(noise(size: 325_000), as: "photo.png")))
    }

    func testAnEmptyFileIsNotAROM() throws {
        XCTAssertFalse(S9xEngine.looksLikeROM(try write(Data(), as: "empty.sfc")))
    }

    func testAMissingFileIsNotAROM() {
        XCTAssertFalse(S9xEngine.looksLikeROM(folder.appendingPathComponent("missing.sfc")))
    }

    func testAFileCalledZipThatIsNotOneIsNotAROM() throws {
        XCTAssertFalse(S9xEngine.looksLikeROM(try write(noise(size: 4096), as: "broken.zip")))
    }

    func testAZipOfSomethingElseIsNotAROM() throws {
        let photo = try write(noise(size: 325_000), as: "photo.png")
        XCTAssertFalse(S9xEngine.looksLikeROM(try zip([photo], as: "photos.zip")))
    }

    // MARK: - ROMs

    func testALoROMIsAROM() throws {
        let rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20)
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(rom, as: "game.sfc")))
    }

    func testAHiROMIsAROM() throws {
        let rom = makeROM(size: 0x100000, headerAt: 0xFFC0, mapMode: 0x21)
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(rom, as: "game.sfc")))
    }

    func testAnExHiROMIsAROM() throws {
        let rom = makeROM(size: 0x600000, headerAt: 0x40FFC0, mapMode: 0x25)
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(rom, as: "game.sfc")))
    }

    func testADumpWithACopierHeaderIsAROM() throws {
        let rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20)
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(Data(count: 512) + rom, as: "game.smc")))
    }

    func testARomWithAWrongChecksumButARealHeaderIsAROM() throws {
        let rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20, checksum: nil)
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(rom, as: "homebrew.sfc")))
    }

    func testARomWithAMatchingChecksumAndUnusualFieldsIsAROM() throws {
        var rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20)
        rom[0x7FC0 + 0x15] = 0x00
        rom[0x7FC0 + 0x3D] = 0x00
        XCTAssertTrue(S9xEngine.looksLikeROM(try write(rom, as: "prototype.sfc")))
    }

    func testAZippedROMIsAROM() throws {
        let rom = try write(makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20), as: "game.sfc")
        XCTAssertTrue(S9xEngine.looksLikeROM(try zip([rom], as: "game.zip")))
    }

    func testAZippedROMWithACopierHeaderIsAROM() throws {
        let rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20)
        let file = try write(Data(count: 512) + rom, as: "game.smc")
        XCTAssertTrue(S9xEngine.looksLikeROM(try zip([file], as: "GAME.ZIP")))
    }

    // MARK: - MultiCart

    /// A Sufami Turbo cart image with `extra` copier-header bytes in front.
    private func makeSufamiCart(size: Int = 0x80000, extra: Int = 0) -> Data {
        var cart = Data(repeating: 0, count: size)
        cart.replaceSubrange(0..<14, with: Data("BANDAI SFC-ADX".utf8))
        return Data(count: extra) + cart
    }

    private func makeSufamiBIOS() -> Data {
        var bios = Data(repeating: 0, count: 0x40000)
        bios.replaceSubrange(0..<14, with: Data("BANDAI SFC-ADX".utf8))
        bios.replaceSubrange(0x10..<0x1E, with: Data("SFC-ADX BACKUP".utf8))
        return bios
    }

    private func problem(with cart: URL) -> S9xMultiCartProblem {
        S9xEngine.problem(withMultiCart: cart, biosFolder: folder)
    }

    func testATextFileIsNotAMultiCart() throws {
        let text = Data(repeating: UInt8(ascii: "a"), count: 0x80000)
        XCTAssertEqual(problem(with: try write(text, as: "notes.txt")), .notACart)
    }

    func testAnEmptyFileIsNotAMultiCart() throws {
        XCTAssertEqual(problem(with: try write(Data(), as: "empty.st")), .notACart)
    }

    func testAMissingFileIsNotAMultiCart() {
        XCTAssertEqual(problem(with: folder.appendingPathComponent("missing.st")), .notACart)
    }

    func testAnOrdinaryROMIsNotAMultiCart() throws {
        let rom = makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20)
        XCTAssertEqual(problem(with: try write(rom, as: "game.sfc")), .notACart)
    }

    func testASufamiCartWithoutTheBIOSReportsTheBIOS() throws {
        XCTAssertEqual(problem(with: try write(makeSufamiCart(), as: "cart.st")), .noBIOS)
    }

    func testASufamiCartLoadsWithTheBIOS() throws {
        _ = try write(makeSufamiBIOS(), as: "STBIOS.bin")
        XCTAssertEqual(problem(with: try write(makeSufamiCart(), as: "cart.st")), .none)
    }

    func testAWrongFileNamedLikeTheBIOSDoesNotCount() throws {
        _ = try write(noise(size: 0x40000), as: "STBIOS.bin")
        XCTAssertEqual(problem(with: try write(makeSufamiCart(), as: "cart.st")), .noBIOS)
    }

    func testASufamiCartWithACopierHeaderLoads() throws {
        _ = try write(makeSufamiBIOS(), as: "STBIOS.bin")
        XCTAssertEqual(problem(with: try write(makeSufamiCart(extra: 512), as: "cart.st")), .none)
    }

    func testAZippedSufamiCartLoads() throws {
        _ = try write(makeSufamiBIOS(), as: "STBIOS.bin")
        let cart = try write(makeSufamiCart(), as: "cart.st")
        XCTAssertEqual(problem(with: try zip([cart], as: "cart.zip")), .none)
    }

    func testTheBIOSItselfIsNotACart() throws {
        _ = try write(makeSufamiBIOS(), as: "STBIOS.bin")
        let bios = makeSufamiBIOS() + Data(count: 0x40000)
        XCTAssertEqual(problem(with: try write(bios, as: "bios.st")), .notACart)
    }

    func testABSXCartLoadsWithoutABIOS() throws {
        var cart = Data(repeating: 0, count: 0x100000)
        cart[0x7FB2] = 0x5A
        cart[0x7FB5] = 0x41
        cart[0x7FDA] = 0x33
        XCTAssertEqual(problem(with: try write(cart, as: "memorypack.bs")), .none)
    }

    func testAGzippedROMIsAROM() throws {
        let file = try write(makeROM(size: 0x80000, headerAt: 0x7FC0, mapMode: 0x20), as: "game.sfc")
        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = [file.path]
        try gzip.run()
        gzip.waitUntilExit()
        XCTAssertTrue(S9xEngine.looksLikeROM(folder.appendingPathComponent("game.sfc.gz")))
    }
}
