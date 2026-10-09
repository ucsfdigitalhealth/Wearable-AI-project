import Foundation

/// A recorded stretch of sensor data, saved on the phone.
struct RecordingSession: Codable, Identifiable {
    let id: UUID
    let deviceId: String
    let deviceName: String
    let startDate: Date
    let endDate: Date
    let ppg: [PPGSample]
    let acc: [ACCSample]
    let hr: [HRSample]

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var averageHR: Int? {
        guard !hr.isEmpty else { return nil }
        return hr.map(\.bpm).reduce(0, +) / hr.count
    }

    var minHR: Int? { hr.map(\.bpm).min() }
    var maxHR: Int? { hr.map(\.bpm).max() }
}

// Compare by id only, so views don't hash thousands of samples.
extension RecordingSession: Hashable {
    static func == (lhs: RecordingSession, rhs: RecordingSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
