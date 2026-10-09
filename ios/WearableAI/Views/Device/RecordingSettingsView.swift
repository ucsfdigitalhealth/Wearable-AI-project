import SwiftUI

/// Which sensors the device records, and when.
struct RecordingSettingsView: View {
    var showsSaveButton = true

    @Environment(DeviceManager.self) private var device
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecordingSettings.load()
    @State private var saving = false

    private let toggleableStreams: [SensorStream] = [.ppg, .acc, .gyro, .mag]

    var body: some View {
        Form {
            Section {
                ForEach(toggleableStreams) { stream in
                    Toggle(isOn: binding(for: stream)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Record \(stream.title)")
                                Text(stream.rateLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: stream.systemImage)
                        }
                    }
                    .tint(.green)
                }
            } header: {
                Text("Sensors")
            } footer: {
                Text("Heart rate and PPI are always recorded. More sensors use more battery and storage.")
            }

            Section("Recording Mode") {
                ForEach(RecordingMode.allCases) { mode in
                    RadioRow(title: mode.title, isSelected: draft.mode == mode) {
                        draft.mode = mode
                    }
                }
            }

            if showsSaveButton {
                Section {
                    PrimaryButton(title: "Save Settings", isLoading: saving) {
                        Task {
                            saving = true
                            await device.apply(draft)
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(draft == device.recordingSettings || saving)
                    .plainListRow()
                }
            }
        }
        .navigationTitle("Recording Settings")
        .onChange(of: draft) {
            // During onboarding there's no Save button, so apply right away.
            if !showsSaveButton {
                Task { await device.apply(draft) }
            }
        }
    }

    private func binding(for stream: SensorStream) -> Binding<Bool> {
        Binding {
            draft.enabledStreams.contains(stream)
        } set: { isOn in
            if isOn {
                draft.enabledStreams.insert(stream)
            } else {
                draft.enabledStreams.remove(stream)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingSettingsView()
    }
    .previewEnvironment()
}
