import SwiftUI

/// Turn on passive phone data collection (GPS, motion, activity, screen state).
struct PassiveDataView: View {
    @Environment(PassiveDataCollector.self) private var collector
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Toggle("Collect phone data", isOn: Binding(
                    get: { collector.isEnabled },
                    set: { $0 ? collector.enable() : collector.disable() }
                ))
                LabeledContent("Status", value: collector.isCollecting ? "Collecting" : "Off")
                LabeledContent("Location access", value: collector.permission.title)
            } footer: {
                Text("Runs in the background while on. Files are saved as phone_*.csv next to the Verity Sense files, so they are exported and uploaded together.")
            }

            if collector.permission == .denied {
                Section {
                    Label("Location access is off. Turn it on in Settings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } else if collector.permission == .whenInUse {
                Section {
                    Label("Choose “Always” so GPS keeps recording when the app is closed.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section("Data collected") {
                ForEach(PassiveStream.allCases) { stream in
                    HStack {
                        Label(stream.title, systemImage: stream.systemImage)
                        Spacer()
                        Text("\(collector.counts[stream, default: 0])")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let last = collector.lastLocationDate {
                    LabeledContent("Last GPS fix", value: last.formatted(date: .omitted, time: .standard))
                }
                if let activity = collector.lastActivity {
                    LabeledContent("Current activity", value: activity.capitalized)
                }
            }

            Section("About screen state") {
                Text("iOS doesn't tell apps when the screen turns on or off. The app records when the phone is locked or unlocked and when the app moves to the foreground or background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Phone Data")
    }
}

#Preview {
    NavigationStack {
        PassiveDataView()
    }
    .previewEnvironment()
}
