import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ExportStore.self) private var exports
    @AppStorage("studyName") private var studyName = "RAPHE Study"
    @AppStorage("participantId") private var participantId = "P001"
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @AppStorage("useRealDevice") private var useRealDevice = false
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
                if StudyConfig.polarAvailable {
                    Toggle("Use real Verity Sense", isOn: $useRealDevice)
                }
                LabeledContent("Source", value: StudyConfig.polarAvailable && StudyConfig.useRealDevice ? "Polar Verity Sense" : "Simulated Verity Sense")
                ForEach(SensorStream.allCases) { stream in
                    LabeledContent(stream.title, value: stream.rateLabel)
                }
            } header: {
                Text("Data source")
            } footer: {
                Text(StudyConfig.polarAvailable
                     ? "Restart the app after changing this. The real device needs a physical iPhone; the Simulator has no Bluetooth."
                     : "Fake data in the same format as the Polar Verity Sense. This build doesn't include the Polar SDK yet.")
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
