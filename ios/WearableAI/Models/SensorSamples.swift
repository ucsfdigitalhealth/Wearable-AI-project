import Foundation

// Placeholder data format. It mirrors the shapes the Polar BLE SDK delivers for the
// Verity Sense (PolarPpgData / PolarAccelerometerData / PolarHrData) so the mock can be
// swapped for the real device later. Update these once the team's common format is final.

enum VeritySense {
    static let ppgSampleRate = 55.0  // Hz
    static let accSampleRate = 52.0  // Hz
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

/// Heart rate as reported by the device (about once per second).
struct HRSample: Codable, Hashable {
    /// Nanoseconds since the Unix epoch.
    let timestampNs: Int64
    let bpm: Int
    let rrIntervalsMs: [Int]
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
