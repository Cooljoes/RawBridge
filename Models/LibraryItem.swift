import Photos

/// Exactly one group per asset. Only original resources participate in the classification.
enum LibraryFormat: String, Codable, CaseIterable, Identifiable {
    case jpegRAW = "JPEG + RAW"
    case raw = "RAW"
    case heifRAW = "HEIF + RAW"
    case proRAW = "Apple ProRAW"
    case jpeg = "JPEG"
    case heif = "HEIF"
    case other = "Other formats"

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .raw: return "RAW only"
        case .jpeg: return "JPEG only"
        case .heif: return "HEIF only"
        default: return rawValue
        }
    }

    init(formats: Set<PhotoFormat>, isProRAW: Bool = false) {
        switch formats {
        case [.jpeg, .raw]: self = .jpegRAW
        case [.heif, .raw]: self = .heifRAW
        case [.raw]: self = isProRAW ? .proRAW : .raw
        case [.jpeg]: self = .jpeg
        case [.heif]: self = .heif
        default: self = .other
        }
    }
}

/// The disk cache contains only the fields needed to display the last refreshed list.
struct LibraryRecord: Codable, Identifiable {
    let id: String
    private let title: String
    var format: LibraryFormat
    let rawExtension: String?

    init(_ photo: PhotoAsset) {
        id = photo.id
        title = photo.title
        format = LibraryFormat(formats: photo.formats)
        rawExtension = photo.rawOriginal?.rawExtension
    }

    var displayFilename: String {
        guard format == .jpegRAW else { return title }
        let name = title as NSString
        // A 0.2.0 snapshot may contain the JPEG's name. Show its stem beside the
        // cached RAW badge until a manual refresh supplies the actual RAW filename.
        if !name.pathExtension.isEmpty && name.pathExtension.uppercased() != rawExtension {
            return name.deletingPathExtension
        }
        return title
    }

    var formatBadge: String? {
        guard format == .jpegRAW else { return rawExtension }
        return rawExtension.map { ".\($0)" } ?? PhotoFormat.raw.rawValue
    }
}

struct LibraryItem: Identifiable {
    let asset: PHAsset
    var record: LibraryRecord
    var id: String { record.id }
}
