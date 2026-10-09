import SwiftUI

extension View {
    /// Adds the app's environment objects to a preview, saving data to a temp folder.
    @MainActor
    func previewEnvironment() -> some View {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PreviewSessions")
        let store = SessionStore(directory: directory)
        if store.sessions.isEmpty {
            store.generateSampleSessions()
        }
        return self
            .environment(store)
            .environment(DeviceManager(source: MockVeritySenseSource(), sessionStore: store))
    }
}
