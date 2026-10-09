import Foundation

/// Where sensor data comes from. `MockVeritySenseSource` implements it for now; a
/// `PolarVeritySenseSource` built on the Polar BLE SDK will replace it later.
protocol SensorDataSource: AnyObject {
    func scan() -> AsyncStream<DiscoveredDevice>
    func connect(to device: DiscoveredDevice) async throws -> DeviceInfo
    func disconnect() async

    /// Batches of PPG samples (the device sends data in batches, not one sample at a time).
    func ppgStream() -> AsyncStream<[PPGSample]>
    /// Batches of accelerometer samples.
    func accStream() -> AsyncStream<[ACCSample]>
    /// About one heart-rate sample per second.
    func hrStream() -> AsyncStream<HRSample>
}
