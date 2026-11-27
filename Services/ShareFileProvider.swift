import Foundation
import UniformTypeIdentifiers

enum ShareFileProvider {
    static func make(for resource: PhotoResource,
                     load: @escaping @Sendable () async throws -> ExtractedFile) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = resource.filename
        let expected: UTType = resource.format == .raw ? .rawImage : .jpeg
        let types = [UTType(resource.uti), UTType(filenameExtension: (resource.filename as NSString).pathExtension)]
        let type = types.compactMap { $0 }.first { $0.conforms(to: expected) } ?? expected

        provider.registerFileRepresentation(for: type, visibility: .all, openInPlace: false) { complete in
            let progress = Progress(totalUnitCount: 1)
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let file = try await load()
                    try Task.checkCancellation()
                    // Keep staging alive while Foundation copies the promised file.
                    withExtendedLifetime(file) { complete(file.url, false, nil) }
                    progress.completedUnitCount = 1
                } catch {
                    complete(nil, false, error)
                }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        return provider
    }
}
