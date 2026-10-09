import Charts
import SwiftUI

/// Daily values over the past week or month.
struct TrendsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"

        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var period = Period.week

    var body: some View {
        let days = MockHealthData.recentDays(period.days)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TrendCard(title: "Steps", average: average(days.map(\.steps)).formatted(), unit: "avg / day") {
                        Chart(days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                                .foregroundStyle(.green)
                        }
                    }

                    TrendCard(title: "Resting Heart Rate", average: "\(average(days.map(\.restingHR)))", unit: "bpm avg") {
                        Chart(days) { day in
                            LineMark(x: .value("Day", day.date, unit: .day), y: .value("BPM", day.restingHR))
                                .foregroundStyle(.red)
                            PointMark(x: .value("Day", day.date, unit: .day), y: .value("BPM", day.restingHR))
                                .foregroundStyle(.red)
                                .symbolSize(period == .week ? 30 : 10)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                    }

                    TrendCard(title: "Sleep", average: formatMinutes(average(days.map(\.sleepMinutes))), unit: "avg / night") {
                        Chart(days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", Double(day.sleepMinutes) / 60))
                                .foregroundStyle(.purple)
                        }
                    }

                    TrendCard(title: "Active Minutes", average: "\(average(days.map(\.activeMinutes)))", unit: "min avg / day") {
                        Chart(days) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.activeMinutes))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
        }
    }

    private func average(_ values: [Int]) -> Int {
        values.isEmpty ? 0 : values.reduce(0, +) / values.count
    }
}

private struct TrendCard<Content: View>: View {
    let title: String
    let average: String
    let unit: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(average).font(.title2.weight(.semibold))
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
                .frame(height: 140)
        }
    }
}

#Preview {
    TrendsView()
}
