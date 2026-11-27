import Photos
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var total = 0
    @Published private(set) var scanned = 0
    @Published private(set) var scanning = false
    @Published private(set) var restoring = false
    @Published private(set) var hasSnapshot = false
    @Published private(set) var indexing = false
    @Published private(set) var cacheSaveFailed = false
    @Published private(set) var brands: [String] = []
    @Published private var indexed: [String: String] = [:]

    private let service: PhotoLibraryService
    private var observer: LibraryObserver?
    private var initialized = false
    @Published private(set) var accessRevision = UUID()
    private var listVersion = UUID()
    private var revision = UUID()
    private var scanTask: Task<[LibraryItem], Error>?
    private var brandRevision = UUID()

    init(service: PhotoLibraryService = PhotoLibraryService()) {
        self.service = service
    }

    func brand(for item: LibraryItem) -> String? {
        indexed[item.id] ?? MetadataService.knownBrand(rawExtension: item.record.rawExtension)
    }

    func record(_ metadata: CameraMetadata, for item: LibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if metadata.isProRAW && items[index].record.format.isDNG {
            items[index].record.format = .proRAW
        }
        if let make = metadata.make {
            let name = MetadataService.normalize(make)
            indexed[item.id] = name
            if !brands.contains(name) { brands = (brands + [name]).sorted() }
        }
    }

    func indexBrands() async {
        guard !indexing, !scanning, !restoring else { return }
        let token = brandRevision
        indexing = true
        defer { if token == brandRevision { indexing = false } }
        for item in items where brand(for: item) == nil {
            let metadata = await MetadataService.localMetadata(item.asset)
            guard token == brandRevision, !Task.isCancelled else { return }
            if let metadata { record(metadata, for: item) }
        }
    }

    func request() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await synchronizeAccess()
    }

    /// Foreground and permission events can prune the saved list, but never discover new resources.
    func synchronizeAccess(checkLimitedSelection: Bool = false) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let changed = status != access
        if initialized && !changed {
            if status == .limited && checkLimitedSelection { await pruneLimitedList() }
            return
        }
        if changed { accessRevision = UUID() }
        initialized = true
        access = status
        let token = invalidateWork()
        items = []
        brands = []
        indexed = [:]
        hasSnapshot = false
        guard status == .authorized || status == .limited else {
            observer = nil
            await service.forget()
            return
        }
        if status == .limited && observer == nil {
            observer = LibraryObserver { [weak self] in
                Task { @MainActor in await self?.synchronizeAccess(checkLimitedSelection: true) }
            }
        } else if status == .authorized { observer = nil }
        restoring = true
        let visible = await service.restore()
        guard token == revision else { return }
        restoring = false
        if let visible {
            replaceItems(visible)
            if status == .limited { await persist(visible, token: token) }
        }
    }

    private func pruneLimitedList() async {
        guard hasSnapshot, !restoring else { return }
        let version = listVersion
        let token = revision
        let visible = await service.authorizedItems(items.map(\.record))
        guard token == revision, version == listVersion, access == .limited,
              visible.count < items.count else { return }
        let allowed = Set(visible.map(\.id))
        indexed = indexed.filter { allowed.contains($0.key) }
        accessRevision = UUID()
        replaceItems(visible)
        await persist(visible, token: token)
    }

    /// Let the pull gesture settle while the model scans and reports progress independently.
    func requestRefresh() {
        Task { await refresh() }
    }

    func refresh() async {
        await synchronizeAccess()
        guard access == .authorized || access == .limited, !scanning, !restoring else { return }
        let token = invalidateWork()
        scanning = true
        scanned = 0
        total = 0
        cacheSaveFailed = false
        let task = Task { try await service.scan { [weak self] done, count in
            guard self?.revision == token else { return }
            self?.scanned = done
            self?.total = count
        } }
        scanTask = task
        defer {
            if revision == token { scanning = false; scanTask = nil }
        }
        guard let result = try? await task.value, revision == token else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == access else {
            await synchronizeAccess()
            return
        }
        let visible = access == .limited ? await service.authorizedItems(result.map(\.record)) : result
        guard token == revision else { return }
        replaceItems(visible)
        await persist(visible, token: token)
    }

    private func invalidateWork() -> UUID {
        scanTask?.cancel()
        scanTask = nil
        revision = UUID()
        brandRevision = UUID()
        scanning = false
        restoring = false
        indexing = false
        return revision
    }

    private func replaceItems(_ result: [LibraryItem]) {
        listVersion = UUID()
        items = result
        brands = Set(result.compactMap(brand)).sorted()
        hasSnapshot = true
    }

    private func persist(_ result: [LibraryItem], token: UUID) async {
        do { try await service.save(result.map(\.record)) }
        catch { if revision == token { cacheSaveFailed = true } }
    }
}

private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    let changed: @Sendable () -> Void
    init(changed: @escaping @Sendable () -> Void) {
        self.changed = changed
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    func photoLibraryDidChange(_ changeInstance: PHChange) { changed() }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
}
