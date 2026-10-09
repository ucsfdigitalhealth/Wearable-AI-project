import SwiftUI

enum AppTab: String {
    case home, trends, insights, more
}

/// Launch arguments used to open a specific screen (for CI screenshots), e.g.
/// `-demoTab more -demoScreen sync`.
enum DemoLaunch {
    static var tab: AppTab? { UserDefaults.standard.string(forKey: "demoTab").flatMap(AppTab.init) }
    static var screen: String? { UserDefaults.standard.string(forKey: "demoScreen") }
    static var autoStart: Bool { UserDefaults.standard.bool(forKey: "demoAutoStart") }
}

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        if showOnboarding {
            OnboardingView()
        } else {
            MainTabView()
        }
    }

    private var showOnboarding: Bool {
        if DemoLaunch.screen == "onboarding" { return true }
        if DemoLaunch.tab != nil { return false }
        return !hasOnboarded
    }
}

struct MainTabView: View {
    @State private var selection = DemoLaunch.tab ?? .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                .tag(AppTab.trends)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "lightbulb.fill") }
                .tag(AppTab.insights)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
    }
}

#Preview {
    MainTabView()
        .previewEnvironment()
}
