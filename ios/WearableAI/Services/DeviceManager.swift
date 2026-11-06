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
    /// Streams the sensor is recording on its own (offline recording).
    private(set) var sensorRecordingStreams: Set<SensorStream> = []
    private(set) var isUpdatingSensorRecording = false
    private(set) var recordingError: String?

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
    var isSensorRecording: Bool { !sensorRecordingStreams.isEmpty }
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
                self.recordingError = nil
                await self.refreshRecordingStatus()
                do {
                    try await self.refreshRecordings()
                } catch {
                    self.recordingError = "Couldn't list recordings: \(error.localizedDescription)"
                }
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
        stopLiveStreams()
        Task { await self.source.disconnect() }

        state = .disconnected
        pendingRecordings = []
        sensorRecordingStreams = []
        recordingError = nil
        recentPPG = []
        recentACC = []
        hrHistory = []
        activity = .resting
        movementIntensity = 0
    }

    // MARK: - Offline recordings

    func refreshRecordings() async throws {
        guard connectedDevice != nil else { return }
        // Hide recordings that are already on the phone (e.g. from a sync that couldn't
        // remove them from the sensor).
        let onPhone = Set(sessionStore.sessions.map(\.startDate.timeIntervalSince1970))
        pendingRecordings = try await source.listRecordings()
            .filter { !onPhone.contains($0.startDate.timeIntervalSince1970) }
    }

    /// Downloads a recording. It stays on the device until `deleteFromSensor` is called.
    func download(
        _ recording: DeviceRecording,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> RecordingSession {
        try await source.download(recording, progress: progress)
    }

    /// Removes a recording from the device. Call only after it is saved on the phone.
    func deleteFromSensor(_ recording: DeviceRecording) async throws {
        try await source.deleteFromDevice(recording)
        pendingRecordings.removeAll { $0.id == recording.id }
    }

    /// Saves which streams to record. They're sent to the sensor when a recording starts.
    func saveSettings(_ settings: RecordingSettings) {
        settings.save()
        recordingSettings = settings
    }

    // MARK: - Recording on the sensor

    /// Starts recording the enabled streams on the sensor, which then records on its own.
    func startSensorRecording() async {
        guard connectedDevice != nil, !isUpdatingSensorRecording else { return }
        isUpdatingSensorRecording = true
        recordingError = nil
        // The sensor can't stream and record PPG or accelerometer at the same time.
        stopLiveStreams()
        do {
            try await source.startRecording(recordingSettings.enabledStreams)
        } catch {
            recordingError = error.localizedDescription
        }
        await refreshRecordingStatus()
        isUpdatingSensorRecording = false
    }

    /// Stops every recording on the sensor. Returns false (and sets `recordingError`) if it fails.
    @discardableResult
    func stopSensorRecording() async -> Bool {
        guard connectedDevice != nil else { return false }
        isUpdatingSensorRecording = true
        recordingError = nil
        var stopped = true
        do {
            try await source.stopRecording()
        } catch {
            recordingError = error.localizedDescription
            stopped = false
        }
        await refreshRecordingStatus()
        isUpdatingSensorRecording = false
        return stopped
    }

    func refreshRecordingStatus() async {
        guard connectedDevice != nil else { return }
        if let streams = try? await source.recordingStatus() {
            sensorRecordingStreams = streams
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

    /// Starts the live streams for the Live Data screen. They aren't needed for the
    /// record-then-sync workflow, so they only run while that screen is open.
    func startLiveStreams() {
        guard connectedDevice != nil, streamTasks.isEmpty else { return }
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

    func stopLiveStreams() {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
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
