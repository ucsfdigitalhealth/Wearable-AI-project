import Foundation
import Observation

/// How much recent data the live screen shows.
enum LiveDisplay {
    static let windowSeconds = 5.0
    static let hrHistoryLength = 120
}

/// Holds connection state, the device's pending recordings and recording settings,
/// and short rolling windows of live data for the Live Data screen.
@MainActor
@Observable
final class DeviceManager {
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(DiscoveredDevice)
        case connected(DeviceInfo)
    }

    enum ConnectStep: Int, Comparable {
        case found, pairing, connected

        static func < (lhs: ConnectStep, rhs: ConnectStep) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var state: ConnectionState = .disconnected
    private(set) var connectStep: ConnectStep = .found
    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var lastError: String?

    private(set) var pendingRecordings: [DeviceRecording] = []
    private(set) var recordingSettings = RecordingSettings.load()

    private(set) var recentPPG: [PPGSample] = []
    private(set) var recentACC: [ACCSample] = []
    private(set) var hrHistory: [HRSample] = []
    private(set) var activity: ActivityLevel = .resting
    private(set) var movementIntensity: Double = 0

    private(set) var recordingStartDate: Date?

    @ObservationIgnored private var recordedPPG: [PPGSample] = []
    @ObservationIgnored private var recordedACC: [ACCSample] = []
    @ObservationIgnored private var recordedHR: [HRSample] = []

    @ObservationIgnored private let source: SensorDataSource
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var streamTasks: [Task<Void, Never>] = []

    init(source: SensorDataSource, sessionStore: SessionStore) {
        self.source = source
        self.sessionStore = sessionStore
    }

    var connectedDevice: DeviceInfo? {
        if case .connected(let info) = state { return info }
        return nil
    }

    var isScanning: Bool { state == .scanning }
    var isRecording: Bool { recordingStartDate != nil }
    var currentHR: HRSample? { hrHistory.last }
    var pendingBytes: Int64 { pendingRecordings.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: - Connection

    func startScan() {
        guard state == .disconnected else { return }
        discoveredDevices = []
        lastError = nil
        state = .scanning
        scanTask = Task {
            for await device in self.source.scan() {
                self.discoveredDevices.append(device)
            }
            if self.state == .scanning {
                self.state = .disconnected
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        if state == .scanning {
            state = .disconnected
        }
    }

    func connect(to device: DiscoveredDevice) {
        stopScan()
        state = .connecting(device)
        connectStep = .found
        connectTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600))
                self.connectStep = .pairing
                let info = try await self.source.connect(to: device)
                self.connectStep = .connected
                self.state = .connected(info)
                self.startStreams()
                await self.refreshRecordings()
            } catch is CancellationError {
                self.state = .disconnected
            } catch {
                self.lastError = error.localizedDescription
                self.state = .disconnected
            }
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        state = .disconnected
    }

    func disconnect() {
        if isRecording {
            stopRecording()
        }
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        Task { await self.source.disconnect() }

        state = .disconnected
        pendingRecordings = []
        recentPPG = []
        recentACC = []
        hrHistory = []
        activity = .resting
        movementIntensity = 0
    }

    // MARK: - Offline recordings

    func refreshRecordings() async {
        guard connectedDevice != nil else { return }
        do {
            // Hide recordings that are already on the phone (e.g. from an interrupted sync).
            let onPhone = Set(sessionStore.sessions.map(\.startDate.timeIntervalSince1970))
            pendingRecordings = try await source.listRecordings()
                .filter { !onPhone.contains($0.startDate.timeIntervalSince1970) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Downloads a recording, then removes it from the device.
    func download(
        _ recording: DeviceRecording,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> RecordingSession {
        let session = try await source.download(recording, progress: progress)
        try await source.deleteFromDevice(recording)
        pendingRecordings.removeAll { $0.id == recording.id }
        return session
    }

    func apply(_ settings: RecordingSettings) async {
        settings.save()
        recordingSettings = settings
        if connectedDevice != nil {
            try? await source.apply(settings)
        }
    }

    // MARK: - Live recording

    func startRecording() {
        guard connectedDevice != nil, !isRecording else { return }
        recordedPPG = []
        recordedACC = []
        recordedHR = []
        recordingStartDate = .now
    }

    func stopRecording() {
        guard let start = recordingStartDate, let device = connectedDevice else { return }
        let session = RecordingSession(
            id: UUID(),
            deviceId: device.id,
            deviceName: device.name,
            startDate: start,
            endDate: .now,
            ppg: recordedPPG,
            acc: recordedACC,
            gyro: [],
            mag: [],
            hr: recordedHR
        )
        recordingStartDate = nil
        recordedPPG = []
        recordedACC = []
        recordedHR = []
        sessionStore.save(session)
    }

    // MARK: - Streams

    private func startStreams() {
        streamTasks = [
            Task {
                for await batch in self.source.ppgStream() { self.handlePPG(batch) }
            },
            Task {
                for await batch in self.source.accStream() { self.handleACC(batch) }
            },
            Task {
                for await sample in self.source.hrStream() { self.handleHR(sample) }
            },
        ]
    }

    private func handlePPG(_ batch: [PPGSample]) {
        recentPPG.append(contentsOf: batch)
        recentPPG.keepLast(Int(LiveDisplay.windowSeconds * VeritySense.ppgSampleRate))
        if isRecording { recordedPPG.append(contentsOf: batch) }
    }

    private func handleACC(_ batch: [ACCSample]) {
        recentACC.append(contentsOf: batch)
        recentACC.keepLast(Int(LiveDisplay.windowSeconds * VeritySense.accSampleRate))
        if isRecording { recordedACC.append(contentsOf: batch) }

        // Classify the last ~2 seconds.
        let window = recentACC.suffix(Int(2 * VeritySense.accSampleRate))
        movementIntensity = ActivityClassifier.movementIntensity(window)
        activity = ActivityClassifier.level(forIntensity: movementIntensity)
    }

    private func handleHR(_ sample: HRSample) {
        hrHistory.append(sample)
        hrHistory.keepLast(LiveDisplay.hrHistoryLength)
        if isRecording { recordedHR.append(sample) }
    }
}

private extension Array {
    mutating func keepLast(_ count: Int) {
        if self.count > count {
            removeFirst(self.count - count)
        }
    }
}
