import SwiftUI

@MainActor
final class PhotoDetailViewModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var meta = CameraMetadata()
    @Published private(set) var loading = false
    @Published private(set) var downloaded: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var bytes: Int64?
    private var generation = UUID()

    func load(_ resource: PhotoResource?, network: Bool) async {
        let token = UUID()
        generation = token
        image = nil
        error = nil
        meta = CameraMetadata()
        bytes = nil
        downloaded = 0
        loading = false
        guard let resource else { return }
        loading = true
        defer { if token == generation { loading = false } }
        do {
            let file = try await RAWExtractionService.extract(resource, network: network, interruptible: true) { [weak self] fraction in
                Task { @MainActor in if self?.generation == token { self?.downloaded = fraction } }
            }
            let (image, meta) = try await PreviewService.shared.render(file: file, format: resource.format)
            guard token == generation, !Task.isCancelled else { return }
            self.image = image
            self.meta = meta
            bytes = file.fingerprint.bytes
            if image == nil { error = String(localized: "This device could not decode the preview. You can still extract the original.") }
        } catch {
            if token == generation && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
