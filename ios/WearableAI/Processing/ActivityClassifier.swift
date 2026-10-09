import Foundation

enum ActivityLevel: String {
    case resting = "Resting"
    case light = "Light"
    case active = "Active"

    var systemImage: String {
        switch self {
        case .resting: "figure.stand"
        case .light: "figure.walk"
        case .active: "figure.run"
        }
    }
}

/// Simple movement estimate from raw accelerometer data. This is a placeholder until
/// the real processing pipeline exists.
enum ActivityClassifier {
    /// Standard deviation of the acceleration magnitude, in mG. Near zero when still.
    static func movementIntensity(_ samples: some Collection<ACCSample>) -> Double {
        guard samples.count > 1 else { return 0 }
        let magnitudes = samples.map(\.magnitude)
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let variance = magnitudes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(magnitudes.count)
        return variance.squareRoot()
    }

    static func level(forIntensity intensity: Double) -> ActivityLevel {
        switch intensity {
        case ..<30: .resting
        case ..<120: .light
        default: .active
        }
    }

    static func classify(_ samples: some Collection<ACCSample>) -> ActivityLevel {
        level(forIntensity: movementIntensity(samples))
    }
}
