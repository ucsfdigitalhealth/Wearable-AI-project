import Foundation

/// Where sensor data comes from. `MockVeritySenseSource` implements it for now; a
/// `PolarVeritySenseSource` built on the Polar BLE SDK will replace it later.
protocol SensorDataSource: AnyObject {
    func scan() -> AsyncStream<DiscoveredDevice>
    func connect(to device: DiscoveredDevice) async throws -> DeviceInfo
    func disconnect() async

    // MARK: Offline recordings (the main workflow: record on the device, sync later)

    /// Sends the recording configuration to the device.
    func apply(_ settings: RecordingSettings) async throws
    /// Recordings stored on the device that haven't been downloaded yet.
    func listRecordings() async throws -> [DeviceRecording]
    /// Downloads one recording over BLE. `progress` is called with 0...1.
    func download(
        _ recording: DeviceRecording,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> RecordingSession
    /// Removes a recording from the device after it has been saved on the phone.
    func deleteFromDevice(_ recording: DeviceRecording) async throws

    // MARK: Live streaming (used by the Live Data screen)

    /// Batches of PPG samples (the device sends data in batches, not one sample at a time).
    func ppgStream() -> AsyncStream<[PPGSample]>
    /// Batches of accelerometer samples.
    func accStream() -> AsyncStream<[ACCSample]>
    /// About one heart-rate sample per second.
    func hrStream() -> AsyncStream<HRSample>
}
