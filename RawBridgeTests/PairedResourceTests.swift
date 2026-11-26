import XCTest
import Photos
import ImageIO
import UniformTypeIdentifiers
@testable import RawBridge

final class PairedResourceTests: XCTestCase {
    @MainActor
    func testManualRefreshAndColdLaunchCache() async throws {
        #if targetEnvironment(simulator)
        let docs = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let jpeg = docs.appendingPathComponent("RawBridgeTestFixture/iss030e122639.JPG")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: jpeg.path), "Install the optional simulator fixture.")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let first = LibraryViewModel(service: PhotoLibraryService(cacheURL: cache))
        await first.synchronizeAccess()
        XCTAssertFalse(first.hasSnapshot)
        XCTAssertTrue(first.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        await first.refresh()
        XCTAssertTrue(first.hasSnapshot)
        XCTAssertFalse(first.cacheSaveFailed)
        let originalIDs = first.items.map(\.id)
        XCTAssertFalse(originalIDs.isEmpty)

        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: jpeg, options: nil)
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        let newID = try XCTUnwrap(identifier)
        let reopened = LibraryViewModel(service: PhotoLibraryService(cacheURL: cache))
        await reopened.synchronizeAccess()
        await reopened.synchronizeAccess(checkLimitedSelection: true)
        XCTAssertEqual(reopened.items.map(\.id), originalIDs, "A cold or foreground launch must not discover new photos")
        XCTAssertFalse(reopened.items.contains { $0.id == newID })
        await reopened.refresh()
        XCTAssertEqual(reopened.items.first { $0.id == newID }?.record.format, .jpeg)

        let emptyCache = PhotoLibraryService(cacheURL: cache)
        try await emptyCache.save([])
        let empty = LibraryViewModel(service: emptyCache)
        await empty.synchronizeAccess()
        XCTAssertTrue(empty.hasSnapshot)
        XCTAssertTrue(empty.items.isEmpty)
        #else
        throw XCTSkip("Creates a photo in a simulator library only.")
        #endif
    }

    func testHEIFAndRAWDoesNotOfferJPEG() async throws {
        #if targetEnvironment(simulator)
        let docs = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let fixtures = docs.appendingPathComponent("RawBridgeTestFixture")
        let nef = fixtures.appendingPathComponent("iss030e122639.NEF")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: nef.path), "Install the optional Nikon fixture.")
        let jpg = fixtures.appendingPathComponent("iss030e122639.JPG")
        let heif = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).heic")
        defer { try? FileManager.default.removeItem(at: heif) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(jpg as CFURL, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(heif as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: heif, options: nil)
            request.addResource(with: .alternatePhoto, fileURL: nef, options: nil)
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [try XCTUnwrap(identifier)], options: nil).firstObject)
        let item = PhotoAsset(asset)
        XCTAssertEqual(item.formats, [.heif, .raw])
        XCTAssertEqual(LibraryRecord(item).format, .heifRAW)
        XCTAssertTrue(ExportMode.jpeg.resources(in: item).isEmpty)
        XCTAssertTrue(ExportMode.both.resources(in: item).isEmpty)
        let resource = try XCTUnwrap(ExportMode.raw.resources(in: item).first)
        let exported = try await RAWExtractionService.extract(resource, network: false)
        XCTAssertEqual(exported.fingerprint, try FileIntegrity.read(nef))
        #else
        throw XCTSkip("Simulator fixtures only.")
        #endif
    }

    func testAppleLinearDNGWhenInstalled() async throws {
        #if targetEnvironment(simulator)
        let docs = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let url = docs.appendingPathComponent("RawBridgeTestFixture/IMG_1361.DNG")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Install the optional Apple DNG sample.")
        let original = try FileIntegrity.read(url)
        XCTAssertEqual(original.sha256, "e91e77a4533ed7cce551d83330676ea5c47dd5e55fb38adda7819366afdbdfc2")
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [try XCTUnwrap(identifier)], options: nil).firstObject)
        let scanned = try await PhotoLibraryService().scan { _, _ in }
        XCTAssertEqual(scanned.first { $0.id == asset.localIdentifier }?.record.format, .proRAW)
        let raw = try XCTUnwrap(PhotoAsset(asset).originals.first { $0.format == .raw })
        let file = try await RAWExtractionService.extract(raw, network: false)
        XCTAssertEqual(file.fingerprint, original)
        let metadata = MetadataService.read(file.url)
        XCTAssertTrue(metadata.isProRAW)
        XCTAssertEqual(metadata.model, "iPhone 12 Pro")
        #else
        throw XCTSkip("Simulator fixtures only.")
        #endif
    }

    func testSingleOriginalAssets() async throws {
        #if targetEnvironment(simulator)
        let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("RawBridgeTestFixture")
        for (ext, format) in [("NEF", PhotoFormat.raw), ("JPG", PhotoFormat.jpeg)] {
            let source = folder.appendingPathComponent("iss030e122639.\(ext)")
            try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path), "Install the optional simulator fixture.")
            var identifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "solo.\(ext)"
                request.addResource(with: .photo, fileURL: source, options: options)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [try XCTUnwrap(identifier)], options: nil).firstObject)
            let item = PhotoAsset(asset)
            XCTAssertEqual(item.formats, [format])
            XCTAssertEqual(LibraryRecord(item).format, format == .raw ? .raw : .jpeg)
            let resource = try XCTUnwrap(item.originals.first)
            let exported = try await RAWExtractionService.extract(resource, network: false)
            XCTAssertEqual(exported.fingerprint, try FileIntegrity.read(source))
            XCTAssertEqual(exported.url.lastPathComponent, "solo.\(ext)")
            XCTAssertTrue(ExportMode.both.resources(in: item).isEmpty)
        }
        #else
        throw XCTSkip("This test creates assets in a simulator library only.")
        #endif
    }

    // The opt-in integration run creates one asset in a simulator. Production has no Photos write path.
    @MainActor
    func testNikonPairInPhotoKit() async throws {
        #if targetEnvironment(simulator)
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let fixture = documents.appendingPathComponent("RawBridgeTestFixture")
        let nef = fixture.appendingPathComponent("iss030e122639.NEF")
        let jpeg = fixture.appendingPathComponent("iss030e122639.JPG")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: nef.path), "Provide the optional Nikon fixture as described in README.")
        let original = try FileIntegrity.read(nef)
        XCTAssertEqual(original.sha256, "5922721d13f11795557d97fdeb0a60b900086c402bc82a848ff280d15b99ffd4")
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
        var assetID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: jpeg, options: nil)
            request.addResource(with: .alternatePhoto, fileURL: nef, options: nil)
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }
        let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [try XCTUnwrap(assetID)], options: nil).firstObject)
        let item = PhotoAsset(asset)
        XCTAssertEqual(item.label, "JPEG + RAW")
        XCTAssertEqual(LibraryRecord(item).format, .jpegRAW)
        let raw = try XCTUnwrap(item.originals.first { $0.format == .raw })
        let rendered = try XCTUnwrap(item.originals.first { $0.format == .jpeg })
        XCTAssertNotEqual(raw.id, rendered.id)
        let file = try await RAWExtractionService.extract(raw, network: false)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }
        let output = try await ExportService.save(file, in: destination, policy: .keepBoth)
        XCTAssertEqual(output.lastPathComponent, nef.lastPathComponent)
        XCTAssertEqual(try FileIntegrity.read(output), original)
        let jpg = try await RAWExtractionService.extract(rendered, network: false)
        XCTAssertEqual(jpg.fingerprint, try FileIntegrity.read(jpeg))
        let camera = MetadataService.read(file.url)
        XCTAssertTrue(camera.make?.localizedCaseInsensitiveContains("Nikon") == true)
        XCTAssertNotNil(camera.model)
        let queue = ExportViewModel()
        queue.plan([item], mode: .both)
        queue.start(folder: destination, network: false, policy: .fail)
        queue.cancel()
        while queue.running { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertEqual(queue.finished, 0)
        queue.resume(network: false, policy: .fail)
        while queue.running { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertEqual(queue.finished, 1, "Existing NEF conflicts, JPEG succeeds")
        XCTAssertEqual(queue.remaining, 1)
        XCTAssertNotNil(queue.jobs.first { $0.resource.format == .raw }?.error)
        queue.resume(network: false, policy: .keepBoth)
        while queue.running { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertEqual(queue.finished, 2)
        XCTAssertEqual(try FileIntegrity.read(destination.appendingPathComponent("iss030e122639 (2).NEF")), original)
        XCTAssertEqual(try FileIntegrity.read(destination.appendingPathComponent("iss030e122639.JPG")), jpg.fingerprint)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 3)
        let cancelFolder = destination.appendingPathComponent("cancel")
        try FileManager.default.createDirectory(at: cancelFolder, withIntermediateDirectories: false)
        // Repeated reads of the same original give every output an independent, known reference.
        queue.plan(Array(repeating: item, count: 6), mode: .raw)
        queue.start(folder: cancelFolder, network: false, policy: .keepBoth)
        while queue.finished == 0 && queue.running { try await Task.sleep(for: .milliseconds(5)) }
        queue.cancel()
        while queue.running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(queue.finished, 0)
        XCTAssertLessThan(queue.finished, 6)
        let committed = try FileManager.default.contentsOfDirectory(at: cancelFolder, includingPropertiesForKeys: nil)
        XCTAssertEqual(committed.count, queue.finished)
        for url in committed { XCTAssertEqual(try FileIntegrity.read(url), original) }
        print("Pair: \(rendered.role) \(rendered.uti), \(raw.role) \(raw.uti). Extracted \(original.bytes) bytes, SHA-256 \(original.sha256)")
        #else
        throw XCTSkip("This integration test adds an asset only in a simulator library.")
        #endif
    }
}
