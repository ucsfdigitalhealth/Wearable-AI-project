import Foundation

/// A device found while scanning.
struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let rssi: Int
}

/// Details about the connected device.
struct DeviceInfo: Hashable {
    let id: String
    let name: String
    let model: String
    let firmwareVersion: String
    var batteryPercent: Int
}
