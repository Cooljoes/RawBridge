import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    let items: [PhotoAsset]
    @StateObject private var model = ExportViewModel()
    @AppStorage("defaultMode") private var preferred = ExportMode.raw
    @AppStorage("network") private var network = false
    @AppStorage("collision") private var collision = CollisionPolicy.keepBoth
    @Environment(\.dismiss) private var dismiss
    @State private var mode = ExportMode.raw
    @State private var chooseFolder = false
    @State private var share: ShareRequest?
    @State private var shareCompleted = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Extract", selection: $mode) {
                        ForEach(ExportMode.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.started)
                    LabeledContent("Files", value: model.jobs.count.formatted())
                    if model.skipped > 0 { LabeledContent("Photos without the requested originals", value: model.skipped.formatted()) }
                    Toggle("Allow iCloud downloads", isOn: $network).disabled(model.running)
                    if model.started && !model.running && model.remaining > 0 && !model.forSharing {
                        Picker("Duplicate filenames", selection: $collision) {
                            Text("Keep both").tag(CollisionPolicy.keepBoth)
                            Text("Report conflict").tag(CollisionPolicy.fail)
                        }
                    }
                    if !model.started {
                        Button { chooseFolder = true } label: { Label("Save to Files", systemImage: "folder") }.disabled(model.jobs.isEmpty)
                        Button { openShare() } label: { Label("Share", systemImage: "square.and.arrow.up") }.disabled(model.jobs.isEmpty)
                    }
                }.disabled(model.jobs.isEmpty && model.started)
                if model.started {
                    Section(model.forSharing ? "Prepared for sharing" : "Saved to Files") {
                        LabeledContent("Completed", value: "\(model.finished) / \(model.jobs.count)")
                        if let active = model.active {
                            Text(verbatim: active)
                            if model.progress > 0 { ProgressView(value: model.progress) } else { ProgressView() }
                        }
                        if model.running {
                            Button(model.stopping ? "Cancelling…" : "Cancel extraction", role: .destructive) { model.cancel() }
                                .disabled(model.stopping)
                        } else {
                            if model.remaining > 0 {
                                Button("Retry remaining files") {
                                    if model.forSharing { openShare() }
                                    else { model.resume(network: network, policy: collision) }
                                }
                            }
                            if model.forSharing && model.finished > 0 {
                                Button(model.remaining > 0 ? "Share completed files" : "Share") { openShare(readyOnly: true) }
                            }
                        }
                    }
                    ForEach(model.jobs) { job in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: job.savedName ?? job.resource.filename)
                            if let error = job.error { Text(verbatim: error).foregroundStyle(.red) }
                            if let receipt = job.receipt {
                                Text(verbatim: "\(receipt.bytes.formatted()) B · SHA-256").font(.caption)
                                Text(verbatim: receipt.sha256).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                if let message { Text(verbatim: message) }
            }
            .navigationTitle("Export")
            .toolbar { Button("Done") { dismiss() }.disabled(model.running) }
        }
        .interactiveDismissDisabled(model.running)
        .onAppear { if !model.started {
            let available = ExportMode.allCases.filter { candidate in items.contains { !candidate.resources(in: $0).isEmpty } }
            mode = available.contains(preferred) ? preferred : available.first ?? preferred
            model.plan(items, mode: mode)
        } }
        .onChange(of: mode) { _, value in model.plan(items, mode: value) }
        .onDisappear { if share == nil && model.running { model.cancel() } }
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
            do { model.start(folder: try result.get(), network: network, policy: collision) }
            catch let error as NSError where error.code == NSUserCancelledError { }
            catch { message = error.localizedDescription }
        }
        .sheet(item: $share, onDismiss: {
            if !shareCompleted && model.running { model.cancel() }
        }) { request in
            ShareFiles(providers: request.providers) { completed, error in
                shareCompleted = completed
                if let error { message = error.localizedDescription }
                share = nil
            }
        }
    }

    private func openShare(readyOnly: Bool = false) {
        guard share == nil else { return }
        if !model.started {
            model.start(folder: nil, network: network, policy: collision)
        } else if !readyOnly {
            model.resume(network: network, policy: collision)
        }
        shareCompleted = false
        message = nil
        share = ShareRequest(providers: model.shareProviders(readyOnly: readyOnly))
    }
}

private struct ShareRequest: Identifiable {
    let id = UUID()
    let providers: [NSItemProvider]
}

private struct ShareFiles: UIViewControllerRepresentable {
    let providers: [NSItemProvider]
    let onFinish: @MainActor (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let configuration = UIActivityItemsConfiguration(itemProviders: providers)
        configuration.perItemMetadataProvider = { index, key in
            guard key == .title, providers.indices.contains(index) else { return nil }
            return providers[index].suggestedName
        }
        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        controller.completionWithItemsHandler = { _, completed, _, error in
            onFinish(completed, error)
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
