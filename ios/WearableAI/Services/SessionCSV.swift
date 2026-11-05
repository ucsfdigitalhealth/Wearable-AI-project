import Foundation

/// CSV layout for each Verity Sense stream. It follows the sample files in the backend
/// (`backend/data/samples/demo_ppg.txt` and `demo_acc.txt`): `;` as the separator, a phone
/// timestamp (UTC, ISO 8601 with milliseconds) followed by the sensor timestamp in
/// nanoseconds since 2000-01-01 (Polar's epoch).
enum SessionCSV {
    static func header(_ stream: SensorStream) -> String {
        switch stream {
        case .ppg: "Phone timestamp;sensor timestamp [ns];channel 0;channel 1;channel 2;ambient"
        case .acc: "Phone timestamp;sensor timestamp [ns];X [mg];Y [mg];Z [mg]"
        case .gyro: "Phone timestamp;sensor timestamp [ns];X [dps];Y [dps];Z [dps]"
        case .mag: "Phone timestamp;sensor timestamp [ns];X [gauss];Y [gauss];Z [gauss]"
        case .hr: "Phone timestamp;sensor timestamp [ns];HR [bpm];PPI [ms];contact"
        }
    }

    static func rows(_ session: RecordingSession, _ stream: SensorStream) -> [String] {
        var time = TimestampColumns()
        switch stream {
        case .ppg:
            return session.ppg.map { "\(time.columns($0.timestampNs));\($0.ppg0);\($0.ppg1);\($0.ppg2);\($0.ambient)" }
        case .acc:
            return session.acc.map { "\(time.columns($0.timestampNs));\($0.x);\($0.y);\($0.z)" }
        case .gyro:
            return session.gyro.map { "\(time.columns($0.timestampNs));\($0.x);\($0.y);\($0.z)" }
        case .mag:
            return session.mag.map { "\(time.columns($0.timestampNs));\($0.x);\($0.y);\($0.z)" }
        case .hr:
            // Several PPI values in one second are joined with "|" so they stay in one column.
            return session.hr.map {
                "\(time.columns($0.timestampNs));\($0.bpm);\($0.ppiMs.map { String($0) }.joined(separator: "|"));\($0.contactDetected)"
            }
        }
    }

    static func csv(_ sessions: [RecordingSession], _ stream: SensorStream) -> String {
        let lines = [header(stream)] + sessions.sorted { $0.startDate < $1.startDate }.flatMap { rows($0, stream) }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Builds the "phone timestamp;sensor timestamp" pair for a Unix-epoch nanosecond time.
/// The formatted whole-second part is cached, since consecutive samples share it.
private struct TimestampColumns {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private var cachedSecond: Int64?
    private var cachedText = ""

    mutating func columns(_ unixNs: Int64) -> String {
        let second = unixNs / 1_000_000_000
        if second != cachedSecond {
            cachedSecond = second
            cachedText = Self.formatter.string(from: Date(timeIntervalSince1970: Double(second)))
        }
        let millis = (unixNs % 1_000_000_000) / 1_000_000
        let padded = millis < 10 ? "00\(millis)" : millis < 100 ? "0\(millis)" : "\(millis)"
        return "\(cachedText).\(padded);\(unixNs - VeritySense.polarEpochOffsetNs)"
    }
}
