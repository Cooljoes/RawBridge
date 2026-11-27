import Photos

/// One section per combination of original file formats. Edits and companion videos are excluded.
struct LibraryFormat: Hashable, Codable, Comparable {
    let images: [String]
    let raw: [String]

    init(images: [String] = [], raw: [String] = []) {
        self.images = Set(images).sorted()
        self.raw = Set(raw).sorted()
    }

    init(originals: [PhotoResource]) {
        self.init(images: originals.filter { $0.format != .raw }.compactMap(\.formatName),
                  raw: originals.filter { $0.format == .raw }.compactMap(\.formatName))
    }

    static let proRAW = Self(raw: ["Apple ProRAW"])
    var isDNG: Bool { images.isEmpty && raw == ["DNG"] }
    var isPairedRAW: Bool { !images.isEmpty && !raw.isEmpty }
    var title: String { (images + raw).joined(separator: " + ").nonEmpty ?? "Format unavailable" }

    private var rank: Int {
        if isPairedRAW { return 0 }
        if !raw.isEmpty { return 1 }
        if images == ["JPEG"] { return 2 }
        if images == ["HEIC"] || images == ["HEIF"] { return 3 }
        return images.isEmpty ? 5 : 4
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.rank, lhs.title) < (rhs.rank, rhs.title)
    }
}

struct LibraryRecord: Codable, Identifiable {
    let id: String
    let displayFilename: String
    var format: LibraryFormat
    let rawExtension: String?

    init(_ photo: PhotoAsset) {
        id = photo.id
        displayFilename = photo.title
        format = LibraryFormat(originals: photo.originals)
        rawExtension = photo.rawOriginal?.rawExtension
    }

    var formatBadge: String? {
        guard format.isPairedRAW, let rawExtension else { return nil }
        return ".\(rawExtension)"
    }
}

struct LibraryItem: Identifiable {
    let asset: PHAsset
    var record: LibraryRecord
    var id: String { record.id }
}
