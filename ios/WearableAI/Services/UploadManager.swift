import Foundation
import Observation

/// Uploads a file to cloud storage. `MockDropboxUploader` stands in until the study's
/// Dropbox app is set up (that needs an app key from Ali, then the SwiftyDropbox SDK).
protocol CloudUploader {
    func upload(
        _ file: URL,
        to remotePath: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws
}

struct MockDropboxUploader: CloudUploader {
    func upload(
        _ file: URL,
        to remotePath: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(120))
            await progress(Double(step) / 10)
        }
    }
}

@MainActor
@Observable
final class UploadManager {
    enum Status: Equatable {
        case idle
        case uploading
        case complete(fileCount: Int, bytes: Int64, date: Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var bytesDone: Int64 = 0
    private(set) var bytesTotal: Int64 = 0
    /// Files already uploaded, so they aren't selected again by default.
    private(set) var uploadedFiles: Set<URL> = []

    @ObservationIgnored private let uploader: CloudUploader

    init(uploader: CloudUploader = MockDropboxUploader()) {
        self.uploader = uploader
    }

    var progress: Double {
        bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : 0
    }

    /// Dropbox layout from the study plan: /<study folder>/<participant>/<yyyy-MM-dd>/<file>.
    static func remotePath(for file: ExportedFile, participantId: String) -> String {
        "/VeritySense_Study/\(participantId)/\(file.day)/\(file.name)"
    }

    func upload(_ files: [ExportedFile], participantId: String) async {
        guard status != .uploading, !files.isEmpty else { return }
        status = .uploading
        bytesDone = 0
        bytesTotal = files.reduce(0) { $0 + $1.sizeBytes }

        do {
            for file in files {
                let alreadyDone = bytesDone
                try await uploader.upload(file.url, to: Self.remotePath(for: file, participantId: participantId)) { fraction in
                    self.bytesDone = alreadyDone + Int64(Double(file.sizeBytes) * fraction)
                }
                uploadedFiles.insert(file.url)
            }
            status = .complete(fileCount: files.count, bytes: bytesTotal, date: .now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
