import SwiftUI
import UniformTypeIdentifiers

struct IntegrityView: View {
    @State private var picking = false
    @State private var selectingCard = true
    @State private var card: (String, Fingerprint)?
    @State private var exported: (String, Fingerprint)?
    @State private var reading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Button("Choose camera card original") { selectingCard = true; picking = true }
                receipt(card)
                Button("Choose exported file") { selectingCard = false; picking = true }
                receipt(exported)
            }.disabled(reading)
            if reading { ProgressView("Calculating SHA-256…") }
            if let error { Text(verbatim: error).foregroundStyle(.red) }
            if let card, let exported {
                let equal = card.1 == exported.1
                Label(equal ? "Files match byte for byte" : "Files differ", systemImage: equal ? "checkmark.seal" : "exclamationmark.triangle")
            }
        }.navigationTitle("Verify integrity")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                error = nil
                if selectingCard { card = nil } else { exported = nil }
                reading = true
                Task {
                    defer { reading = false }
                    do {
                        let hash = try await Self.fingerprint(url)
                        if selectingCard { card = (url.lastPathComponent, hash) }
                        else { exported = (url.lastPathComponent, hash) }
                    } catch { self.error = error.localizedDescription }
                }
            } catch let error as NSError where error.code == NSUserCancelledError { }
            catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private func receipt(_ item: (String, Fingerprint)?) -> some View {
        if let item {
            VStack(alignment: .leading) {
                Text(verbatim: "\(item.0) · \(item.1.bytes.formatted()) B")
                Text(verbatim: item.1.sha256).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

    private nonisolated static func fingerprint(_ url: URL) async throws -> Fingerprint {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var error: NSError?
        var result: Result<Fingerprint, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { local in
            result = Result { try FileIntegrity.read(local) }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
