import SwiftUI
import PhotosUI

struct LibraryView: View {
    @StateObject private var library = LibraryViewModel()
    @Environment(\.scenePhase) private var phase
    @State private var rawOnly = false
    @State private var newest = true
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var batch: [PhotoAsset]?
    @State private var manageLimited = false
    @State private var settings = false
    @State private var brand = "All cameras"

    private var visibleItems: [PhotoAsset] {
        var filtered = library.items
        if rawOnly { filtered = filtered.filter { $0.formats.contains(.raw) } }
        if brand != "All cameras" { filtered = filtered.filter { library.brand(for: $0) == brand } }
        return newest ? filtered : filtered.reversed()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch library.access {
                case .authorized, .limited: gallery
                case .notDetermined:
                    ContentUnavailableView {
                        Label("Photo library", systemImage: "photo.on.rectangle")
                    } description: { Text("Choose which photos RawBridge can read.") } actions: {
                        Button("Choose Photo Access") { Task { await library.request() } }.buttonStyle(.borderedProminent)
                    }
                default:
                    ContentUnavailableView {
                        Label("Photo access unavailable", systemImage: "lock")
                    } description: { Text("Review Photos access in Settings.") } actions: {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            }
            .navigationTitle("RawBridge")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Label("Settings", systemImage: "gearshape") } }
                if library.access == .authorized || library.access == .limited {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Toggle("RAW only", isOn: $rawOnly)
                            Toggle("Newest first", isOn: $newest)
                            Picker("Camera", selection: $brand) {
                                Text("All cameras").tag("All cameras")
                                ForEach(library.brands, id: \.self) { Text(verbatim: $0).tag($0) }
                            }
                            Button("Read camera brands") { Task { await library.indexBrands() } }
                            if library.access == .limited { Button("Manage selected photos") { manageLimited = true } }
                        } label: { Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle") }
                        Button(selecting ? "Done" : "Select") { selected = []; selecting.toggle() }
                    }
                }
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $manageLimited, onDismiss: { Task { await library.refresh() } }) { LimitedPicker() }
            .sheet(isPresented: Binding(get: { batch != nil }, set: { if !$0 { batch = nil } })) {
                if let batch { ExportView(items: batch) }
            }
        }
        .task { await library.refresh() }
        .onChange(of: phase) { _, value in if value == .active { Task { await library.refresh() } } }
        .onChange(of: library.access) { _, _ in selected = []; batch = nil }
    }

    private var gallery: some View {
        let items = visibleItems
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if library.access == .limited {
                    Button("Manage selected photos") { manageLimited = true }
                }
                if library.scanning { ProgressView(value: Double(library.items.count), total: Double(max(1, library.total))) }
                if library.indexing { ProgressView("Reading camera brands…") }
                if items.isEmpty && !library.scanning {
                    ContentUnavailableView("No matching photos", systemImage: "photo.stack")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 142, maximum: 240), spacing: 12)], alignment: .leading, spacing: 18) {
                    ForEach(items) { item in
                        if selecting {
                            Button {
                                if !selected.insert(item.id).inserted { selected.remove(item.id) }
                            } label: {
                                tile(item).overlay(alignment: .topTrailing) {
                                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
                                        .padding(7).shadow(radius: 2)
                                }
                            }.accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                        } else {
                            NavigationLink { ResourceView(item: item) { library.record($0, for: item) } } label: { tile(item) }
                        }
                    }
                }.buttonStyle(.plain)
            }.padding()
        }
        .refreshable { await library.refresh() }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button("Select all") { selected = Set(items.map(\.id)) }
                    Spacer()
                    Text(selected.intersection(items.map(\.id)).count.formatted()).monospacedDigit()
                    Button("Export") { batch = items.filter { selected.contains($0.id) } }
                        .buttonStyle(.borderedProminent).disabled(!items.contains { selected.contains($0.id) })
                }.padding().background(.bar)
            }
        }
    }

    private func tile(_ item: PhotoAsset) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AssetThumbnail(asset: item.asset)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .bottomLeading) {
                    Text(verbatim: library.badge(for: item)).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.72), in: Capsule()).padding(6)
                }
            Text(verbatim: item.title).font(.subheadline).lineLimit(1)
            if let date = item.asset.creationDate { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct LimitedPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIViewController {
        let host = PickerHost()
        host.finished = { dismiss() }
        return host
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class PickerHost: UIViewController {
        var finished: (() -> Void)?
        private var presented = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if presented { finished?(); return }
            presented = true
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self) { [weak self] _ in
                Task { @MainActor in self?.finished?() }
            }
        }
    }
}
