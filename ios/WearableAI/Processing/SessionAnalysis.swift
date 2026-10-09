import Foundation

/// Summary values and chart series derived from a recorded session.
struct SessionAnalysis {
    struct Point: Identifiable {
        let id: Int
        let minutes: Double
        let value: Double
    }

    let heartRate: [Point]
    /// Movement intensity (mG) per one-second window.
    let movement: [Point]
    /// Share of seconds classified as light or active.
    let activeFraction: Double

    init(session: RecordingSession) {
        let startNs = session.startDate.nanosecondsSince1970
        func minutes(_ ns: Int64) -> Double { Double(ns - startNs) / 60_000_000_000 }

        heartRate = session.hr.enumerated().map { index, sample in
            Point(id: index, minutes: minutes(sample.timestampNs), value: Double(sample.bpm))
        }

        let windowSize = Int(VeritySense.accSampleRate)
        var points: [Point] = []
        var activeSeconds = 0
        var start = 0
        while start < session.acc.count {
            let window = session.acc[start..<min(start + windowSize, session.acc.count)]
            let intensity = ActivityClassifier.movementIntensity(window)
            if ActivityClassifier.level(forIntensity: intensity) != .resting {
                activeSeconds += 1
            }
            points.append(Point(id: points.count, minutes: minutes(window.first!.timestampNs), value: intensity))
            start += windowSize
        }
        movement = points
        activeFraction = points.isEmpty ? 0 : Double(activeSeconds) / Double(points.count)
    }
}
