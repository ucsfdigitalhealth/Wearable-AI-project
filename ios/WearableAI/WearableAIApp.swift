import SwiftUI

@main
struct WearableAIApp: App {
    @State private var sessionStore: SessionStore
    @State private var deviceManager: DeviceManager

    init() {
        let store = SessionStore()
        _sessionStore = State(initialValue: store)
        // To use the real device, replace MockVeritySenseSource with a Polar SDK version.
        let manager = DeviceManager(source: MockVeritySenseSource(), sessionStore: store)
        _deviceManager = State(initialValue: manager)

        // Launch argument `-demoConnect YES` connects to the simulated device right away
        // (used for CI screenshots).
        if UserDefaults.standard.bool(forKey: "demoConnect") {
            manager.connect(to: DiscoveredDevice(id: "C8A3B2F1", name: "Polar Sense C8A3B2F1", rssi: -58))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessionStore)
                .environment(deviceManager)
        }
    }
}
