import Photos
import UniformTypeIdentifiers
import Foundation

// Each extraction owns a separate directory, including when several windows export the same name.
final class ExtractedFile: Identifiable {
    let id = UUID()
    let url: URL
    let fingerprint: Fingerprint
    init(url: URL, fingerprint: Fingerprint) {
        self.url = url
        self.fingerprint = fingerprint
    }
    private static let cleanup = DispatchQueue(label: "RawBridge.staging.cleanup", qos: .utility)
    deinit {
        let directory = url.deletingLastPathComponent()
        Self.cleanup.async { try? FileManager.default.removeItem(at: directory) }
    }
}

enum RAWExtractionService {
    static func extract(_ resource: PhotoResource, network: Bool, interruptible: Bool = false,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ExtractedFile {
        guard resource.original, resource.format != .other else { throw BridgeError.notOriginal }
        let name = resource.filename
        guard !name.isEmpty, ![".", ".."].contains(name), (name as NSString).lastPathComponent == name,
              !name.contains("\0") else { throw BridgeError.invalidName }
        try Task.checkCancellation()
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("RawBridge-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent(name)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = network
        options.progressHandler = progress
        do {
            if interruptible {
                try await InterruptibleWriter.write(resource.source, to: url, options: options)
            } else {
                try await PHAssetResourceManager.default().writeData(for: resource.source, toFile: url, options: options)
            }
            let fingerprint = try FileIntegrity.read(url, format: resource.format, expectedSize: resource.size,
                                                     requireRawSignature: resource.format == .raw && UTType(resource.uti)?.conforms(to: .rawImage) != true)
            return ExtractedFile(url: url, fingerprint: fingerprint)
        } catch {
            try? fm.removeItem(at: directory)
            let error = error as NSError
            if error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.Code.networkAccessRequired.rawValue {
                throw BridgeError.cloudOnly
            }
            throw error
        }
    }
}
