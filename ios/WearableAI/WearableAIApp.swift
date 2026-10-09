import SwiftUI

@main
struct WearableAIApp: App {
    private let services: AppServices

    init() {
        services = AppServices()

        // Launch argument `-demoConnect YES` connects to the simulated device right away
        // (used for CI screenshots).
        if UserDefaults.standard.bool(forKey: "demoConnect") {
            services.device.connect(to: DiscoveredDevice(id: "C8A3B2F1", name: "Polar Sense C8A3B2F1", rssi: -58))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(services)
        }
    }
}
