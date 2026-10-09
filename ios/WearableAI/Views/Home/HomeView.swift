import Charts
import SwiftUI

/// Daily Summary ("Today"): device status plus today's steps, heart rate, sleep and stress.
struct HomeView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SyncManager.self) private var sync

    private let today = MockHealthData.summary(for: .now)
    private let recent = MockHealthData.recentDays(8)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    deviceCard

                    SummaryCard(title: "Steps", systemImage: "figure.walk", tint: .green) {
                        Text(today.steps.formatted())
                    } chart: {
                        Chart(Array(MockHealthData.hourlySteps(for: .now).enumerated()), id: \.offset) { hour, steps in
                            BarMark(x: .value("Hour", hour), y: .value("Steps", steps))
                                .foregroundStyle(.green)
                        }
                    }

                    SummaryCard(title: "Heart Rate", systemImage: "heart.fill", tint: .red) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(today.restingHR)")
                            Text("bpm (resting)").font(.caption).foregroundStyle(.secondary)
                        }
                    } chart: {
                        Chart(Array(MockHealthData.hourlyHeartRate(for: .now).enumerated()), id: \.offset) { hour, bpm in
                            LineMark(x: .value("Hour", hour), y: .value("BPM", bpm))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.red)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                    }

                    SummaryCard(title: "Sleep", systemImage: "moon.zzz.fill", tint: .purple) {
                        Text(formatMinutes(today.sleepMinutes))
                    } chart: {
                        Chart(recent) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", Double(day.sleepMinutes) / 60))
                                .foregroundStyle(.purple)
                        }
                    }

                    SummaryCard(title: "Skin/Stress (PPG)", systemImage: "sun.max.fill", tint: .orange) {
                        Text(stressLevel.rawValue)
                            .font(.title3.weight(.semibold))
                    } chart: {
                        EmptyView()
                    }

                    Text("Summary values are simulated until the data-processing pipeline is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
        }
    }

    @ViewBuilder
    private var deviceCard: some View {
        Card {
            if let info = device.connectedDevice {
                HStack(spacing: 12) {
                    DeviceIcon(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Polar Verity Sense").font(.headline)
                        BatteryLabel(percent: info.batteryPercent)
                    }
                    Spacer()
                }
                NavigationLink {
                    SyncView()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(device.pendingRecordings.isEmpty
                             ? "Up to date"
                             : "Sync \(device.pendingRecordings.count) new recordings")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .fontWeight(.semibold)
                }
                if let last = sync.lastSyncDate {
                    Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    DeviceIcon(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device not connected").font(.headline)
                        Text("Connect to sync your recordings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink("Connect") { DeviceView() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var stressLevel: StressLevel {
        let baseline = recent.dropLast().map(\.stressScore).reduce(0, +) / max(recent.count - 1, 1)
        switch today.stressScore - baseline {
        case ..<(-5): return .lower
        case 6...: return .higher
        default: return .usual
        }
    }
}

/// A metric card with a big value on the left and a small chart on the right.
private struct SummaryCard<Value: View, ChartContent: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var value: Value
    @ViewBuilder var chart: ChartContent

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                    value
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                Spacer(minLength: 0)
                chart
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(width: 130, height: 56)
            }
        }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    "\(minutes / 60) h \(minutes % 60) min"
}

#Preview {
    HomeView()
        .previewEnvironment()
}
