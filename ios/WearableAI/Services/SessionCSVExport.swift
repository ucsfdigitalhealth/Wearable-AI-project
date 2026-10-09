import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Turns one stream from a single recording into a CSV file for the share sheet.
struct SessionCSVExport: Transferable {
    let session: RecordingSession
    let stream: SensorStream

    var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(stream.rawValue)_\(formatter.string(from: session.startDate)).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try SessionCSV.csv([export.session], export.stream).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
