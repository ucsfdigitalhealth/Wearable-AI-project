import Foundation

/// Generates realistic-looking fake data: resting periods broken up by short walks.
/// Heart rate rises while walking, and walking adds motion to the accelerometer and
/// noise to the PPG signal.
struct SyntheticSignalModel {
    let origin: Date
    /// Random value per model, so each session looks a bit different.
    let variation: Double

    init(origin: Date = .now, variation: Double = .random(in: 0...1)) {
        self.origin = origin
        self.variation = variation
    }

    /// 0 at rest, 1 while walking. Repeats every 90 s and ramps smoothly in and out.
    func walkingIntensity(at date: Date) -> Double {
        let period = 90.0
        let t = max(0, date.timeIntervalSince(origin)) + variation * period
        let phase = t.truncatingRemainder(dividingBy: period)
        let walkStart = 50.0, walkEnd = 85.0, ramp = 5.0
        let rise = (phase - walkStart) / ramp
        let fall = (walkEnd - phase) / ramp
        return min(1, max(0, min(rise, fall)))
    }

    func heartRate(at date: Date) -> Double {
        let t = date.timeIntervalSince(origin)
        let resting = 62 + 10 * variation
        return resting
            + 3 * sin(2 * .pi * t / 41)
            + 1.5 * sin(2 * .pi * t / 11 + variation * 6)
            + 30 * walkingIntensity(at: date)
    }

    func accSample(at date: Date) -> ACCSample {
        let t = date.timeIntervalSince(origin)
        let walk = walkingIntensity(at: date)
        let cadence = 1.8  // steps per second
        func noise() -> Double { .random(in: -8...8) }

        let x = -50 + 20 * sin(2 * .pi * t / 30) + walk * 350 * sin(2 * .pi * cadence * t) + noise()
        let y = -980 + walk * 250 * sin(2 * .pi * 2 * cadence * t + 0.5) + noise()
        let z = 120 + walk * 180 * sin(2 * .pi * cadence * t + 1.2) + noise()
        return ACCSample(timestampNs: date.nanosecondsSince1970, x: Int32(x), y: Int32(y), z: Int32(z))
    }

    func hrSample(at date: Date) -> HRSample {
        let hr = heartRate(at: date)
        return HRSample(
            timestampNs: date.nanosecondsSince1970,
            bpm: Int(hr.rounded()),
            rrIntervalsMs: [Int((60_000 / hr).rounded())],
            contactDetected: true
        )
    }
}

/// Builds the PPG waveform one sample at a time, keeping track of where it is in the
/// current heartbeat.
final class PPGSynthesizer {
    private let model: SyntheticSignalModel
    private var beatPhase = 0.0
    private var lastDate: Date?

    init(model: SyntheticSignalModel) {
        self.model = model
    }

    func sample(at date: Date) -> PPGSample {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        beatPhase += model.heartRate(at: date) / 60 * dt
        beatPhase -= beatPhase.rounded(.down)

        // Main systolic peak plus a smaller dicrotic wave.
        let p = beatPhase
        let pulse = exp(-pow((p - 0.15) / 0.07, 2)) + 0.35 * exp(-pow((p - 0.45) / 0.08, 2))

        let t = date.timeIntervalSince(model.origin)
        let breathing = 1500 * sin(2 * .pi * t / 4)
        let motion = model.walkingIntensity(at: date) * 900 * sin(2 * .pi * 1.8 * t)
        func channel(base: Double, gain: Double) -> Int32 {
            Int32(base - gain * 4000 * pulse + breathing + motion + .random(in: -150...150))
        }

        return PPGSample(
            timestampNs: date.nanosecondsSince1970,
            ppg0: channel(base: 250_000, gain: 1.0),
            ppg1: channel(base: 243_000, gain: 0.9),
            ppg2: channel(base: 238_000, gain: 0.8),
            ambient: Int32(1200 + Double.random(in: -40...40))
        )
    }
}

/// Builds whole fake sessions in one go, for the Sessions screen.
enum SyntheticSessionFactory {
    static func makeSession(start: Date, duration: TimeInterval) -> RecordingSession {
        let model = SyntheticSignalModel(origin: start)
        let ppgSynth = PPGSynthesizer(model: model)

        func dates(rate: Double) -> [Date] {
            (0..<Int(duration * rate)).map { start.addingTimeInterval(Double($0) / rate) }
        }

        return RecordingSession(
            id: UUID(),
            deviceId: "C8A3B2F1",
            deviceName: "Polar Sense C8A3B2F1 (simulated)",
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            ppg: dates(rate: VeritySense.ppgSampleRate).map(ppgSynth.sample(at:)),
            acc: dates(rate: VeritySense.accSampleRate).map(model.accSample(at:)),
            hr: dates(rate: 1).map(model.hrSample(at:))
        )
    }
}
