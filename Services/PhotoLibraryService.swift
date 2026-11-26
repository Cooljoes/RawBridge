import Photos

actor PhotoLibraryService {
    private let cacheURL: URL

    init(cacheURL: URL = URL.cachesDirectory.appendingPathComponent("RawBridge-library-v1.json")) {
        self.cacheURL = cacheURL
    }

    func save(_ records: [LibraryRecord]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func forget() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// A nil cache means the user has never refreshed (or iOS evicted the cache).
    /// An empty array represents a completed refresh of an empty library.
    func restore() -> [LibraryItem]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let records = try? JSONDecoder().decode([LibraryRecord].self, from: data) else { return nil }
        return authorizedItems(records)
    }

    func authorizedItems(_ records: [LibraryRecord]) -> [LibraryItem] {
        var items: [LibraryItem] = []
        for offset in stride(from: 0, to: records.count, by: 500) {
            let page = records[offset..<min(records.count, offset + 500)]
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: page.map(\.id), options: nil)
            var byID: [String: PHAsset] = [:]
            assets.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
            items += page.compactMap { record in byID[record.id].map { LibraryItem(asset: $0, record: record) } }
        }
        return items
    }

    /// Only a manual refresh calls this full-library resource enumeration.
    func scan(progress: @MainActor (Int, Int) -> Void) async throws -> [LibraryItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var items: [LibraryItem] = []
        items.reserveCapacity(assets.count)
        await progress(0, assets.count)
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            var record = autoreleasepool { LibraryRecord(PhotoAsset(asset)) }
            if record.format == .raw, record.rawExtension == "DNG",
               await MetadataService.localMetadata(asset)?.isProRAW == true {
                record.format = .proRAW
            }
            items.append(LibraryItem(asset: asset, record: record))
            if items.count.isMultiple(of: 100) || items.count == assets.count {
                await progress(items.count, assets.count)
            }
        }
        return items
    }

    /// Resolve current resource handles only for a user-opened detail or export selection.
    static func resolve(_ ids: [String]) async -> [PhotoAsset] {
        var photos: [PhotoAsset] = []
        for offset in stride(from: 0, to: ids.count, by: 200) {
            guard !Task.isCancelled else { return [] }
            let page = ids[offset..<min(ids.count, offset + 200)]
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(page), options: nil)
            var byID: [String: PhotoAsset] = [:]
            assets.enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                byID[asset.localIdentifier] = autoreleasepool { PhotoAsset(asset) }
            }
            photos += page.compactMap { byID[$0] }
        }
        return photos
    }
}
