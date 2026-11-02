import Foundation

/// The kinds of passive phone data, each saved to its own CSV file per day.
enum PassiveStream: String, CaseIterable, Identifiable {
    case gps, motion, activity, screen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gps: "Location (GPS)"
        case .motion: "Phone accelerometer & gyroscope"
        case .activity: "Activity & steps"
        case .screen: "Screen & app state"
        }
    }

    var systemImage: String {
        switch self {
        case .gps: "location.fill"
        case .motion: "iphone.gen3.radiowaves.left.and.right"
        case .activity: "figure.walk"
        case .screen: "iphone"
        }
    }

    /// File name prefix. The `phone_` prefix keeps these apart from the Verity Sense streams.
    var filePrefix: String { "phone_\(rawValue)" }

    var header: String {
        switch self {
        case .gps: "timestamp_ns,lat,lon,altitude_m,h_accuracy_m,speed_mps,course_deg"
        case .motion: "timestamp_ns,acc_x_g,acc_y_g,acc_z_g,gyro_x_rps,gyro_y_rps,gyro_z_rps"
        case .activity: "timestamp_ns,activity,confidence,steps_total"
        case .screen: "timestamp_ns,event"
        }
    }
}

/// Appends rows to `Exports/<yyyy-MM-dd>/phone_<stream>_<yyyyMMdd>.csv` — the same folders
/// the Verity Sense exports use, so passive files show up in Export and Upload automatically.
/// Rows are buffered and written in batches; safe to call from any thread.
final class PassiveCSVWriter: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "passive-csv-writer")
    private var buffers: [URL: [String]] = [:]
    private let flushThreshold = 200

    init(directory: URL) {
        self.directory = directory
    }

    func append(_ stream: PassiveStream, at date: Date = .now, row: String) {
        queue.async {
            let url = self.fileURL(stream, day: date)
            self.buffers[url, default: []].append(row)
            if self.buffers[url]!.count >= self.flushThreshold {
                self.flush(url)
            }
        }
    }

    func flush() {
        queue.async {
            for url in Array(self.buffers.keys) { self.flush(url) }
        }
    }

    // MARK: - Private (run on `queue`)

    private func flush(_ url: URL) {
        guard let rows = buffers[url], !rows.isEmpty else { return }
        buffers[url] = []

        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var text = rows.joined(separator: "\n") + "\n"
        if !manager.fileExists(atPath: url.path), let stream = PassiveStream.allCases.first(where: { url.lastPathComponent.hasPrefix($0.filePrefix) }) {
            text = stream.header + "\n" + text
        }

        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func fileURL(_ stream: PassiveStream, day: Date) -> URL {
        let folder = directory.appending(path: Self.format(day, "yyyy-MM-dd"), directoryHint: .isDirectory)
        return folder.appending(path: "\(stream.filePrefix)_\(Self.format(day, "yyyyMMdd")).csv")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
