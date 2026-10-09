import SwiftUI

enum AppTab: String {
    case live, device, sessions, settings
}

struct RootView: View {
    // Launch argument `-demoTab <name>` picks the starting tab (used for CI screenshots).
    @State private var selection = AppTab(rawValue: UserDefaults.standard.string(forKey: "demoTab") ?? "") ?? .live

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Live", systemImage: "waveform.path.ecg") }
                .tag(AppTab.live)
            DeviceView()
                .tabItem { Label("Device", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.device)
            SessionsListView()
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.sessions)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
