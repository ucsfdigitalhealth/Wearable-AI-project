import SwiftUI

/// Creates the app's shared objects and puts them in the SwiftUI environment.
@MainActor
struct AppServices {
    let sessions: SessionStore
    let exports: ExportStore
    let device: DeviceManager
    let sync: SyncManager
    let upload: UploadManager

    /// - Parameter storageRoot: where to keep data; `nil` uses the app's Documents folder.
    init(storageRoot: URL? = nil) {
        sessions = SessionStore(directory: storageRoot?.appending(path: "Sessions"))
        exports = ExportStore(directory: storageRoot?.appending(path: "Exports"))
        // To use the real device, replace MockVeritySenseSource with a Polar SDK version.
        device = DeviceManager(source: MockVeritySenseSource(), sessionStore: sessions)
        sync = SyncManager()
        upload = UploadManager()

        // Make sure the sample recordings also have CSV files to upload.
        if exports.files.isEmpty && !sessions.sessions.isEmpty {
            exports.export(days: sessions.sessions, allSessions: sessions.sessions, streams: Set(SensorStream.allCases))
        }
    }

    static let preview = AppServices(storageRoot: FileManager.default.temporaryDirectory.appending(path: "Preview"))
}

extension View {
    @MainActor
    func appEnvironment(_ services: AppServices) -> some View {
        self
            .environment(services.sessions)
            .environment(services.exports)
            .environment(services.device)
            .environment(services.sync)
            .environment(services.upload)
    }

    @MainActor
    func previewEnvironment() -> some View {
        appEnvironment(AppServices.preview)
    }
}
