import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @State private var confirmingDeleteAll = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Source", value: "Simulated Verity Sense")
                    LabeledContent("PPG", value: "\(Int(VeritySense.ppgSampleRate)) Hz, 3 channels + ambient")
                    LabeledContent("Accelerometer", value: "\(Int(VeritySense.accSampleRate)) Hz, x/y/z in mG")
                } header: {
                    Text("Data source")
                } footer: {
                    Text("Fake data in the same format as the Polar Verity Sense. It will switch to the real device once Bluetooth support is added.")
                }

                Section("Stored data") {
                    LabeledContent("Saved sessions", value: "\(store.sessions.count)")
                    Button("Generate sample sessions") {
                        store.generateSampleSessions()
                    }
                    Button("Delete all sessions", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                    .disabled(store.sessions.isEmpty)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Polar BLE SDK", destination: URL(string: "https://github.com/polarofficial/polar-ble-sdk")!)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all sessions?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    store.deleteAll()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
