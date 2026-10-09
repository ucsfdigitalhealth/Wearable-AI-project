import Charts
import SwiftUI

/// Raw PPG waveform (channel 0) for the last few seconds.
struct PPGWaveformChart: View {
    let samples: [PPGSample]

    var body: some View {
        let latest = samples.last?.timestampNs ?? 0
        Chart(samples, id: \.timestampNs) { sample in
            LineMark(
                x: .value("Seconds", Double(sample.timestampNs - latest) / 1_000_000_000),
                y: .value("PPG", Double(sample.ppg0))
            )
            .foregroundStyle(.red)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXScale(domain: -LiveDisplay.windowSeconds...0)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: 1)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(Int(seconds))s")
                    }
                }
            }
        }
        .frame(height: 140)
    }
}

/// Accelerometer x/y/z for the last few seconds.
struct AccelerometerChart: View {
    let samples: [ACCSample]

    private struct Point: Identifiable {
        let id: Int
        let seconds: Double
        let axis: String
        let mg: Double
    }

    private var points: [Point] {
        let latest = samples.last?.timestampNs ?? 0
        var points: [Point] = []
        // Every 2nd sample is enough for a phone-sized chart.
        for sample in stride(from: 0, to: samples.count, by: 2).map({ samples[$0] }) {
            let seconds = Double(sample.timestampNs - latest) / 1_000_000_000
            points.append(Point(id: points.count, seconds: seconds, axis: "X", mg: Double(sample.x)))
            points.append(Point(id: points.count, seconds: seconds, axis: "Y", mg: Double(sample.y)))
            points.append(Point(id: points.count, seconds: seconds, axis: "Z", mg: Double(sample.z)))
        }
        return points
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Seconds", point.seconds),
                y: .value("mG", point.mg),
                series: .value("Axis", point.axis)
            )
            .foregroundStyle(by: .value("Axis", point.axis))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartForegroundStyleScale(["X": Color.orange, "Y": Color.blue, "Z": Color.teal])
        .chartXScale(domain: -LiveDisplay.windowSeconds...0)
        .chartXAxis {
            AxisMarks(values: .stride(by: 1)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(Int(seconds))s")
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

/// Heart rate over the last couple of minutes.
struct HeartRateTrendChart: View {
    let samples: [HRSample]

    var body: some View {
        Chart(samples, id: \.timestampNs) { sample in
            LineMark(
                x: .value("Time", Date(nanosecondsSince1970: sample.timestampNs)),
                y: .value("BPM", sample.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 140)
    }
}
