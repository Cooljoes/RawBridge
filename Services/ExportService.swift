import Foundation

enum CollisionPolicy: String, CaseIterable { case keepBoth, fail }

enum ExportService {
    /// Coordinate with the selected Files provider. Publish only after a complete, verified copy.
    static func save(_ file: ExtractedFile, in folder: URL, policy: CollisionPolicy) async throws -> URL {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        var coordinatorError: NSError?
        var result: Result<URL, Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &coordinatorError) { directory in
            result = Result {
                let fm = FileManager.default
                let temporary = directory.appendingPathComponent(".RawBridge-\(UUID().uuidString).partial")
                defer { try? fm.removeItem(at: temporary) }
                try fm.copyItem(at: file.url, to: temporary)
                guard try FileIntegrity.read(temporary) == file.fingerprint else { throw BridgeError.mismatch }
                let name = file.url.lastPathComponent
                let base = (name as NSString).deletingPathExtension
                let ext = file.url.pathExtension
                var index = 1
                while true {
                    try Task.checkCancellation()
                    let suffix = ext.isEmpty ? "" : ".\(ext)"
                    let candidate = directory.appendingPathComponent(index == 1 ? name : "\(base) (\(index))\(suffix)")
                    do {
                        try fm.moveItem(at: temporary, to: candidate)
                        return candidate
                    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                        guard policy == .keepBoth else { throw BridgeError.duplicate }
                        index += 1
                    }
                }
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
