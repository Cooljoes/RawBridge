import SwiftUI

@MainActor
final class ExportViewModel: ObservableObject {
    @Published private(set) var jobs: [ExportJob] = []
    @Published private(set) var active: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var running = false
    @Published private(set) var stopping = false
    @Published private(set) var skipped = 0
    @Published private(set) var started = false
    private var worker: Task<Void, Never>?
    private var folder: URL?
    private var progressID: UUID?

    var finished: Int { jobs.filter { $0.receipt != nil }.count }
    var remaining: Int { jobs.count - finished }
    var forSharing: Bool { started && folder == nil }

    func shareProviders(readyOnly: Bool = false) -> [NSItemProvider] {
        jobs.enumerated().compactMap { index, job in
            guard !readyOnly || job.sharingFile != nil else { return nil }
            return ShareFileProvider.make(for: job.resource) { [self] in
                try await fileForSharing(at: index, id: job.id)
            }
        }
    }

    private func fileForSharing(at index: Int, id: UUID) async throws -> ExtractedFile {
        for await (current, isRunning) in $jobs.combineLatest($running).values {
            try Task.checkCancellation()
            guard current.indices.contains(index), current[index].id == id else { throw CancellationError() }
            let job = current[index]
            if let file = job.sharingFile { return file }
            if !isRunning {
                if let reason = job.error {
                    throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: reason])
                }
                throw CancellationError()
            }
        }
        throw CancellationError()
    }

    func plan(_ items: [PhotoAsset], mode: ExportMode) {
        guard !running else { return }
        jobs = []
        skipped = 0
        started = false
        for item in items {
            let resources = mode.resources(in: item)
            if resources.isEmpty { skipped += 1 }
            jobs.append(contentsOf: resources.map { ExportJob(resource: $0) })
        }
    }
    func start(folder: URL?, network: Bool, policy: CollisionPolicy) {
        guard !running, !started else { return }
        self.folder = folder
        started = true
        resume(network: network, policy: policy)
    }
    func resume(network: Bool, policy: CollisionPolicy) {
        guard !running, remaining > 0 else { return }
        running = true
        stopping = false
        worker = Task {
            defer { running = false; active = nil; stopping = false; worker = nil; progressID = nil }
            for index in jobs.indices where jobs[index].receipt == nil {
                guard !Task.isCancelled else { return }
                let resource = jobs[index].resource
                let id = UUID()
                active = resource.filename
                progressID = id
                progress = 0
                jobs[index].error = nil
                do {
                    let file = try await RAWExtractionService.extract(resource, network: network,
                                        interruptible: forSharing || network || jobs.count > 1) { fraction in
                        Task { @MainActor in
                            guard self.progressID == id else { return }
                            self.progress = min(1, max(0, fraction))
                        }
                    }
                    try Task.checkCancellation()
                    if let folder {
                        let url = try await ExportService.save(file, in: folder, policy: policy)
                        jobs[index].savedName = url.lastPathComponent
                    } else {
                        jobs[index].sharingFile = file
                    }
                    jobs[index].receipt = file.fingerprint
                } catch {
                    if Task.isCancelled { return }
                    jobs[index].error = error.localizedDescription
                }
            }
        }
    }

    func cancel() { stopping = true; worker?.cancel() }
}
