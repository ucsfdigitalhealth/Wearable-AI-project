import Foundation

/// CSV layout for each stream (placeholder until the team's common format is final).
enum SessionCSV {
    static func header(_ stream: SensorStream) -> String {
        switch stream {
        case .ppg: "timestamp_ns,ppg0,ppg1,ppg2,ambient"
        case .acc: "timestamp_ns,x_mg,y_mg,z_mg"
        case .gyro: "timestamp_ns,x_dps,y_dps,z_dps"
        case .mag: "timestamp_ns,x_gauss,y_gauss,z_gauss"
        case .hr: "timestamp_ns,hr_bpm,ppi_ms,contact"
        }
    }

    static func rows(_ session: RecordingSession, _ stream: SensorStream) -> [String] {
        switch stream {
        case .ppg:
            session.ppg.map { "\($0.timestampNs),\($0.ppg0),\($0.ppg1),\($0.ppg2),\($0.ambient)" }
        case .acc:
            session.acc.map { "\($0.timestampNs),\($0.x),\($0.y),\($0.z)" }
        case .gyro:
            session.gyro.map { "\($0.timestampNs),\($0.x),\($0.y),\($0.z)" }
        case .mag:
            session.mag.map { "\($0.timestampNs),\($0.x),\($0.y),\($0.z)" }
        case .hr:
            session.hr.map {
                "\($0.timestampNs),\($0.bpm),\($0.ppiMs.map { String($0) }.joined(separator: ";")),\($0.contactDetected)"
            }
        }
    }

    static func csv(_ sessions: [RecordingSession], _ stream: SensorStream) -> String {
        let lines = [header(stream)] + sessions.sorted { $0.startDate < $1.startDate }.flatMap { rows($0, stream) }
        return lines.joined(separator: "\n") + "\n"
    }
}
