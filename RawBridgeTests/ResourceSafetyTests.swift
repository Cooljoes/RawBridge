import XCTest
import UniformTypeIdentifiers
@testable import RawBridge

final class ResourceSafetyTests: XCTestCase {
    func testCameraExtensionsAndUTIPrecedence() {
        for ext in ["NEF","NRW","CR2","CR3","ARW","RAF","RW2","DNG","RWL","ORF","PEF"] {
            XCTAssertEqual(RAWDetectionService.format(uti: "public.data", filename: "frame.\(ext)"), .raw)
        }
        XCTAssertEqual(RAWDetectionService.format(uti: UTType.rawImage.identifier, filename: "frame.bin"), .raw)
        XCTAssertEqual(RAWDetectionService.format(uti: UTType.jpeg.identifier, filename: "renamed.NEF"), .jpeg)
        XCTAssertEqual(RAWDetectionService.format(uti: UTType.heic.identifier, filename: "renamed.NEF"), .heif)
        XCTAssertEqual(RAWDetectionService.format(uti: UTType.png.identifier, filename: "renamed.NEF"), .other)
        XCTAssertEqual(RAWDetectionService.format(uti: UTType.movie.identifier, filename: "renamed.NEF"), .other)
    }

    func testBytesAndTruncation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try FileIntegrity.read(url).sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try FileIntegrity.read(url, expectedSize: 4))
        XCTAssertThrowsError(try FileIntegrity.read(url, format: .raw, requireRawSignature: true))
        try Data().write(to: url)
        XCTAssertThrowsError(try FileIntegrity.read(url))
    }

    func testRenderedFilesCannotBeExportedAsRAW() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).NEF")
        defer { try? FileManager.default.removeItem(at: url) }
        for bytes in [[UInt8](arrayLiteral: 255,216,255,224), [137,80,78,71,13,10,26,10],
                      [0,0,0,20] + Array("ftypheic".utf8)] {
            try Data(bytes).write(to: url)
            XCTAssertThrowsError(try FileIntegrity.read(url, format: .raw))
        }
    }

    func testCollisionAndFailedCopyLeaveExistingFilesIntact() async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: folder) }
        let stage = folder.appendingPathComponent("staging")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        let url = stage.appendingPathComponent("DSC_0001.NEF")
        try Data("original".utf8).write(to: url)
        let file = ExtractedFile(url: url, fingerprint: try FileIntegrity.read(url))
        let first = try await ExportService.save(file, in: folder, policy: .fail)
        do { _ = try await ExportService.save(file, in: folder, policy: .fail); XCTFail("Expected a filename conflict") }
        catch BridgeError.duplicate { }
        let second = try await ExportService.save(file, in: folder, policy: .keepBoth)
        XCTAssertEqual(second.lastPathComponent, "DSC_0001 (2).NEF")
        try Data("changed".utf8).write(to: url)
        do { _ = try await ExportService.save(file, in: folder, policy: .keepBoth); XCTFail("Expected hash mismatch") }
        catch BridgeError.mismatch { }
        XCTAssertEqual(try FileIntegrity.read(first), file.fingerprint)
        XCTAssertEqual(try FileIntegrity.read(second), file.fingerprint)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: folder.path)), ["staging", first.lastPathComponent, second.lastPathComponent])
    }
}
