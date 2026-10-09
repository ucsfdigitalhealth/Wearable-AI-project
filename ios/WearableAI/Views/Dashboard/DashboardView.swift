import SwiftUI

struct DashboardView: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        Group {
            if device.connectedDevice == nil {
                ContentUnavailableView {
                    Label("No device connected", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Connect your Polar Verity Sense to stream live data.")
                } actions: {
                    NavigationLink("Connect Device") { DeviceView() }
                }
            } else {
                liveContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Data")
    }

    private var liveContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    MetricCard(
                        title: "Heart rate",
                        value: device.currentHR.map { "\($0.bpm)" } ?? "--",
                        unit: "bpm",
                        systemImage: "heart.fill",
                        tint: .red
                    )
                    MetricCard(
                        title: "Activity",
                        value: device.activity.rawValue,
                        systemImage: device.activity.systemImage,
                        tint: .green
                    )
                }

                RecordingCard()

                Card(title: "PPG (raw)") {
                    PPGWaveformChart(samples: device.recentPPG)
                }

                Card(title: "Accelerometer (mG)") {
                    AccelerometerChart(samples: device.recentACC)
                }

                Card(title: "Heart rate trend") {
                    if device.hrHistory.count < 2 {
                        Text("Collecting data…")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        HeartRateTrendChart(samples: device.hrHistory)
                    }
                }
            }
            .padding()
        }
    }
}

private struct RecordingCard: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let start = device.recordingStartDate {
                        Label("Recording", systemImage: "record.circle")
                            .foregroundStyle(.red)
                            .font(.subheadline.weight(.semibold))
                        Text(start, style: .timer)
                            .font(.title2.monospacedDigit())
                    } else {
                        Text("Not recording")
                            .font(.subheadline.weight(.semibold))
                        Text("Saved recordings appear under More → Recordings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    if device.isRecording {
                        device.stopRecording()
                    } else {
                        device.startRecording()
                    }
                } label: {
                    Label(
                        device.isRecording ? "Stop" : "Record",
                        systemImage: device.isRecording ? "stop.fill" : "circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(device.isRecording ? .gray : .red)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .previewEnvironment()
}
