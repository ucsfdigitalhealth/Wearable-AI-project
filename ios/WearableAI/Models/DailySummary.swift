import Foundation

/// One day's health summary. These values are mocked for now; they'll come from the
/// data-processing pipeline once it exists.
struct DailySummary: Identifiable {
    let date: Date
    let steps: Int
    let activeMinutes: Int
    let restingHR: Int
    let sleepMinutes: Int
    /// 0 (calm) – 100 (stressed), estimated from PPG.
    let stressScore: Int

    var id: Date { date }
}

enum StressLevel: String {
    case lower = "Lower than usual"
    case usual = "About usual"
    case higher = "Higher than usual"
}

/// Deterministic fake summaries: the same day always produces the same numbers.
enum MockHealthData {
    static func summary(for date: Date) -> DailySummary {
        let day = Calendar.current.startOfDay(for: date)
        var rng = SeededGenerator(seed: UInt64(day.timeIntervalSince1970 / 86_400))
        let weekend = Calendar.current.isDateInWeekend(day)
        let steps = Int(rng.next(in: 5_000...11_000)) - (weekend ? 1_500 : 0)
        return DailySummary(
            date: day,
            steps: steps,
            activeMinutes: steps / 160 + Int(rng.next(in: 0...15)),
            restingHR: Int(rng.next(in: 64...76)),
            sleepMinutes: Int(rng.next(in: 380...500)),
            stressScore: Int(rng.next(in: 20...70))
        )
    }

    /// The last `count` days, oldest first, ending today.
    static func recentDays(_ count: Int) -> [DailySummary] {
        (0..<count).reversed().map { offset in
            summary(for: Calendar.current.date(byAdding: .day, value: -offset, to: .now)!)
        }
    }

    /// Steps per hour for a day (24 values, zero after the current hour today).
    static func hourlySteps(for date: Date) -> [Int] {
        let summary = summary(for: date)
        var rng = SeededGenerator(seed: UInt64(summary.date.timeIntervalSince1970) &+ 7)
        let weights = (0..<24).map { hour -> Double in
            guard (7...22).contains(hour) else { return 0 }
            return rng.next(in: 0.2...1.0) * ([8, 12, 17, 18].contains(hour) ? 2.5 : 1)
        }
        let total = weights.reduce(0, +)
        let currentHour = Calendar.current.isDateInToday(date) ? Calendar.current.component(.hour, from: .now) : 23
        return weights.enumerated().map { hour, weight in
            hour <= currentHour ? Int(Double(summary.steps) * weight / total) : 0
        }
    }

    /// Average heart rate per hour so far (one value per hour).
    static func hourlyHeartRate(for date: Date) -> [Int] {
        let summary = summary(for: date)
        var rng = SeededGenerator(seed: UInt64(summary.date.timeIntervalSince1970) &+ 13)
        let currentHour = Calendar.current.isDateInToday(date) ? Calendar.current.component(.hour, from: .now) : 23
        return (0...currentHour).map { hour in
            let awake = (7...22).contains(hour)
            return summary.restingHR + (awake ? Int(rng.next(in: 5...25)) : Int(rng.next(in: -6...0)))
        }
    }
}

/// Small deterministic random number generator (SplitMix64).
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt64() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
