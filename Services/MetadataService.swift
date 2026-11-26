import Photos
import ImageIO

struct CameraMetadata {
    var make: String?
    var model: String?
    var lens: String?
    var iso: Int?
    var exposure: Double?
    var aperture: Double?
    var focalLength: Double?
    var shotDate: String?
    var isProRAW = false
}

enum MetadataService {
    static func read(_ url: URL) -> CameraMetadata {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [String: Any] else { return CameraMetadata() }
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let dng = properties[kCGImagePropertyDNGDictionary as String] as? [String: Any] ?? [:]
        let make = tiff[kCGImagePropertyTIFFMake as String] as? String
        // Apple camera make alone cannot distinguish a third-party Bayer DNG from ProRAW.
        // ImageIO also reports the DNG profile under its general ProfileName key.
        let profile = (dng[kCGImagePropertyDNGProfileName as String] ?? dng[kCGImagePropertyProfileName as String]) as? String
        let camera = dng[kCGImagePropertyDNGUniqueCameraModel as String] as? String
        let linear = (tiff[kCGImagePropertyTIFFPhotometricInterpretation as String] as? NSNumber)?.intValue == 34892
        let appleLinearProfile = linear && profile == "Apple Embedded Color Profile"
            && camera?.localizedCaseInsensitiveContains("iPhone") == true
        let pro = make?.lowercased() == "apple"
            && (appleLinearProfile || profile?.localizedCaseInsensitiveContains("ProRAW") == true)
        return CameraMetadata(make: make, model: tiff[kCGImagePropertyTIFFModel as String] as? String,
                              lens: exif[kCGImagePropertyExifLensModel as String] as? String,
                              iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue,
                              exposure: exif[kCGImagePropertyExifExposureTime as String] as? Double,
                              aperture: exif[kCGImagePropertyExifFNumber as String] as? Double,
                              focalLength: exif[kCGImagePropertyExifFocalLength as String] as? Double,
                              shotDate: exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, isProRAW: pro)
    }

    static func localMetadata(_ asset: PHAsset) async -> CameraMetadata? {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                DispatchQueue.global(qos: .utility).async {
                    let result = input?.fullSizeImageURL.map(read)
                    continuation.resume(returning: result)
                }
            }
        }
    }

    static func knownBrand(rawExtension: String?) -> String? {
        switch rawExtension?.lowercased() {
        case "nef", "nrw": return "Nikon"
        case "cr2", "cr3": return "Canon"
        case "arw": return "Sony"
        case "raf": return "Fujifilm"
        case "rw2": return "Panasonic"
        case "rwl": return "Leica"
        case "orf": return "OM SYSTEM / Olympus"
        case "pef": return "Pentax"
        default: return nil
        }
    }

    static func normalize(_ make: String) -> String {
        let aliases = [("nikon", "Nikon"), ("canon", "Canon"), ("sony", "Sony"), ("fuji", "Fujifilm"),
                       ("panasonic", "Panasonic"), ("leica", "Leica"), ("olympus", "OM SYSTEM / Olympus"),
                       ("om digital", "OM SYSTEM / Olympus"), ("om system", "OM SYSTEM / Olympus"),
                       ("pentax", "Pentax"), ("apple", "Apple")]
        return aliases.first { make.localizedCaseInsensitiveContains($0.0) }?.1 ?? make
    }
}
