import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Turns one data stream from a session into a CSV file for the share sheet.
struct SessionCSVExport: Transferable {
    enum Stream: String, CaseIterable, Identifiable {
        case ppg, acc, hr

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ppg: "PPG"
            case .acc: "Accelerometer"
            case .hr: "Heart rate"
            }
        }
    }

    let session: RecordingSession
    let stream: Stream

    var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "wearableai_\(stream.rawValue)_\(formatter.string(from: session.startDate)).csv"
    }

    func csv() -> String {
        var lines: [String]
        switch stream {
        case .ppg:
            lines = ["timestamp_ns,ppg0,ppg1,ppg2,ambient"]
            lines += session.ppg.map { "\($0.timestampNs),\($0.ppg0),\($0.ppg1),\($0.ppg2),\($0.ambient)" }
        case .acc:
            lines = ["timestamp_ns,x_mg,y_mg,z_mg"]
            lines += session.acc.map { "\($0.timestampNs),\($0.x),\($0.y),\($0.z)" }
        case .hr:
            lines = ["timestamp_ns,hr_bpm,rr_ms,contact"]
            lines += session.hr.map {
                let rr = $0.rrIntervalsMs.map(String.init).joined(separator: ";")
                return "\($0.timestampNs),\($0.bpm),\(rr),\($0.contactDetected)"
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try export.csv().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
