import SwiftUI
import PhotosUI

struct LibraryView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.scenePhase) private var phase
    @State private var format: LibraryFormat?
    @State private var expandedFormats: [LibraryFormat: Bool] = [:]
    @State private var newest = true
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var batch: [String]?
    @State private var manageLimited = false
    @State private var settings = false
    @State private var brand = "All cameras"

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
                        Button { Task { await library.refresh() } } label: {
                            Label("Refresh library", systemImage: "arrow.clockwise")
                        }.accessibilityIdentifier("refreshLibrary").disabled(library.scanning || library.restoring)
                        Menu {
                            Toggle("Recently added first", isOn: $newest)
                            Picker("Camera", selection: $brand) {
                                Text("All cameras").tag("All cameras")
                                ForEach(library.brands, id: \.self) { Text(verbatim: $0).tag($0) }
                            }
                            Button("Read camera brands") { Task { await library.indexBrands() } }
                                .disabled(library.items.isEmpty || library.scanning || library.indexing)
                        } label: { Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle") }
                        Button(selecting ? "Done" : "Select") { selected = []; selecting.toggle() }
                            .disabled(!library.hasSnapshot)
                    }
                }
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $manageLimited, onDismiss: {
                Task { await library.synchronizeAccess(checkLimitedSelection: true) }
            }) { LimitedPicker() }
            .sheet(isPresented: Binding(get: { batch != nil }, set: { if !$0 { batch = nil } })) {
                if let batch { ResolvedPhotos(ids: batch) { ExportView(items: $0) } }
            }
        }
        .id(library.accessRevision)
        .task { await library.synchronizeAccess() }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await library.synchronizeAccess(checkLimitedSelection: true) } }
        }
        .onChange(of: library.accessRevision) { _, _ in selected = []; batch = nil; selecting = false }
        .onChange(of: library.brands) { _, values in
            if !values.contains(brand) { brand = "All cameras" }
        }
        .onChange(of: format) { _, value in
            selected = []
            if let value { expandedFormats[value] = true }
        }
        .onChange(of: brand) { _, _ in selected = [] }
    }

    private var gallery: some View {
        let brandItems = brand == "All cameras" ? library.items : library.items.filter { library.brand(for: $0) == brand }
        let groups = Dictionary(grouping: brandItems) { $0.record.format }
        let available = groups.keys.sorted()
        let active = format.flatMap { groups[$0] == nil ? nil : $0 }
        let categories = active.map { [$0] } ?? available
        let visible = active.flatMap { groups[$0] } ?? brandItems
        let selectedVisible = selecting ? visible.filter { selected.contains($0.id) } : []
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if library.access == .limited { Button("Manage selected photos") { manageLimited = true } }
                if available.count > 1 {
                    Picker("Format", selection: $format) {
                        Text("All formats").tag(Optional<LibraryFormat>.none)
                        ForEach(available, id: \.self) { value in
                            Text(LocalizedStringKey(value.title)).tag(Optional(value))
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("formatPicker")
                }
                if library.scanning {
                    ProgressView(value: Double(library.scanned), total: Double(max(1, library.total))) {
                        Text("Refreshing library…")
                    }.accessibilityIdentifier("scanProgress")
                } else if library.restoring {
                    ProgressView("Opening saved list…")
                } else if !library.hasSnapshot {
                    ContentUnavailableView {
                        Label("Refresh your library", systemImage: "photo.stack")
                    } description: { Text("Refresh to group the 100 most recently added photos by format.") }
                        actions: { Button("Refresh library") { Task { await library.refresh() } }.buttonStyle(.borderedProminent) }
                } else if visible.isEmpty {
                    ContentUnavailableView("No matching photos", systemImage: "photo.stack")
                }
                if library.cacheSaveFailed { Text("This list could not be saved on this device.").foregroundStyle(.secondary) }
                if library.indexing { ProgressView("Reading camera brands…") }
                ForEach(categories, id: \.self) { category in
                    let entries = groups[category] ?? []
                    let expanded = expandedFormats[category] ?? (category == categories.first)
                    Divider()
                    Button {
                        expandedFormats[category] = !expanded
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(category.title)).font(.headline)
                            Spacer()
                            Text(entries.count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: expanded ? "chevron.down" : "chevron.forward")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.interaction, Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                    .accessibilityIdentifier("formatSection-" + category.title)
                    if expanded {
                        photoGrid(newest ? entries : Array(entries.reversed()), category: category)
                    }
                }
            }.padding()
        }
        .onChange(of: available) { _, values in
            if let format, !values.contains(format) { self.format = nil }
        }
        .refreshable { await library.refresh() }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button("Select all") { selected = Set(visible.map(\.id)) }
                    Spacer()
                    Text(selectedVisible.count.formatted()).monospacedDigit()
                    Button("Export") { batch = selectedVisible.map(\.id) }
                        .buttonStyle(.borderedProminent).disabled(selectedVisible.isEmpty)
                }.padding().background(.bar)
            }
        }
    }

    private func photoGrid(_ entries: [LibraryItem], category: LibraryFormat) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142, maximum: 240), spacing: 12)],
                  alignment: .leading, spacing: 18) {
            ForEach(entries) { item in
                if selecting {
                    Button {
                        if !selected.insert(item.id).inserted { selected.remove(item.id) }
                    } label: {
                        tile(item).overlay(alignment: .topTrailing) {
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
                                .padding(7).shadow(radius: 2)
                                .allowsHitTesting(false)
                        }
                    }.accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                } else {
                    NavigationLink {
                        ResolvedPhotos(ids: [item.id]) { photos in
                            if let photo = photos.first {
                                ResourceView(item: photo) { library.record($0, for: item) }
                            }
                        }
                    } label: { tile(item) }
                    .accessibilityIdentifier("libraryTile-" + category.title)
                }
            }
        }.buttonStyle(.plain)
    }

    private func tile(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AssetThumbnail(asset: item.asset)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .bottomLeading) {
                    if let badge = item.record.formatBadge {
                        Text(verbatim: badge).font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.72), in: Capsule()).padding(6)
                            .allowsHitTesting(false)
                    }
                }
            Text(verbatim: item.record.displayFilename).font(.subheadline).lineLimit(1).truncationMode(.middle)
            if let date = item.asset.creationDate { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.interaction, Rectangle())
    }
}

private struct ResolvedPhotos<Content: View>: View {
    let ids: [String]
    @ViewBuilder var content: ([PhotoAsset]) -> Content
    @State private var photos: [PhotoAsset]?

    var body: some View {
        Group {
            if let photos {
                if photos.isEmpty { ContentUnavailableView("Photos no longer available", systemImage: "photo.stack") }
                else { content(photos) }
            } else { ProgressView() }
        }
        .task(id: ids) {
            let current = await PhotoLibraryService.resolve(ids)
            if !Task.isCancelled { photos = current }
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
