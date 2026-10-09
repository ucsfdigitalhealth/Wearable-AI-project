import SwiftUI

/// A rounded panel for the dashboard and session detail screens.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A single big number with a label, e.g. "72 bpm".
struct MetricCard: View {
    let title: String
    let value: String
    var unit: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        Card {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    HStack {
        MetricCard(title: "Heart rate", value: "72", unit: "bpm", systemImage: "heart.fill", tint: .red)
        MetricCard(title: "Activity", value: "Resting", systemImage: "figure.stand", tint: .green)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
