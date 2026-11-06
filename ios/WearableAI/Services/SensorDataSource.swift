import Foundation

/// Where sensor data comes from. `MockVeritySenseSource` implements it for now; a
/// `PolarVeritySenseSource` built on the Polar BLE SDK will replace it later.
protocol SensorDataSource: AnyObject {
    func scan() -> AsyncStream<DiscoveredDevice>
    func connect(to device: DiscoveredDevice) async throws -> DeviceInfo
    func disconnect() async

    // MARK: Offline recordings (the main workflow: record on the device, sync later)

    /// Streams the device is recording right now.
    func recordingStatus() async throws -> Set<SensorStream>
    /// Starts recording these streams on the device. Throws if any of them fails to start.
    func startRecording(_ streams: Set<SensorStream>) async throws
    /// Stops every recording on the device. Polar recommends this before downloading or
    /// deleting recordings.
    func stopRecording() async throws
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
    // Cancelling the task that reads a stream stops it on the device. PPG and accelerometer
    // can't stream while the device is recording them.

    /// Batches of PPG samples (the device sends data in batches, not one sample at a time).
    func ppgStream() -> AsyncStream<[PPGSample]>
    /// Batches of accelerometer samples.
    func accStream() -> AsyncStream<[ACCSample]>
    /// About one heart-rate sample per second.
    func hrStream() -> AsyncStream<HRSample>
}
