import SwiftUI

struct Insight: Identifiable {
    let id: String
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
}

/// Compares the latest day/week/month with the period before it.
enum InsightEngine {
    enum Period: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"

        var id: String { rawValue }
        var length: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            }
        }
        var baselineLength: Int { self == .day ? 7 : length }
        var comparison: String {
            switch self {
            case .day: "than your 7-day average"
            case .week: "than the week before"
            case .month: "than the month before"
            }
        }
    }

    static func insights(for period: Period) -> [Insight] {
        let days = MockHealthData.recentDays(period.length + period.baselineLength)
        let current = Array(days.suffix(period.length))
        let baseline = Array(days.prefix(period.baselineLength))

        func avg(_ values: [DailySummary], _ key: KeyPath<DailySummary, Int>) -> Double {
            Double(values.map { $0[keyPath: key] }.reduce(0, +)) / Double(max(values.count, 1))
        }

        let stepsChange = (avg(current, \.steps) - avg(baseline, \.steps)) / avg(baseline, \.steps) * 100
        let hrChange = avg(current, \.restingHR) - avg(baseline, \.restingHR)
        let sleepChange = avg(current, \.sleepMinutes) - avg(baseline, \.sleepMinutes)
        let stressChange = avg(current, \.stressScore) - avg(baseline, \.stressScore)

        return [
            Insight(
                id: "activity",
                title: "Activity",
                message: "You were \(Int(abs(stepsChange).rounded()))% \(stepsChange >= 0 ? "more" : "less") active \(period.comparison).",
                systemImage: "figure.run",
                tint: .orange
            ),
            Insight(
                id: "hr",
                title: "Heart Rate",
                message: abs(hrChange) < 1
                    ? "Your resting HR was about the same as usual."
                    : "Your resting HR was \(Int(abs(hrChange).rounded())) bpm \(hrChange < 0 ? "lower" : "higher") \(period.comparison).",
                systemImage: "heart.fill",
                tint: .red
            ),
            Insight(
                id: "sleep",
                title: "Sleep",
                message: "You slept \(Int(abs(sleepChange).rounded())) min \(sleepChange >= 0 ? "longer" : "shorter") \(period.comparison).",
                systemImage: "moon.zzz.fill",
                tint: .purple
            ),
            Insight(
                id: "stress",
                title: "Stress (PPG)",
                message: stressChange < -3
                    ? "Lower than your usual average. Nice!"
                    : stressChange > 3 ? "Higher than your usual average. Try to take a break." : "About the same as usual.",
                systemImage: "sun.max.fill",
                tint: .orange
            ),
        ]
    }
}

struct InsightsView: View {
    @State private var period = InsightEngine.Period.day

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(InsightEngine.Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(InsightEngine.insights(for: period)) { insight in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: insight.systemImage)
                                .font(.title2)
                                .foregroundStyle(insight.tint)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title).font(.headline)
                                Text(insight.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Insights are simulated until the data-processing pipeline is ready.")
                }
            }
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
