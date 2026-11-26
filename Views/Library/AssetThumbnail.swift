import SwiftUI
import Photos

struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?
    @State private var generation: UUID?
    private static let manager = PHCachingImageManager()

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .clipped()
            .accessibilityHidden(true)
            .onAppear {
                let id = UUID()
                generation = id
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .opportunistic
                request = Self.manager.requestImage(for: asset, targetSize: CGSize(width: 440, height: 330),
                                                    contentMode: .aspectFill, options: options) { value, _ in
                    Task { @MainActor in if generation == id, let value { image = value } }
                }
            }
            .onDisappear {
                generation = nil
                if let request { Self.manager.cancelImageRequest(request) }
                image = nil
            }
    }
}
