import CryptoKit
import Foundation

struct Fingerprint: Equatable {
    let bytes: Int64
    let sha256: String
}

enum BridgeError: LocalizedError {
    case invalidName, empty, mismatch, previewAsRAW, notOriginal, duplicate, cloudOnly

    var errorDescription: String? {
        switch self {
        case .invalidName: return String(localized: "The original filename is missing or unsafe.")
        case .empty: return String(localized: "The resource is empty.")
        case .mismatch: return String(localized: "The file does not match the expected bytes.")
        case .previewAsRAW: return String(localized: "The file contains a rendered image instead of RAW data.")
        case .notOriginal: return String(localized: "This resource is not an exportable original.")
        case .duplicate: return String(localized: "A file with this name already exists.")
        case .cloudOnly: return String(localized: "Photos requires a download. Allow iCloud downloads and try again.")
        }
    }
}

enum FileIntegrity {
    static func read(_ url: URL, format: PhotoFormat? = nil, expectedSize: Int? = nil, requireRawSignature: Bool = false) throws -> Fingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try autoreleasepool { try handle.read(upToCount: 1024 * 1024) ?? Data() }
            if data.isEmpty { break }
            if bytes == 0 {
                let prefix = [UInt8](data.prefix(16))
                let jpeg = prefix.starts(with: [0xff, 0xd8, 0xff])
                let png = prefix.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
                let heif = String(decoding: prefix.dropFirst(4).prefix(4), as: UTF8.self) == "ftyp"
                    && ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "avif"].contains(String(decoding: prefix.dropFirst(8).prefix(4), as: UTF8.self))
                if format == .raw && (jpeg || png || heif) { throw BridgeError.previewAsRAW }
                if requireRawSignature {
                    // TIFF/BigTIFF families, Olympus ORF, Panasonic RW2, RAF and Canon CR3.
                    let headers: [[UInt8]] = [[73,73,42,0], [77,77,0,42], [73,73,43,0], [77,77,0,43],
                                              [73,73,82,79], [73,73,82,83], [77,77,79,82], [73,73,85,0]]
                    let raf = prefix.starts(with: Array("FUJIFILMCCD-RAW ".utf8))
                    let cr3 = prefix.dropFirst(4).starts(with: Array("ftypcrx ".utf8))
                    guard raf || cr3 || headers.contains(where: { prefix.starts(with: $0) }) else { throw BridgeError.mismatch }
                }
                if format == .jpeg && !jpeg { throw BridgeError.mismatch }
            }
            hash.update(data: data)
            bytes += Int64(data.count)
        }
        guard bytes > 0 else { throw BridgeError.empty }
        if let expectedSize, bytes != Int64(expectedSize) { throw BridgeError.mismatch }
        return Fingerprint(bytes: bytes, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
