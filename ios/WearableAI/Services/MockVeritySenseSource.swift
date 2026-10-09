import Foundation

/// A pretend Polar Verity Sense. It acts like the real device: scanning finds devices
/// after a short delay, connecting takes a moment, and data arrives in batches at the
/// real sample rates.
final class MockVeritySenseSource: SensorDataSource {
    private var model = SyntheticSignalModel()
    private var settings = RecordingSettings.load()
    private var storedRecordings: [DeviceRecording] = []

    private let nearbyDevices = [
        DiscoveredDevice(id: "C8A3B2F1", name: "Polar Sense C8A3B2F1", rssi: -58),
        DiscoveredDevice(id: "D19E7740", name: "Polar Sense D19E7740", rssi: -77),
    ]

    func scan() -> AsyncStream<DiscoveredDevice> {
        let devices = nearbyDevices
        return AsyncStream { continuation in
            let task = Task {
                for device in devices {
                    try? await Task.sleep(for: .milliseconds(800))
                    if Task.isCancelled { break }
                    continuation.yield(device)
                }
                try? await Task.sleep(for: .seconds(2))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func connect(to device: DiscoveredDevice) async throws -> DeviceInfo {
        try await Task.sleep(for: .seconds(1.5))
        model = SyntheticSignalModel()
        storedRecordings = Self.makeStoredRecordings(streams: settings.enabledStreams)
        return DeviceInfo(
            id: device.id,
            name: device.name,
            model: "Polar Verity Sense (simulated)",
            firmwareVersion: "2.1.10",
            batteryPercent: .random(in: 60...95)
        )
    }

    func disconnect() async {}

    func apply(_ settings: RecordingSettings) async throws {
        try await Task.sleep(for: .milliseconds(300))
        self.settings = settings
    }

    func listRecordings() async throws -> [DeviceRecording] {
        try await Task.sleep(for: .milliseconds(300))
        return storedRecordings
    }

    func download(
        _ recording: DeviceRecording,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> RecordingSession {
        // Pretend BLE transfer: about 3 seconds per recording.
        let steps = 20
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(150))
            await progress(Double(step) / Double(steps))
        }
        return SyntheticSessionFactory.makeSession(
            start: recording.startDate,
            duration: recording.duration,
            streams: Set(recording.streams)
        )
    }

    func deleteFromDevice(_ recording: DeviceRecording) async throws {
        storedRecordings.removeAll { $0.id == recording.id }
    }

    /// Two recordings from earlier today, as if the participant wore the device.
    private static func makeStoredRecordings(streams: Set<SensorStream>) -> [DeviceRecording] {
        let streams = SensorStream.allCases.filter(streams.contains)
        let bytesPerSecond = streams.reduce(0.0) { $0 + $1.sampleRate * 16 }
        return [(-5.0, 300.0), (-2.5, 240.0)].map { hoursAgo, duration in
            let start = Date.now.addingTimeInterval(hoursAgo * 3600)
            return DeviceRecording(
                id: UUID().uuidString,
                startDate: start,
                duration: duration,
                sizeBytes: Int64(bytesPerSecond * duration),
                streams: streams
            )
        }
    }

    func ppgStream() -> AsyncStream<[PPGSample]> {
        let synth = PPGSynthesizer(model: model)
        return Self.batchedStream(rate: VeritySense.ppgSampleRate, makeSample: synth.sample(at:))
    }

    func accStream() -> AsyncStream<[ACCSample]> {
        Self.batchedStream(rate: VeritySense.accSampleRate, makeSample: model.accSample(at:))
    }

    func hrStream() -> AsyncStream<HRSample> {
        let model = model
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    continuation.yield(model.hrSample(at: .now))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends a batch of samples every 200 ms. Timestamps are evenly spaced at `rate`,
    /// so no samples are dropped.
    private static func batchedStream<Sample>(
        rate: Double,
        makeSample: @escaping (Date) -> Sample
    ) -> AsyncStream<[Sample]> {
        AsyncStream { continuation in
            let task = Task {
                let start = Date()
                var emitted = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    let due = Int(Date().timeIntervalSince(start) * rate)
                    guard due > emitted else { continue }
                    let batch = (emitted..<due).map { makeSample(start.addingTimeInterval(Double($0) / rate)) }
                    emitted = due
                    continuation.yield(batch)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
