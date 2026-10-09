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

    var body: some View {
        Form {
            Section("Data") {
                ForEach(SensorStream.allCases) { stream in
                    Button {
                        if streams.contains(stream) {
                            streams.remove(stream)
                        } else {
                            streams.insert(stream)
                        }
                    } label: {
                        HStack {
                            Image(systemName: streams.contains(stream) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(streams.contains(stream) ? Color.accentColor : .secondary)
                                .font(.title3)
                            Text("\(stream.title) (\(stream.rateLabel))")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            Section("Time Range") {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if timeRange == .custom {
                    DatePicker("From", selection: $from)
                    DatePicker("To", selection: $to)
                } else if let first = sessions.sessions.last, let last = sessions.sessions.first {
                    Text("\(first.startDate.formatted(date: .abbreviated, time: .shortened)) – \(last.endDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("File Format") {
                LabeledContent("Format", value: "CSV (.csv)")
            }

            Section {
                Button {
                    exported = exports.export(days: selectedSessions, allSessions: sessions.sessions, streams: streams)
                } label: {
                    Text("Export to CSV")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .disabled(streams.isEmpty || selectedSessions.isEmpty)
            } footer: {
                Text(selectedSessions.isEmpty
                     ? "No recordings in this range."
                     : "\(selectedSessions.count) recordings. Files will be saved to your phone.")
            }

            if !exported.isEmpty {
                Section("Exported (\(exported.count) files)") {
                    ForEach(exported) { file in
                        LabeledContent(file.name, value: file.sizeBytes.fileSizeText)
                    }
                    ShareLink(items: exported.map(\.url)) {
                        Label("Share files", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink {
                        UploadView()
                    } label: {
                        Label("Upload to Dropbox", systemImage: "icloud.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Export Data")
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
