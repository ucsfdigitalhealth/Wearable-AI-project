import SwiftUI

/// First-launch flow: welcome → how to wear it → connect the device → recording settings.
struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("studyName") private var studyName = "RAPHE Study"
    @State private var page = 0

    private let lastPage = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    WearPage().tag(1)
                    DeviceView().tag(2)
                    RecordingSettingsView(showsSaveButton: false).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.default, value: page)

                PageDots(count: lastPage + 1, current: page)
                    .padding(.vertical, 12)

                Button {
                    if page < lastPage {
                        page += 1
                    } else {
                        hasOnboarded = true
                    }
                } label: {
                    Text(page < lastPage ? "Next" : "Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding([.horizontal, .bottom])
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(studyName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        page -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(page == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if page < lastPage {
                            page += 1
                        } else {
                            hasOnboarded = true
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ArmbandIllustration()
            Text("Welcome!")
                .font(.largeTitle.bold())
            Text("Wear your Polar Verity Sense on your upper arm as shown.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

private struct WearPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ArmbandIllustration()
            Text("Wear it on your upper arm")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Strap the sensor snugly to your upper arm, on the outside.", systemImage: "1.circle.fill")
                Label("Keep it on during the day and while sleeping.", systemImage: "2.circle.fill")
                Label("The device records on its own. Open the app once a day to sync.", systemImage: "3.circle.fill")
                Label("Battery lasts about 30 hours. Charge it when the app reminds you.", systemImage: "4.circle.fill")
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

/// Placeholder artwork until we have a real photo of the armband.
struct ArmbandIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 160, height: 160)
            // Upper arm with the strap and sensor on it.
            Capsule()
                .fill(Color(red: 0.93, green: 0.76, blue: 0.62))
                .frame(width: 64, height: 150)
            RoundedRectangle(cornerRadius: 4)
                .fill(.black)
                .frame(width: 70, height: 20)
            DeviceIcon(size: 44)
        }
        .clipShape(Circle())
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .previewEnvironment()
}
