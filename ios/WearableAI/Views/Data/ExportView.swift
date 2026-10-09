import SwiftUI

/// Export Data: pick streams and a time range, then write CSV files on the phone.
struct ExportView: View {
    enum TimeRange: String, CaseIterable, Identifiable {
        case all, custom
        var id: String { rawValue }
        var title: String { self == .all ? "Full recording" : "Custom range" }
    }

    @Environment(SessionStore.self) private var sessions
    @Environment(ExportStore.self) private var exports

    @State private var streams = Set(SensorStream.allCases)
    @State private var timeRange = TimeRange.all
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    @State private var to = Date.now
    @State private var exported: [ExportedFile] = []
    @State private var showingUpload = false

    var body: some View {
        Form {
            Section {
                ForEach(SensorStream.allCases) { stream in
                    CheckboxRow(isOn: streams.contains(stream)) {
                        if streams.contains(stream) {
                            streams.remove(stream)
                        } else {
                            streams.insert(stream)
                        }
                    } label: {
                        Text("\(stream.title) (\(stream.rateLabel))")
                    }
                }
            }

            Section("Time Range") {
                RadioRow(title: TimeRange.all.title, subtitle: fullRangeText, isSelected: timeRange == .all) {
                    timeRange = .all
                }
                RadioRow(title: TimeRange.custom.title, isSelected: timeRange == .custom) {
                    timeRange = .custom
                }
                if timeRange == .custom {
                    DatePicker("From", selection: $from)
                    DatePicker("To", selection: $to)
                }
            }

            Section("File Format") {
                RadioRow(title: "CSV (.csv)", isSelected: true) {}
            }

            Section {
                PrimaryButton(title: "Export to CSV") {
                    exported = exports.export(days: selectedSessions, allSessions: sessions.sessions, streams: streams)
                }
                .disabled(streams.isEmpty || selectedSessions.isEmpty)
                .plainListRow()
            } footer: {
                Text(selectedSessions.isEmpty ? "No recordings in this range." : "Files will be saved to your phone.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            if !exported.isEmpty {
                Section("Exported (\(exported.count) files)") {
                    ForEach(exported) { file in
                        LabeledContent(file.name, value: file.sizeBytes.fileSizeText)
                    }
                    ShareLink(items: exported.map(\.url)) {
                        Label("Share files", systemImage: "square.and.arrow.up")
                    }
                }
                Section {
                    PrimaryButton(title: "Upload to Dropbox") { showingUpload = true }
                        .plainListRow()
                }
            }
        }
        .navigationTitle("Export Data")
        .navigationDestination(isPresented: $showingUpload) { UploadView() }
    }

    private var fullRangeText: String? {
        guard let first = sessions.sessions.last, let last = sessions.sessions.first else { return nil }
        let start = first.startDate.formatted(date: .abbreviated, time: .shortened)
        let end = last.endDate.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }

    private var selectedSessions: [RecordingSession] {
        guard timeRange == .custom else { return sessions.sessions }
        return sessions.sessions.filter { $0.startDate >= from && $0.startDate <= to }
    }
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .previewEnvironment()
}
