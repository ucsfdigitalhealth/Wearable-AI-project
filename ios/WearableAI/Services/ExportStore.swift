import Foundation
import Observation

/// A CSV file saved on the phone, ready to upload.
struct ExportedFile: Identifiable, Hashable {
    let url: URL
    /// The recording day, "yyyy-MM-dd" (also the Dropbox folder name).
    let day: String
    let sizeBytes: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Converts recordings to CSV files in Documents/Exports/<yyyy-MM-dd>/<stream>_<yyyyMMdd>.csv.
/// All recordings from the same day go into one file per stream.
@MainActor
@Observable
final class ExportStore {
    private(set) var files: [ExportedFile] = []

    @ObservationIgnored private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.documentsDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    /// Writes CSVs for the given recordings. Days that already have files are rewritten
    /// with all of that day's recordings from `allSessions`, so no data is lost.
    @discardableResult
    func export(
        days sessions: [RecordingSession],
        allSessions: [RecordingSession],
        streams: Set<SensorStream>
    ) -> [ExportedFile] {
        let calendar = Calendar.current
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startDate) })
        var written: [URL] = []

        for day in days {
            let daySessions = allSessions.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            let folder = directory.appending(path: Self.folderName(day), directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            for stream in SensorStream.allCases where streams.contains(stream) {
                guard daySessions.contains(where: { $0.sampleCount(stream) > 0 }) else { continue }
                let url = folder.appending(path: "\(stream.rawValue)_\(Self.compactDay(day)).csv")
                do {
                    try SessionCSV.csv(daySessions, stream).write(to: url, atomically: true, encoding: .utf8)
                    written.append(url)
                } catch {
                    print("Failed to write \(url.lastPathComponent): \(error)")
                }
            }
        }

        reload()
        return files.filter { written.contains($0.url) }
    }

    func reload() {
        let manager = FileManager.default
        let dayFolders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files = dayFolders.flatMap { folder -> [ExportedFile] in
            let csvs = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return csvs.filter { $0.pathExtension == "csv" }.map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return ExportedFile(url: url, day: folder.lastPathComponent, sizeBytes: Int64(size))
            }
        }
        .sorted { ($0.day, $0.name) > ($1.day, $1.name) }
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    static func folderName(_ day: Date) -> String {
        format(day, "yyyy-MM-dd")
    }

    private static func compactDay(_ day: Date) -> String {
        format(day, "yyyyMMdd")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
