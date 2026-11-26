import Photos

// Photos delivers data and completion on a serial queue. The lock only protects request-ID
// registration and cancellation, which can race with the return from requestData.
private final class RequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHAssetResourceDataRequestID?
    private var cancelled = false

    func register(_ value: PHAssetResourceDataRequestID) {
        lock.lock()
        id = value
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let value = id
        lock.unlock()
        if let value { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
}

enum InterruptibleWriter {
    static func write(_ resource: PHAssetResource, to url: URL, options: PHAssetResourceRequestOptions) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        let token = RequestToken()
        // The first write error must survive PhotoKit's cancellation callback (e.g. disk full).
        final class StreamState: @unchecked Sendable { var error: Error? }
        let state = StreamState()
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                        guard state.error == nil else { return }
                        do { try handle.write(contentsOf: data) }
                        catch { state.error = error; token.cancel() }
                    } completionHandler: { error in
                        if let failure = state.error ?? error { continuation.resume(throwing: failure) }
                        else { continuation.resume() }
                    }
                    token.register(id)
                }
                try Task.checkCancellation()
            } onCancel: { token.cancel() }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}
