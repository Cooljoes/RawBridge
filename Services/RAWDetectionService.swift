import UniformTypeIdentifiers
import Foundation

enum RAWDetectionService {
    static let extensions: Set<String> = ["nef", "nrw", "cr2", "cr3", "arw", "raf", "rw2", "dng", "rwl", "orf", "pef"]

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
