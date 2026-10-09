import SwiftUI

struct DeviceView: View {
    @Environment(DeviceManager.self) private var device

    var body: some View {
        NavigationStack {
            List {
                switch device.state {
                case .connected(let info):
                    connectedSections(info)
                case .connecting(let target):
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting to \(target.name)…")
                        }
                    }
                case .disconnected, .scanning:
                    scanSections
                }
            }
            .navigationTitle("Device")
        }
    }

    @ViewBuilder
    private func connectedSections(_ info: DeviceInfo) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(info.name).font(.headline)
                    Text("Connected").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }

        Section("Details") {
            LabeledContent("Model", value: info.model)
            LabeledContent("Device ID", value: info.id)
            LabeledContent("Firmware", value: info.firmwareVersion)
            LabeledContent("Battery") {
                Label("\(info.batteryPercent)%", systemImage: batterySymbol(info.batteryPercent))
            }
        }

        Section("Data streams") {
            StreamRow(name: "PPG (raw optical)", rate: "\(Int(VeritySense.ppgSampleRate)) Hz")
            StreamRow(name: "Accelerometer", rate: "\(Int(VeritySense.accSampleRate)) Hz")
            StreamRow(name: "Heart rate", rate: "1 Hz")
        }

        Section {
            Button("Disconnect", role: .destructive) {
                device.disconnect()
            }
        }
    }

    @ViewBuilder
    private var scanSections: some View {
        Section {
            if device.discoveredDevices.isEmpty && !device.isScanning {
                Text("Turn on your Polar Verity Sense and tap Scan.")
                    .foregroundStyle(.secondary)
            }
            ForEach(device.discoveredDevices) { found in
                Button {
                    device.connect(to: found)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.tint)
                        Text(found.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(found.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if device.isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Nearby devices")
        } footer: {
            Text("Using a simulated Verity Sense until the real device arrives.")
        }

        if let error = device.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Button(device.isScanning ? "Stop scanning" : "Scan for devices") {
                if device.isScanning {
                    device.stopScan()
                } else {
                    device.startScan()
                }
            }
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 88...: "battery.100"
        case 63...: "battery.75"
        case 38...: "battery.50"
        case 13...: "battery.25"
        default: "battery.0"
        }
    }
}

private struct StreamRow: View {
    let name: String
    let rate: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
            Text(name)
            Spacer()
            Text(rate).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DeviceView()
        .previewEnvironment()
}
