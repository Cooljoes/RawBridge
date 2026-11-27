import Photos

struct PhotoAsset: Identifiable {
    let asset: PHAsset
    let resources: [PhotoResource]
    var id: String { asset.localIdentifier }
    let originals: [PhotoResource]
    let formats: Set<PhotoFormat>
    var rawOriginal: PhotoResource? { originals.first { $0.format == .raw } }

    var title: String {
        if let raw = rawOriginal {
            return raw.filename.nonEmpty ?? raw.displayFormat
        }
        return originals.first?.filename.nonEmpty ?? resources.first?.filename.nonEmpty ?? "—"
    }

    init(_ asset: PHAsset) {
        self.asset = asset
        resources = PHAssetResource.assetResources(for: asset).enumerated().map(PhotoResource.init)
        originals = resources.filter(\.original)
        formats = Set(originals.map(\.format))
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
