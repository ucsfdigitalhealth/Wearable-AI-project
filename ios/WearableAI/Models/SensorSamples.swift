import Foundation

// Placeholder data format. It mirrors the shapes the Polar BLE SDK delivers for the
// Verity Sense (PPG, accelerometer, gyroscope, magnetometer, HR + PPI) so the mock can
// be swapped for the real device later. Update these once the team's common format is final.

enum VeritySense {
    static let ppgSampleRate = 55.0   // Hz
    static let accSampleRate = 52.0   // Hz
    static let gyroSampleRate = 52.0  // Hz
    static let magSampleRate = 50.0   // Hz
}

/// The data streams the Verity Sense can record.
enum SensorStream: String, CaseIterable, Codable, Identifiable {
    case ppg, acc, gyro, mag, hr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ppg: "PPG"
        case .acc: "Accelerometer"
        case .gyro: "Gyroscope"
        case .mag: "Magnetometer"
        case .hr: "HR & PPI"
        }
    }

    var sampleRate: Double {
        switch self {
        case .ppg: VeritySense.ppgSampleRate
        case .acc: VeritySense.accSampleRate
        case .gyro: VeritySense.gyroSampleRate
        case .mag: VeritySense.magSampleRate
        case .hr: 1
        }
    }

    var rateLabel: String { "\(Int(sampleRate)) Hz" }

    var systemImage: String {
        switch self {
        case .ppg: "waveform.path.ecg"
        case .acc: "figure.run"
        case .gyro: "gyroscope"
        case .mag: "location.north.circle"
        case .hr: "heart.fill"
        }
    }
}

/// One raw optical (PPG) sample: three PPG channels plus the ambient light channel.
struct PPGSample: Codable, Hashable {
    /// Nanoseconds since the Unix epoch.
    let timestampNs: Int64
    let ppg0: Int32
    let ppg1: Int32
    let ppg2: Int32
    let ambient: Int32
}

/// One raw accelerometer sample, in milli-g.
struct ACCSample: Codable, Hashable {
    /// Nanoseconds since the Unix epoch.
    let timestampNs: Int64
    let x: Int32
    let y: Int32
    let z: Int32

    var magnitude: Double {
        let x = Double(x), y = Double(y), z = Double(z)
        return (x * x + y * y + z * z).squareRoot()
    }
}

/// One gyroscope sample, in degrees per second.
struct GyroSample: Codable, Hashable {
    let timestampNs: Int64
    let x: Float
    let y: Float
    let z: Float
}

/// One magnetometer sample, in gauss.
struct MagSample: Codable, Hashable {
    let timestampNs: Int64
    let x: Float
    let y: Float
    let z: Float
}

/// Heart rate as reported by the device (about once per second), with the
/// peak-to-peak intervals (PPI) detected since the previous sample.
struct HRSample: Codable, Hashable {
    /// Nanoseconds since the Unix epoch.
    let timestampNs: Int64
    let bpm: Int
    let ppiMs: [Int]
    let contactDetected: Bool
}

extension Date {
    var nanosecondsSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1_000_000_000)
    }

    init(nanosecondsSince1970 ns: Int64) {
        self.init(timeIntervalSince1970: Double(ns) / 1_000_000_000)
    }
}
