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
    /// Problems that didn't stop the sync, e.g. a recording that couldn't be downloaded.
    private(set) var warningMessage: String?

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
        warningMessage = nil
    }

    func sync(device: DeviceManager, sessions: SessionStore, exports: ExportStore) async {
        guard !isSyncing, device.connectedDevice != nil else { return }
        errorMessage = nil
        warningMessage = nil
        bytesDone = 0
        bytesTotal = 0

        currentStep = .connecting
        device.stopLiveStreams()
        // Polar recommends stopping recordings before reading or deleting them.
        guard await device.stopSensorRecording() else {
            fail("Couldn't stop the recording on the sensor: \(device.recordingError ?? "unknown error")")
            return
        }
        do {
            try await device.refreshRecordings()
        } catch {
            fail("Couldn't list the recordings on the sensor: \(error.localizedDescription)")
            return
        }

        currentStep = .downloading
        let recordings = device.pendingRecordings
        bytesTotal = recordings.reduce(0) { $0 + $1.sizeBytes }
        var downloaded: [(recording: DeviceRecording, session: RecordingSession)] = []
        var problems: [String] = []
        for recording in recordings {
            let alreadyDone = bytesDone
            do {
                let session = try await device.download(recording) { fraction in
                    self.bytesDone = alreadyDone + Int64(Double(recording.sizeBytes) * fraction)
                }
                downloaded.append((recording, session))
            } catch {
                // Skip it and keep going; it stays on the sensor for the next sync.
                problems.append("Recording from \(recording.startDate.formatted(date: .abbreviated, time: .shortened)): \(error.localizedDescription)")
            }
            bytesDone = alreadyDone + recording.sizeBytes
        }
        if downloaded.isEmpty && !problems.isEmpty {
            fail("Sync failed.\n" + problems.joined(separator: "\n"))
            return
        }

        // Skip recordings already on the phone (e.g. a sync that was interrupted earlier).
        let existing = Set(sessions.sessions.map { "\($0.deviceId)-\($0.startDate.timeIntervalSince1970)" })
        let newSessions = downloaded.map { $0.session }
            .filter { !existing.contains("\($0.deviceId)-\($0.startDate.timeIntervalSince1970)") }

        currentStep = .converting
        exports.export(days: newSessions, allSessions: sessions.sessions + newSessions, streams: Set(SensorStream.allCases))
        try? await Task.sleep(for: .milliseconds(700))

        currentStep = .saving
        for session in newSessions {
            sessions.save(session)
        }
        try? await Task.sleep(for: .milliseconds(500))

        // Only now remove them from the sensor, so a failure here can't lose data.
        for item in downloaded {
            do {
                try await device.deleteFromSensor(item.recording)
            } catch {
                problems.append("Saved on the phone, but \(error.localizedDescription)")
            }
        }

        warningMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
        lastSyncDate = .now
        lastSyncCount = newSessions.count
        currentStep = .complete
    }

    private func fail(_ message: String) {
        errorMessage = message
        currentStep = nil
    }
}
