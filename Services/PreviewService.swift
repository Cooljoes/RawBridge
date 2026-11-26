import CoreImage
import ImageIO
import UIKit

actor PreviewService {
    static let shared = PreviewService()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(file: ExtractedFile, format: PhotoFormat) throws -> (UIImage?, CameraMetadata) {
        defer { withExtendedLifetime(file) {} }
        try Task.checkCancellation()
        let metadata = MetadataService.read(file.url)
        let limit: CGFloat = 1440
        let cg: CGImage?
        if format == .raw {
            guard let filter = CIRAWFilter(imageURL: file.url) else { return (nil, metadata) }
            let dimension = max(filter.nativeSize.width, filter.nativeSize.height)
            guard dimension > 0 else { return (nil, metadata) }
            filter.scaleFactor = Float(min(1, limit / dimension))
            guard let image = filter.outputImage, !image.extent.isInfinite, !image.extent.isEmpty else { return (nil, metadata) }
            cg = context.createCGImage(image, from: image.extent)
        } else {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: Int(limit)]
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) else { return (nil, metadata) }
            cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        try Task.checkCancellation()
        return (cg.map { UIImage(cgImage: $0) }, metadata)
    }
}
