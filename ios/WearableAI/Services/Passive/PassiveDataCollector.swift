import CoreLocation
import CoreMotion
import Observation
import UIKit

/// Collects passive smartphone data in the background: GPS, phone accelerometer and
/// gyroscope, activity/steps, and screen lock/app state. Everything is written to CSV
/// through `PassiveCSVWriter`.
///
/// iOS notes:
/// - Background collection works because the app holds "Always" location access with
///   background updates on; that keeps the process alive so motion and lock events keep arriving.
///   The blue status-bar indicator is shown while this runs (required by iOS).
/// - Significant-location-change monitoring relaunches the app after it is force-quit or
///   terminated by the system. Call `resumeIfEnabled()` at launch.
/// - iOS has no API for "screen on/off". We log device lock/unlock (protected data
///   available/unavailable) and app foreground/background, which is the closest signal.
@MainActor
@Observable
final class PassiveDataCollector: NSObject {
    enum Permission: Equatable {
        case notDetermined, denied, whenInUse, always

        var title: String {
            switch self {
            case .notDetermined: "Not asked yet"
            case .denied: "Denied"
            case .whenInUse: "While using the app"
            case .always: "Always"
            }
        }
    }

    private static let enabledKey = "passiveCollectionEnabled"

    private(set) var isCollecting = false
    private(set) var permission: Permission = .notDetermined
    private(set) var counts: [PassiveStream: Int] = [:]
    private(set) var lastLocationDate: Date?
    private(set) var lastActivity: String?

    /// Whether the user turned collection on (survives relaunch).
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Sampling rate for the phone's accelerometer and gyroscope.
    static let motionRate = 10.0

    /// Thread-safe, so the sensor callbacks can use it directly.
    nonisolated private let writer: PassiveCSVWriter
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "passive-motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var flushTimer: Timer?
    /// Today's step count, written by the pedometer callback and read by the activity callback.
    @ObservationIgnored nonisolated(unsafe) private var steps = 0

    /// - Parameter exportsDirectory: the folder `ExportStore` reads (`Documents/Exports`).
    init(exportsDirectory: URL? = nil) {
        let directory = exportsDirectory ?? URL.documentsDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        writer = PassiveCSVWriter(directory: directory)
        super.init()
        locationManager.delegate = self
        permission = Self.permission(for: locationManager.authorizationStatus)
    }

    // MARK: - Control

    /// Turns collection on. Asks for location permission first if needed.
    func enable() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        switch permission {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()   // continues in the delegate callback
        case .whenInUse:
            locationManager.requestAlwaysAuthorization()
            start()
        case .always, .denied:
            start()
        }
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        stop()
    }

    /// Call at app launch (including relaunches triggered by location changes).
    func resumeIfEnabled() {
        if isEnabled { start() }
    }

    // MARK: - Start / stop

    private func start() {
        guard !isCollecting, permission != .denied, permission != .notDetermined else { return }
        isCollecting = true
        startLocation()
        startMotion()
        startActivity()
        startScreenEvents()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.writer.flush()
        }
        log(.screen, "collection_started")
    }

    private func stop() {
        guard isCollecting else { return }
        log(.screen, "collection_stopped")
        isCollecting = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        flushTimer?.invalidate()
        flushTimer = nil
        writer.flush()
    }

    // MARK: - Location

    private func startLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10   // metres; saves battery when standing still
        locationManager.activityType = .other
        locationManager.pausesLocationUpdatesAutomatically = false
        if permission == .always {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
            locationManager.startMonitoringSignificantLocationChanges()
        }
        locationManager.startUpdatingLocation()
    }

    // MARK: - Phone motion

    private func startMotion() {
        let interval = 1 / Self.motionRate
        // Both sensors are read together on one timer so each row has acc + gyro.
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(to: motionQueue) { @Sendable [weak self] motion, _ in
            guard let self, let motion else { return }
            let date = Self.date(fromBootTime: motion.timestamp)
            // userAcceleration excludes gravity; add it back for raw accelerometer values.
            let a = motion.userAcceleration, g = motion.gravity, r = motion.rotationRate
            let row = "\(date.nanosecondsSince1970),\(a.x + g.x),\(a.y + g.y),\(a.z + g.z),\(r.x),\(r.y),\(r.z)"
            self.writer.append(.motion, at: date, row: row)
            Task { @MainActor in self.counts[.motion, default: 0] += 1 }
        }
    }

    // MARK: - Activity & steps

    private func startActivity() {
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: motionQueue) { @Sendable [weak self] activity in
                guard let self, let activity else { return }
                let name = Self.name(of: activity)
                let steps = self.steps
                self.writer.append(.activity, at: activity.startDate, row: "\(activity.startDate.nanosecondsSince1970),\(name),\(activity.confidence.rawValue),\(steps)")
                Task { @MainActor in
                    self.lastActivity = name
                    self.counts[.activity, default: 0] += 1
                }
            }
        }
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Calendar.current.startOfDay(for: .now)) { @Sendable [weak self] data, _ in
                guard let self, let data else { return }
                self.steps = data.numberOfSteps.intValue
            }
        }
    }

    // MARK: - Screen / app state

    private func startScreenEvents() {
        let center = NotificationCenter.default
        let events: [(Notification.Name, String)] = [
            (UIApplication.protectedDataDidBecomeAvailableNotification, "unlocked"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "locked"),
            (UIApplication.didBecomeActiveNotification, "app_foreground"),
            (UIApplication.willResignActiveNotification, "app_inactive"),
            (UIApplication.didEnterBackgroundNotification, "app_background"),
            (UIApplication.willTerminateNotification, "app_terminate"),
        ]
        observers = events.map { name, event in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.log(.screen, event) }
                if name == UIApplication.willTerminateNotification {
                    MainActor.assumeIsolated { self?.writer.flush() }
                }
            }
        }
    }

    private func log(_ stream: PassiveStream, _ event: String) {
        let now = Date.now
        writer.append(stream, at: now, row: "\(now.nanosecondsSince1970),\(event)")
        counts[stream, default: 0] += 1
    }

    // MARK: - Helpers

    nonisolated private static func permission(for status: CLAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }

    /// CoreMotion timestamps are seconds since device boot.
    nonisolated private static func date(fromBootTime seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceNow: seconds - ProcessInfo.processInfo.systemUptime)
    }

    nonisolated private static func name(of activity: CMMotionActivity) -> String {
        if activity.automotive { return "automotive" }
        if activity.cycling { return "cycling" }
        if activity.running { return "running" }
        if activity.walking { return "walking" }
        if activity.stationary { return "stationary" }
        return "unknown"
    }
}

extension PassiveDataCollector: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newPermission = Self.permission(for: manager.authorizationStatus)
        Task { @MainActor in
            let wasCollecting = self.isCollecting
            self.permission = newPermission
            guard self.isEnabled else { return }
            switch newPermission {
            case .whenInUse:
                // iOS only allows the "Always" prompt after "While Using" was granted.
                manager.requestAlwaysAuthorization()
                self.start()
            case .always:
                // Restart so background updates and significant-change monitoring get enabled.
                if wasCollecting { self.stop() }
                self.start()
            case .denied, .notDetermined:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 {
            let c = location.coordinate
            let row = "\(location.timestamp.nanosecondsSince1970),\(c.latitude),\(c.longitude),\(location.altitude),\(location.horizontalAccuracy),\(location.speed),\(location.course)"
            writer.append(.gps, at: location.timestamp, row: row)
        }
        let latest = locations.last?.timestamp
        Task { @MainActor in
            self.counts[.gps, default: 0] += locations.count
            self.lastLocationDate = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}
