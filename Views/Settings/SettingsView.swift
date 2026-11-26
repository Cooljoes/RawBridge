import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("network") private var network = false
    @AppStorage("defaultMode") private var mode = ExportMode.raw
    @AppStorage("collision") private var collision = CollisionPolicy.keepBoth

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "—") (\(info?["CFBundleVersion"] as? String ?? "—"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    Picker("Default format", selection: $mode) {
                        ForEach(ExportMode.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    }
                    Toggle("Allow iCloud downloads", isOn: $network)
                    Picker("Duplicate filenames", selection: $collision) {
                        Text("Keep both").tag(CollisionPolicy.keepBoth)
                        Text("Report conflict").tag(CollisionPolicy.fail)
                    }
                }
                Section {
                    NavigationLink("Verify integrity") { IntegrityView() }
                }
                Section("Language") {
                    Link("App language in Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                Section("About RawBridge") {
                    LabeledContent("Version", value: version)
                    Text("RawBridge reads the originals in your Photos library and exports the files you choose.")
                }
                Section("Privacy") {
                    Text("Photos and camera metadata stay on your device. When enabled, Photos can download originals from iCloud. You choose the destination when saving or sharing.")
                }
            }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
        }
    }
}
