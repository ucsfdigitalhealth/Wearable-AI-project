import Foundation

/// A device found while scanning.
struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let rssi: Int
}

/// Details about the connected device.
struct DeviceInfo: Hashable {
    let id: String
    let name: String
    let model: String
    let firmwareVersion: String
    var batteryPercent: Int
}

/// A recording stored on the device that hasn't been downloaded to the phone yet.
struct DeviceRecording: Identifiable, Hashable {
    let id: String
    let startDate: Date
    let duration: TimeInterval
    let sizeBytes: Int64
    let streams: [SensorStream]
}

enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case continuous
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuous: "Continuous"
        case .scheduled: "Scheduled (e.g., daytime only)"
        }
    }
}

/// What the device records while offline.
struct RecordingSettings: Codable, Equatable {
    var enabledStreams: Set<SensorStream> = [.ppg, .acc, .hr]
    var mode: RecordingMode = .continuous

    private static let key = "recordingSettings"

    static func load() -> RecordingSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(RecordingSettings.self, from: data)
        else { return RecordingSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
