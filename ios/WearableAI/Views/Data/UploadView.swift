import SwiftUI

/// Upload to Dropbox: choose exported CSV files and upload them to the study folder.
struct UploadView: View {
    @Environment(ExportStore.self) private var exports
    @Environment(UploadManager.self) private var uploads
    @AppStorage("participantId") private var participantId = "P001"
    @AppStorage("uploadInBackground") private var uploadInBackground = true

    @State private var selected: Set<URL> = []

    var body: some View {
        List {
            Section {
                CloudBadge()
            } footer: {
                Text("Simulated: Dropbox isn't connected yet. Files would go to /VeritySense_Study/\(participantId)/<date>/.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            Section("Selected Files (\(selected.count))") {
                if exports.files.isEmpty {
                    Text("No CSV files yet. Sync or export recordings first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(exports.files) { file in
                    Button {
                        toggle(file)
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(file.url) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected.contains(file.url) ? Color.accentColor : .secondary)
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(file.name).foregroundStyle(.primary)
                                Text(file.day).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if uploads.uploadedFiles.contains(file.url) {
                                Image(systemName: "checkmark.icloud")
                                    .foregroundStyle(.green)
                            }
                            Text(file.sizeBytes.fileSizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    Task { await uploads.upload(selectedFiles, participantId: participantId) }
                } label: {
                    Text("Upload to Dropbox")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .disabled(selected.isEmpty || uploads.status == .uploading)

                Toggle("Upload in background", isOn: $uploadInBackground)
            }

            statusSection
        }
        .navigationTitle("Upload to Dropbox")
        .onAppear(perform: selectNotYetUploaded)
        .task {
            if DemoLaunch.autoStart && uploads.status == .idle {
                selectNotYetUploaded()
                await uploads.upload(selectedFiles, participantId: participantId)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch uploads.status {
        case .idle:
            EmptyView()
        case .uploading:
            Section {
                ProgressView(value: uploads.progress) {
                    Text("Uploading… \(uploads.bytesDone.fileSizeText) of \(uploads.bytesTotal.fileSizeText)")
                        .font(.subheadline)
                }
            }
        case .complete(let count, let bytes, let date):
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Upload complete!").font(.headline)
                        Text("\(count) files uploaded (\(bytes.fileSizeText))")
                            .font(.subheadline)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var selectedFiles: [ExportedFile] {
        exports.files.filter { selected.contains($0.url) }
    }

    private func toggle(_ file: ExportedFile) {
        if selected.contains(file.url) {
            selected.remove(file.url)
        } else {
            selected.insert(file.url)
        }
    }

    private func selectNotYetUploaded() {
        selected = Set(exports.files.map(\.url).filter { !uploads.uploadedFiles.contains($0) })
    }
}

#Preview {
    NavigationStack {
        UploadView()
    }
    .previewEnvironment()
}
