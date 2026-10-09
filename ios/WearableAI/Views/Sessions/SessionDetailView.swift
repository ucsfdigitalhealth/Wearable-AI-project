import Charts
import SwiftUI

struct SessionDetailView: View {
    let session: RecordingSession
    private let analysis: SessionAnalysis

    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(session: RecordingSession) {
        self.session = session
        self.analysis = SessionAnalysis(session: session)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryGrid

                Card(title: "Heart rate (bpm)") {
                    Chart(analysis.heartRate) { point in
                        LineMark(x: .value("Minutes", point.minutes), y: .value("BPM", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.red)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxisLabel("minutes")
                    .frame(height: 160)
                }

                Card(title: "Movement (mG)") {
                    Chart(analysis.movement) { point in
                        AreaMark(x: .value("Minutes", point.minutes), y: .value("Movement", point.value))
                            .foregroundStyle(.green.opacity(0.6))
                    }
                    .chartXAxisLabel("minutes")
                    .frame(height: 120)
                }

                Card(title: "Raw data") {
                    LabeledContent("PPG samples", value: session.ppg.count.formatted())
                    LabeledContent("Accelerometer samples", value: session.acc.count.formatted())
                    LabeledContent("Heart rate samples", value: session.hr.count.formatted())
                    LabeledContent("Device", value: session.deviceName)
                }

                Card(title: "Export CSV") {
                    ForEach(SessionCSVExport.Stream.allCases) { stream in
                        let export = SessionCSVExport(session: session, stream: stream)
                        ShareLink(item: export, preview: SharePreview(export.fileName)) {
                            Label(stream.title, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(session)
                dismiss()
            }
        }
    }

    private var summaryGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                MetricCard(title: "Duration", value: formatDuration(session.duration), systemImage: "clock", tint: .blue)
                MetricCard(title: "Avg HR", value: session.averageHR.map { "\($0)" } ?? "--", unit: "bpm", systemImage: "heart.fill", tint: .red)
            }
            GridRow {
                MetricCard(
                    title: "HR range",
                    value: "\(session.minHR ?? 0)–\(session.maxHR ?? 0)",
                    unit: "bpm",
                    systemImage: "arrow.up.arrow.down",
                    tint: .pink
                )
                MetricCard(
                    title: "Active",
                    value: "\(Int((analysis.activeFraction * 100).rounded()))",
                    unit: "%",
                    systemImage: "figure.walk",
                    tint: .green
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: SyntheticSessionFactory.makeSession(start: .now.addingTimeInterval(-600), duration: 240))
    }
    .previewEnvironment()
}
