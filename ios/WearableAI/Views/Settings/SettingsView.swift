import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ExportStore.self) private var exports
    @AppStorage("studyName") private var studyName = "RAPHE Study"
    @AppStorage("participantId") private var participantId = "P001"
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @State private var confirmingDeleteAll = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        Form {
            Section("Study") {
                LabeledContent("Study") {
                    TextField("Study name", text: $studyName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Participant ID") {
                    TextField("P001", text: $participantId)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                }
            }

            Section {
                LabeledContent("Source", value: "Simulated Verity Sense")
                ForEach(SensorStream.allCases) { stream in
                    LabeledContent(stream.title, value: stream.rateLabel)
                }
            } header: {
                Text("Data source")
            } footer: {
                Text("Fake data in the same format as the Polar Verity Sense. It will switch to the real device once Bluetooth support is added.")
            }

            Section("Stored data") {
                LabeledContent("Recordings", value: "\(store.sessions.count)")
                LabeledContent("CSV files", value: "\(exports.files.count)")
                Button("Generate sample recordings") {
                    store.generateSampleSessions()
                }
                Button("Delete all data", role: .destructive) {
                    confirmingDeleteAll = true
                }
                .disabled(store.sessions.isEmpty && exports.files.isEmpty)
            }

            Section {
                Button("Show onboarding again") {
                    hasOnboarded = false
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Link("Polar BLE SDK", destination: URL(string: "https://github.com/polarofficial/polar-ble-sdk")!)
            }
        }
        .navigationTitle("Study & Settings")
        .confirmationDialog("Delete all data?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                store.deleteAll()
                exports.deleteAll()
            }
        } message: {
            Text("This deletes all recordings and CSV files on this phone. It can't be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
