import SwiftUI

/// Creates the app's shared objects and puts them in the SwiftUI environment.
@MainActor
struct AppServices {
    let sessions: SessionStore
    let exports: ExportStore
    let device: DeviceManager
    let sync: SyncManager
    let upload: UploadManager
    let passive: PassiveDataCollector

    /// - Parameter storageRoot: where to keep data; `nil` uses the app's Documents folder.
    init(storageRoot: URL? = nil) {
        sessions = SessionStore(directory: storageRoot?.appending(path: "Sessions"))
        exports = ExportStore(directory: storageRoot?.appending(path: "Exports"))
        device = DeviceManager(source: Self.makeSource(), sessionStore: sessions)
        sync = SyncManager()
        upload = UploadManager(uploader: Self.makeUploader())
        passive = PassiveDataCollector(exportsDirectory: storageRoot?.appending(path: "Exports"))

        // Make sure the sample recordings also have CSV files to upload.
        if exports.files.isEmpty && !sessions.sessions.isEmpty {
            exports.export(days: sessions.sessions, allSessions: sessions.sessions, streams: Set(SensorStream.allCases))
        }
    }

    /// The real Verity Sense when it is available and switched on in Settings; otherwise the simulator.
    private static func makeSource() -> SensorDataSource {
        #if POLAR_SDK
        if StudyConfig.useRealDevice { return PolarVeritySenseSource() }
        #endif
        return MockVeritySenseSource()
    }

    private static func makeUploader() -> CloudUploader {
        #if DROPBOX_SDK
        if StudyConfig.dropboxAvailable {
            DropboxUploader.configure()
            return DropboxUploader()
        }
        #endif
        return MockDropboxUploader()
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
            .environment(services.passive)
    }

    @MainActor
    func previewEnvironment() -> some View {
        appEnvironment(AppServices.preview)
    }
}
