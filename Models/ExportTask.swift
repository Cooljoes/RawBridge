import Foundation

enum ExportMode: String, CaseIterable, Identifiable {
    case raw = "RAW", jpeg = "JPEG", both = "RAW + JPEG"
    var id: Self { self }

    func resources(in item: PhotoAsset) -> [PhotoResource] {
        switch self {
        case .raw: return item.originals.filter { $0.format == .raw }
        case .jpeg: return item.originals.filter { $0.format == .jpeg }
        case .both:
            guard item.formats.isSuperset(of: [.raw, .jpeg]) else { return [] }
            return item.originals.filter { $0.format == .raw || $0.format == .jpeg }
        }
    }
}

struct ExportJob: Identifiable {
    let resource: PhotoResource
    let id = UUID()
    var receipt: Fingerprint?
    var savedName: String?
    var sharingFile: ExtractedFile?
    var error: String?
}
