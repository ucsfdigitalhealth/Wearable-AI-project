// Real Polar Verity Sense support, built on the Polar BLE SDK.
//
// This file only compiles when the `POLAR_SDK` build flag is set (see ios/README.md), because
// it was written without a Mac to compile against. The "Build with Polar + Dropbox SDKs" CI job
// compiles it on every push; once that job is green, add POLAR_SDK to
// SWIFT_ACTIVE_COMPILATION_CONDITIONS in the project to turn it on for the main build.
#if POLAR_SDK
import CoreBluetooth
import Foundation
import PolarBleSdk
import RxSwift

enum PolarSourceError: LocalizedError {
    case notConnected
    case timedOut
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "The Verity Sense isn't connected."
        case .timedOut: "Timed out connecting to the Verity Sense."
        case .unsupported(let what): "Unsupported: \(what)"
        }
    }
}

/// Talks to a real Polar Verity Sense over Bluetooth. Replaces `MockVeritySenseSource`.
final class PolarVeritySenseSource: NSObject, SensorDataSource {
    /// Polar timestamps count nanoseconds from 2000-01-01; we store Unix-epoch nanoseconds.
    private static let polarEpochOffsetNs: Int64 = 946_684_800 * 1_000_000_000

    private var api: PolarBleApi!
    private var deviceId: String?
    private var firmware = "–"
    private var battery = 0
    private var connectContinuation: CheckedContinuation<Void, Error>?
    /// Offline recording files on the device, grouped by recording folder.
    private var entriesByRecording: [String: [PolarOfflineRecordingEntry]] = [:]

    override init() {
        super.init()
        api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue.main,
            features: [
                .feature_hr,
                .feature_battery_info,
                .feature_device_info,
                .feature_polar_online_streaming,
                .feature_polar_offline_recording,
                .feature_polar_device_time_setup,
            ]
        )
        api.observer = self
        api.deviceInfoObserver = self
    }

    // MARK: - Scan / connect

    func scan() -> AsyncStream<DiscoveredDevice> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await info in self.api.searchForDevice().values {
                        guard info.name.contains("Sense") else { continue }
                        continuation.yield(DiscoveredDevice(id: info.deviceId, name: info.name, rssi: Int(info.rssi)))
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func connect(to device: DiscoveredDevice) async throws -> DeviceInfo {
        deviceId = device.id
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.connectContinuation = continuation
                    do { try self.api.connectToDevice(device.id) } catch {
                        self.connectContinuation = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw PolarSourceError.timedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
        // Keep the device clock right so offline recordings get correct timestamps.
        try? await api.setLocalTime(device.id, time: .now, zone: .current).value
        return DeviceInfo(id: device.id, name: device.name, model: "Polar Verity Sense", firmwareVersion: firmware, batteryPercent: battery)
    }

    func disconnect() async {
        if let deviceId { try? api.disconnectFromDevice(deviceId) }
        deviceId = nil
        entriesByRecording = [:]
    }

    // MARK: - Offline recordings

    func apply(_ settings: RecordingSettings) async throws {
        let id = try requireId()
        for stream in SensorStream.allCases {
            let feature = Self.dataType(stream)
            if settings.enabledStreams.contains(stream) {
                let sensorSettings = stream == .hr ? nil : try await api.requestOfflineRecordingSettings(id, feature: feature).value.maxSettings()
                // Fails harmlessly if this stream is already recording.
                try? await api.startOfflineRecording(id, feature: feature, settings: sensorSettings, secret: nil).value
            } else {
                try? await api.stopOfflineRecording(id, feature: feature).value
            }
        }
    }

    func listRecordings() async throws -> [DeviceRecording] {
        let id = try requireId()
        var entries: [PolarOfflineRecordingEntry] = []
        for try await entry in api.listOfflineRecordings(id).values { entries.append(entry) }

        // Streams recorded together share a folder: e.g. /U/0/20260102/R/093000/{ACC0,PPG0}.REC
        entriesByRecording = Dictionary(grouping: entries) {
            ($0.path as NSString).deletingLastPathComponent
        }
        return entriesByRecording.compactMap { folder, entries in
            guard let first = entries.min(by: { $0.date < $1.date }) else { return nil }
            let streams = entries.compactMap { Self.stream($0.type) }
            let size = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
            let bytesPerSecond = streams.reduce(0.0) { $0 + $1.sampleRate * 16 }
            return DeviceRecording(
                id: folder,
                startDate: first.date,
                duration: bytesPerSecond > 0 ? Double(size) / bytesPerSecond : 0,  // estimate until downloaded
                sizeBytes: size,
                streams: streams
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    func download(
        _ recording: DeviceRecording,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> RecordingSession {
        let id = try requireId()
        let entries = entriesByRecording[recording.id] ?? []
        var ppg: [PPGSample] = [], acc: [ACCSample] = [], gyro: [GyroSample] = []
        var mag: [MagSample] = [], hr: [HRSample] = []

        for (index, entry) in entries.enumerated() {
            let data = try await api.getOfflineRecord(id, entry: entry, secret: nil).value
            switch data {
            case .accOfflineRecordingData(let d, _, _):
                acc += d.map { ACCSample(timestampNs: unix($0.timeStamp), x: $0.x, y: $0.y, z: $0.z) }
            case .ppgOfflineRecordingData(let d, _, _):
                ppg += d.samples.compactMap { sample in
                    let c = sample.channelSamples
                    guard c.count >= 4 else { return nil }
                    return PPGSample(timestampNs: unix(sample.timeStamp), ppg0: c[0], ppg1: c[1], ppg2: c[2], ambient: c[3])
                }
            case .gyroOfflineRecordingData(let d, _, _):
                gyro += d.map { GyroSample(timestampNs: unix($0.timeStamp), x: $0.x, y: $0.y, z: $0.z) }
            case .magOfflineRecordingData(let d, _, _):
                mag += d.map { MagSample(timestampNs: unix($0.timeStamp), x: $0.x, y: $0.y, z: $0.z) }
            case .hrOfflineRecordingData(let d, let start):
                // HR samples carry no timestamps: one per second from the start time.
                hr += d.enumerated().map { offset, s in
                    HRSample(
                        timestampNs: start.addingTimeInterval(Double(offset)).nanosecondsSince1970,
                        bpm: Int(s.hr),
                        ppiMs: s.rrsMs,
                        contactDetected: s.contactStatus
                    )
                }
            default:
                break
            }
            await progress(Double(index + 1) / Double(max(entries.count, 1)))
        }

        let end = [ppg.last?.timestampNs, acc.last?.timestampNs, hr.last?.timestampNs].compactMap { $0 }.max()
            .map { Date(nanosecondsSince1970: $0) } ?? recording.startDate.addingTimeInterval(recording.duration)
        return RecordingSession(
            id: UUID(),
            deviceId: id,
            deviceName: "Polar Verity Sense \(id)",
            startDate: recording.startDate,
            endDate: end,
            ppg: ppg, acc: acc, gyro: gyro, mag: mag, hr: hr
        )
    }

    func deleteFromDevice(_ recording: DeviceRecording) async throws {
        let id = try requireId()
        for entry in entriesByRecording[recording.id] ?? [] {
            try await api.removeOfflineRecord(id, entry: entry).value
        }
        entriesByRecording[recording.id] = nil
    }

    // MARK: - Live streaming

    func ppgStream() -> AsyncStream<[PPGSample]> {
        liveStream(.ppg) { api, id, settings in
            api.startPpgStreaming(id, settings: settings).map { data in
                data.samples.compactMap { sample -> PPGSample? in
                    let c = sample.channelSamples
                    guard c.count >= 4 else { return nil }
                    return PPGSample(timestampNs: self.unix(sample.timeStamp), ppg0: c[0], ppg1: c[1], ppg2: c[2], ambient: c[3])
                }
            }
        }
    }

    func accStream() -> AsyncStream<[ACCSample]> {
        liveStream(.acc) { api, id, settings in
            api.startAccStreaming(id, settings: settings).map { data in
                data.map { ACCSample(timestampNs: self.unix($0.timeStamp), x: $0.x, y: $0.y, z: $0.z) }
            }
        }
    }

    func hrStream() -> AsyncStream<HRSample> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let id = try self.requireId()
                    for try await batch in self.api.startHrStreaming(id).values {
                        for s in batch {
                            continuation.yield(HRSample(
                                timestampNs: Date.now.nanosecondsSince1970,
                                bpm: Int(s.hr),
                                ppiMs: s.rrsMs,
                                contactDetected: s.contactStatus
                            ))
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Requests the sensor's maximum settings, starts a stream and forwards its batches.
    private func liveStream<T>(
        _ feature: PolarDeviceDataType,
        start: @escaping (PolarBleApi, String, PolarSensorSetting) -> Observable<[T]>
    ) -> AsyncStream<[T]> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let id = try self.requireId()
                    let settings = try await self.api.requestStreamSettings(id, feature: feature).value.maxSettings()
                    for try await batch in start(self.api, id, settings).values {
                        continuation.yield(batch)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func requireId() throws -> String {
        guard let deviceId else { throw PolarSourceError.notConnected }
        return deviceId
    }

    /// Converts a sensor timestamp to Unix-epoch nanoseconds. Values already in Unix time
    /// (larger than ~2027 in Polar time) are left alone.
    private func unix(_ polarNs: UInt64) -> Int64 {
        let value = Int64(clamping: polarNs)
        return value < 1_200_000_000_000_000_000 ? value + Self.polarEpochOffsetNs : value
    }

    private static func dataType(_ stream: SensorStream) -> PolarDeviceDataType {
        switch stream {
        case .ppg: .ppg
        case .acc: .acc
        case .gyro: .gyro
        case .mag: .magnetometer
        case .hr: .hr
        }
    }

    private static func stream(_ type: PolarDeviceDataType) -> SensorStream? {
        switch type {
        case .ppg: .ppg
        case .acc: .acc
        case .gyro: .gyro
        case .magnetometer: .mag
        case .hr: .hr
        default: nil
        }
    }
}

// MARK: - Connection callbacks

extension PolarVeritySenseSource: PolarBleApiObserver {
    func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {}

    func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        connectContinuation?.resume()
        connectContinuation = nil
    }

    func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo, pairingError: Bool) {
        if let continuation = connectContinuation {
            continuation.resume(throwing: PolarSourceError.notConnected)
            connectContinuation = nil
        }
    }
}

extension PolarVeritySenseSource: PolarBleApiDeviceInfoObserver {
    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        battery = Int(batteryLevel)
    }

    func batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState) {}

    func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {}

    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        // 2A26 is the standard "Firmware Revision String" characteristic.
        if uuid == CBUUID(string: "2A26") { firmware = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
#endif
