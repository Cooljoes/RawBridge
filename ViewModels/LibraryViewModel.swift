import Photos
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var items: [PhotoAsset] = []
    @Published private(set) var total = 0
    @Published private(set) var scanning = false
    @Published private(set) var indexing = false
    @Published private var indexed: [String: String] = [:]
    private var indexGeneration = UUID()
    @Published private(set) var brands: [String] = []
    @Published private var proRAW: Set<String> = []
    func badge(for item: PhotoAsset) -> String {
        let ext = item.originals.first { $0.format == .raw }.map { ($0.filename as NSString).pathExtension.uppercased() }
        if proRAW.contains(item.id) { return item.label.replacingOccurrences(of: "RAW", with: "ProRAW") }
        guard let ext, RAWDetectionService.extensions.contains(ext.lowercased()) else { return item.label }
        return "\(item.label) · \(ext)"
    }
    func record(_ metadata: CameraMetadata, for item: PhotoAsset) {
        if metadata.isProRAW && item.formats.contains(.raw) { proRAW.insert(item.id) }
        if let make = metadata.make {
            let name = MetadataService.normalize(make)
            indexed[item.id] = name
            updateBrands([name])
        }
    }
    private var observer: LibraryObserver?
    private func updateBrands(_ newValues: [String]) {
        let updated = Set(brands).union(newValues).sorted()
        if updated != brands { brands = updated }
    }
    func brand(for item: PhotoAsset) -> String? { indexed[item.id] ?? MetadataService.knownBrand(item) }
    func indexBrands() async {
        guard !indexing else { return }
        let token = indexGeneration
        indexing = true
        defer { if token == indexGeneration { indexing = false } }
        for item in items where brand(for: item) == nil {
            let metadata = await MetadataService.localMetadata(item.asset)
            guard token == indexGeneration, !Task.isCancelled else { return }
            if let metadata { record(metadata, for: item) }
        }
    }
    private var generation = UUID()

    func request() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await refresh()
    }

    func refresh() async {
        let token = UUID()
        generation = token
        indexGeneration = UUID()
        indexing = false
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        items = []
        brands = []
        total = 0
        scanning = false
        if access != .authorized { indexed = [:]; proRAW = [] }
        guard access == .authorized || access == .limited else { observer = nil; return }
        if observer == nil {
            observer = LibraryObserver { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
        }
        scanning = true
        defer { if generation == token { scanning = false } }
        let service = PhotoLibraryService()
        let count = await service.start()
        guard generation == token else { return }
        total = count
        while items.count < count, generation == token, !Task.isCancelled {
            guard let batch = try? await service.page(from: items.count, limit: 100),
                  !batch.isEmpty, generation == token, !Task.isCancelled else { return }
            items.append(contentsOf: batch)
            updateBrands(batch.compactMap(brand))
        }
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
