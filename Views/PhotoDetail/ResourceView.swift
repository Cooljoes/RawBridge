import SwiftUI

struct ResourceView: View {
    let item: PhotoAsset
    var onMetadata: (CameraMetadata) -> Void = { _ in }
    @State private var exporting = false
    @State private var choice: Int?
    @StateObject private var detail = PhotoDetailViewModel()
    @AppStorage("network") private var network = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var choices: [PhotoResource] { item.originals.filter { $0.format != .other } }
    private var current: PhotoResource? { choices.first { $0.id == choice } ?? choices.first }

    var body: some View {
        GeometryReader { geometry in
            if sizeClass == .regular && geometry.size.width > 850 {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { preview.padding() }.frame(width: geometry.size.width * 0.54)
                    Divider()
                    details(includePreview: false)
                }
            } else {
                details(includePreview: true)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Export") { exporting = true } }
        .sheet(isPresented: $exporting) { ExportView(items: [item]) }
        .task(id: "\(current?.id ?? -1)-\(network)") {
            await detail.load(current, network: network)
            if !Task.isCancelled { onMetadata(detail.meta) }
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            if choices.count > 1 {
                Picker("Preview", selection: Binding(get: { current?.id ?? -1 }, set: { choice = $0 })) {
                    ForEach(choices) { resource in Text(verbatim: resource.displayFormat).tag(resource.id) }
                }.pickerStyle(.segmented)
            }
            if let image = detail.image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 580)
                    .accessibilityLabel("Original preview")
            } else if detail.loading {
                if detail.downloaded > 0 { ProgressView(value: detail.downloaded) } else { ProgressView("Reading original…") }
            } else if let error = detail.error {
                Text(verbatim: error).foregroundStyle(.secondary)
            } else {
                Text("No original preview available").foregroundStyle(.secondary)
            }
            if let current { Text(verbatim: current.filename).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity)
    }

    private func details(includePreview: Bool) -> some View {
        List {
            if includePreview { Section { preview } }
            Section("Photo details") {
                if detail.meta.isProRAW { LabeledContent("Format", value: "Apple ProRAW") }
                if let make = detail.meta.make { LabeledContent("Manufacturer", value: make) }
                if let model = detail.meta.model { LabeledContent("Camera", value: model) }
                if let lens = detail.meta.lens { LabeledContent("Lens", value: lens) }
                if let iso = detail.meta.iso { LabeledContent("ISO", value: iso.formatted()) }
                if let speed = detail.meta.exposure, speed > 0 {
                    LabeledContent("Shutter", value: speed < 1 ? "1/\((1 / speed).rounded().formatted()) s" : "\(speed.formatted()) s")
                }
                if let aperture = detail.meta.aperture { LabeledContent("Aperture", value: "ƒ/\(aperture.formatted())") }
                if let focal = detail.meta.focalLength { LabeledContent("Focal length", value: "\(focal.formatted()) mm") }
                if let date = detail.meta.shotDate { LabeledContent("Capture date", value: date) }
                else if let date = item.asset.creationDate { LabeledContent("Capture date") { Text(date, format: .dateTime) } }
                Toggle("Allow iCloud downloads", isOn: $network)
            }
            ForEach(item.resources) { resource in
                Section(resource.filename.nonEmpty ?? "—") {
                    LabeledContent("Resource", value: resource.role)
                    LabeledContent("UTI", value: resource.uti).textSelection(.enabled)
                    LabeledContent("Format", value: resource.displayFormat)
                    if let size = resource.size.map(Int64.init) ?? (current?.id == resource.id ? detail.bytes : nil) {
                        LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
            }
        }
    }
}
