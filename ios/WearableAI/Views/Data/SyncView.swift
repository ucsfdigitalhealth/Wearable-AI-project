import SwiftUI

/// Sync & Upload: downloads recordings from the device, converts them to CSV and saves them.
struct SyncView: View {
    @Environment(DeviceManager.self) private var device
    @Environment(SessionStore.self) private var sessions
    @Environment(ExportStore.self) private var exports
    @Environment(SyncManager.self) private var sync
    @State private var showingUpload = false

    var body: some View {
        List {
            if device.connectedDevice == nil && !sync.isSyncing {
                Section {
                    ContentUnavailableView {
                        Label("No device connected", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Connect your Polar Verity Sense to sync its recordings.")
                    } actions: {
                        NavigationLink("Connect Device") { DeviceView() }
                    }
                }
            } else {
                Section {
                    VStack(spacing: 16) {
                        ProgressRing(progress: sync.progress)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }

                Section {
                    ForEach(SyncManager.Step.allCases, id: \.self) { step in
                        ChecklistRow(title: step.title, status: status(for: step))
                    }
                }

                if let error = sync.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if sync.currentStep == .complete {
                        PrimaryButton(title: "Upload to Dropbox") { showingUpload = true }
                            .plainListRow()
                    } else {
                        PrimaryButton(
                            title: device.pendingRecordings.isEmpty ? "Check for Recordings" : "Start Sync",
                            isLoading: sync.isSyncing
                        ) {
                            Task { await sync.sync(device: device, sessions: sessions, exports: exports) }
                        }
                        .disabled(sync.isSyncing)
                        .plainListRow()
                    }
                }
            }
        }
        .navigationTitle("Sync Recordings")
        .navigationDestination(isPresented: $showingUpload) { UploadView() }
        .task {
            if sync.currentStep == .complete { sync.reset() }
            if DemoLaunch.autoStart && !sync.isSyncing {
                // Wait for the demo connection to finish first.
                for _ in 0..<50 where device.connectedDevice == nil || device.pendingRecordings.isEmpty {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await sync.sync(device: device, sessions: sessions, exports: exports)
            }
        }
    }

    private var statusText: String {
        switch sync.currentStep {
        case nil:
            device.pendingRecordings.isEmpty
                ? "No new recordings on the device."
                : "\(device.pendingRecordings.count) new recordings (\(device.pendingBytes.fileSizeText)) ready to sync."
        case .connecting:
            "Connecting to device…"
        case .downloading:
            "Downloading from device…\n\(sync.bytesDone.fileSizeText) of \(sync.bytesTotal.fileSizeText)"
        case .converting:
            "Converting to CSV…"
        case .saving:
            "Saving to phone…"
        case .complete:
            sync.lastSyncCount == 0 ? "Everything is already synced." : "\(sync.lastSyncCount) recordings synced."
        }
    }

    private func status(for step: SyncManager.Step) -> ChecklistRow.Status {
        guard let current = sync.currentStep else { return .pending }
        if current == .complete || step < current { return .done }
        return step == current ? .active : .pending
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 150, height: 150)
    }
}

#Preview {
    NavigationStack {
        SyncView()
    }
    .previewEnvironment()
}
