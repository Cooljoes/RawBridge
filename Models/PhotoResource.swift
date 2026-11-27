import Photos
import UniformTypeIdentifiers

enum PhotoFormat: String, Hashable {
    case raw = "RAW", jpeg = "JPEG", heif = "HEIF", other = "—"
}

struct PhotoResource: Identifiable {
    let id: Int
    let source: PHAssetResource
    let filename: String
    let uti: String
    let format: PhotoFormat
    let size: Int?

    init(index: Int, source: PHAssetResource) {
        id = index
        self.source = source
        if #available(iOS 27, *) {
            filename = source.filename ?? ""
            size = source.dataSize
        } else {
            filename = source.originalFilename
            size = nil
        }
        if #available(iOS 26, *) {
            uti = source.contentType.identifier
        } else {
            uti = source.uniformTypeIdentifier
        }
        format = RAWDetectionService.format(uti: uti, filename: filename)
    }

    var formatName: String? { RAWDetectionService.name(uti: uti, filename: filename, format: format) }

    var rawExtension: String? {
        guard format == .raw, let name = formatName, name != "RAW" else { return nil }
        return name
    }

    var displayFormat: String { rawExtension.map { ".\($0)" } ?? formatName ?? "—" }

    var original: Bool { source.type == .photo || source.type == .alternatePhoto }
    var role: String {
        switch source.type {
        case .photo: return "photo"
        case .alternatePhoto: return "alternatePhoto"
        case .fullSizePhoto: return "fullSizePhoto"
        case .adjustmentBasePhoto: return "adjustmentBasePhoto"
        case .adjustmentData: return "adjustmentData"
        case .video: return "video"
        case .audio: return "audio"
        case .fullSizeVideo: return "fullSizeVideo"
        case .pairedVideo: return "pairedVideo"
        case .fullSizePairedVideo: return "fullSizePairedVideo"
        case .adjustmentBaseVideo: return "adjustmentBaseVideo"
        case .adjustmentBasePairedVideo: return "adjustmentBasePairedVideo"
        case .photoProxy: return "photoProxy"
        default: return "resource #\(source.type.rawValue)"
        }
    }
}
