import UniformTypeIdentifiers
import Foundation

enum RAWDetectionService {
    static let extensions: Set<String> = ["nef", "nrw", "cr2", "cr3", "arw", "raf", "rw2", "dng", "rwl", "orf", "pef"]

    /// A display name from the original's declared type, with the filename as a fallback.
    static func name(uti: String, filename: String, format: PhotoFormat) -> String? {
        if format == .jpeg { return "JPEG" }
        let suffix = (filename as NSString).pathExtension.lowercased()
        let type = UTType(uti)
        if format == .raw {
            // A RAW family can register multiple extensions (e.g. NEF and NRW).
            if let type, type != .rawImage, type.conforms(to: .rawImage) {
                if type.tags[.filenameExtension]?.contains(suffix) == true { return suffix.uppercased() }
                if let ext = type.preferredFilenameExtension { return ext.uppercased() }
            }
            return extensions.contains(suffix) ? suffix.uppercased() : "RAW"
        }
        if type == .heif, suffix == "heic" { return "HEIC" }
        let generic = type == nil || type == .data || type == .item || type == .image
            || type == .content || type?.isDynamic == true
        let ext = generic ? suffix.nonEmpty : type?.preferredFilenameExtension ?? suffix.nonEmpty
        switch ext?.lowercased() {
        case "jpg", "jpe": return "JPEG"
        case "tif": return "TIFF"
        case let ext?: return ext.uppercased()
        case nil: return generic ? nil : uti.nonEmpty
        }
    }

    static func format(uti: String, filename: String) -> PhotoFormat {
        let ext = (filename as NSString).pathExtension.lowercased()
        if let type = UTType(uti) {
            if type.conforms(to: .rawImage) { return .raw }
            if type.conforms(to: .jpeg) { return .jpeg }
            if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heif }
            let generic = type == .data || type == .image || type == .item || type == .tiff || type.isDynamic
            if !generic && type.isDeclared { return .other }
        }
        if extensions.contains(ext) { return .raw }
        if ["jpeg", "jpg", "jpe"].contains(ext) { return .jpeg }
        if ["heic", "heif"].contains(ext) { return .heif }
        return .other
    }
}
