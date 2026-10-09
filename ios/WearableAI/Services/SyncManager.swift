import Foundation
import Observation

/// Runs the sync workflow: download recordings from the device over BLE, convert them
/// to CSV, and save them on the phone.
@MainActor
@Observable
final class SyncManager {
    enum Step: Int, CaseIterable, Comparable {
        case connecting, downloading, converting, saving, complete

        var title: String {
            switch self {
            case .connecting: "Connecting to device"
            case .downloading: "Downloading recordings"
            case .converting: "Converting to CSV"
            case .saving: "Saving to phone"
            case .complete: "Complete"
            }
        }

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var currentStep: Step?
    private(set) var bytesDone: Int64 = 0
    private(set) var bytesTotal: Int64 = 0
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncCount = 0
    private(set) var errorMessage: String?

    var isSyncing: Bool {
        if let currentStep { return currentStep != .complete }
        return false
    }

    var progress: Double {
        switch currentStep {
        case nil, .connecting: 0
        case .downloading: bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : 1
        case .converting, .saving, .complete: 1
        }
    }

    func reset() {
        guard !isSyncing else { return }
        currentStep = nil
        errorMessage = nil
    }

    func sync(device: DeviceManager, sessions: SessionStore, exports: ExportStore) async {
        guard !isSyncing, device.connectedDevice != nil else { return }
        errorMessage = nil
        bytesDone = 0

        currentStep = .connecting
        await device.refreshRecordings()
        try? await Task.sleep(for: .milliseconds(800))

        currentStep = .downloading
        let recordings = device.pendingRecordings
        bytesTotal = recordings.reduce(0) { $0 + $1.sizeBytes }
        var downloaded: [RecordingSession] = []
        do {
            for recording in recordings {
                let alreadyDone = bytesDone
                let session = try await device.download(recording) { fraction in
                    self.bytesDone = alreadyDone + Int64(Double(recording.sizeBytes) * fraction)
                }
                downloaded.append(session)
            }
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            currentStep = nil
            return
        }

        // Skip recordings already on the phone (e.g. a sync that was interrupted earlier).
        let existing = Set(sessions.sessions.map { "\($0.deviceId)-\($0.startDate.timeIntervalSince1970)" })
        downloaded.removeAll { existing.contains("\($0.deviceId)-\($0.startDate.timeIntervalSince1970)") }

        currentStep = .converting
        exports.export(days: downloaded, allSessions: sessions.sessions + downloaded, streams: Set(SensorStream.allCases))
        try? await Task.sleep(for: .milliseconds(700))

        currentStep = .saving
        for session in downloaded {
            sessions.save(session)
        }
        try? await Task.sleep(for: .milliseconds(500))

        lastSyncDate = .now
        lastSyncCount = downloaded.count
        currentStep = .complete
    }
}
