import SwiftUI

enum MoreDestination: String, Hashable {
    case device, recordingSettings, sync, export, upload, recordings, live, settings
}

/// Device and data management, plus developer tools.
struct MoreView: View {
    @State private var path: [MoreDestination] = DemoLaunch.screen.flatMap(MoreDestination.init).map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Device") {
                    row(.device, "Device", "dot.radiowaves.left.and.right")
                    row(.recordingSettings, "Recording Settings", "slider.horizontal.3")
                    row(.sync, "Sync Recordings", "arrow.triangle.2.circlepath")
                }
                Section("Data") {
                    row(.recordings, "Recordings", "list.bullet.rectangle")
                    row(.export, "Export to CSV", "tablecells")
                    row(.upload, "Upload to Dropbox", "icloud.and.arrow.up")
                }
                Section("Developer") {
                    row(.live, "Live Data", "waveform.path.ecg")
                }
                Section {
                    row(.settings, "Study & Settings", "gearshape")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .device: DeviceView()
                case .recordingSettings: RecordingSettingsView()
                case .sync: SyncView()
                case .export: ExportView()
                case .upload: UploadView()
                case .recordings: SessionsListView()
                case .live: DashboardView()
                case .settings: SettingsView()
                }
            }
        }
    }

    private func row(_ destination: MoreDestination, _ title: String, _ systemImage: String) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview {
    MoreView()
        .previewEnvironment()
}
