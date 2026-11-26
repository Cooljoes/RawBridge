import Photos

actor PhotoLibraryService {
    private var fetch: PHFetchResult<PHAsset>?

    func start() -> Int {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        fetch = result
        return result.count
    }

    func page(from offset: Int, limit: Int) throws -> [PhotoAsset] {
        guard let fetch, offset < fetch.count else { return [] }
        var page = [PhotoAsset]()
        for index in offset..<min(fetch.count, offset + limit) {
            try Task.checkCancellation()
            page.append(autoreleasepool { PhotoAsset(fetch.object(at: index)) })
        }
        return page
    }
}
