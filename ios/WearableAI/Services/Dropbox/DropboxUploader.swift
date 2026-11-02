// Real Dropbox upload, built on SwiftyDropbox.
//
// Compiles only with the `DROPBOX_SDK` build flag (see the note at the top of
// PolarVeritySenseSource.swift). Before it can work you also need to:
//   1. Create a Dropbox app (scoped access, "App folder" or "Full Dropbox") with the
//      `files.content.write` permission, and put its app key in StudyConfig.dropboxAppKey.
//   2. Put the same key in Support/Info-extra.plist as the URL scheme `db-<APP_KEY>`.
#if DROPBOX_SDK
import SwiftyDropbox
import UIKit

struct DropboxUploadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Uploads files in 8 MB chunks, so a full day of PPG (which can pass Dropbox's 150 MB
/// single-request limit) uploads reliably and a flaky connection only costs one chunk.
struct DropboxUploader: CloudUploader {
    private static let chunkSize = 8 * 1024 * 1024

    /// Call once at launch.
    @MainActor
    static func configure() {
        guard !StudyConfig.dropboxAppKey.isEmpty else { return }
        DropboxClientsManager.setupWithAppKey(StudyConfig.dropboxAppKey)
    }

    /// Call from `.onOpenURL` to finish the login that `link()` started.
    @MainActor
    static func handleRedirect(_ url: URL, completion: @escaping @MainActor () -> Void) {
        DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false) { _ in
            Task { @MainActor in completion() }
        }
    }

    var isLinked: Bool { DropboxClientsManager.authorizedClient != nil }

    @MainActor
    func link() {
        let scopes = ScopeRequest(scopeType: .user, scopes: ["files.content.write"], includeGrantedScopes: false)
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: nil,
            loadingStatusDelegate: nil,
            openURL: { UIApplication.shared.open($0) },
            scopeRequest: scopes
        )
    }

    func unlink() {
        DropboxClientsManager.unlinkClients()
    }

    func upload(
        _ file: URL,
        to remotePath: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxUploadError(message: "Dropbox isn't linked. Tap “Connect Dropbox” first.")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let total = Int((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

        var offset = 0
        var sessionId: String?
        repeat {
            let chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
            let isLast = offset + chunk.count >= total

            if let id = sessionId {
                let cursor = Files.UploadSessionCursor(sessionId: id, offset: UInt64(offset))
                if isLast {
                    let commit = Files.CommitInfo(path: remotePath, mode: .overwrite, autorename: false, mute: true)
                    _ = try await send(client.files.uploadSessionFinish(cursor: cursor, commit: commit, input: chunk))
                } else {
                    _ = try await send(client.files.uploadSessionAppendV2(cursor: cursor, input: chunk))
                }
            } else if isLast {
                // The whole file fits in one chunk.
                _ = try await send(client.files.upload(path: remotePath, mode: .overwrite, autorename: false, mute: true, input: chunk))
            } else {
                sessionId = try await send(client.files.uploadSessionStart(input: chunk)).sessionId
            }

            offset += chunk.count
            await progress(total > 0 ? Double(min(offset, total)) / Double(total) : 1)
            if isLast { break }
        } while true
    }

    /// Wraps SwiftyDropbox's callback API as async/throws.
    private func send<R: JSONSerializer, E: JSONSerializer>(
        _ request: UploadRequest<R, E>
    ) async throws -> R.ValueType {
        try await withCheckedThrowingContinuation { continuation in
            request.response { result, error in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: DropboxUploadError(message: error.map { "\($0)" } ?? "Upload failed"))
                }
            }
        }
    }
}
#endif
