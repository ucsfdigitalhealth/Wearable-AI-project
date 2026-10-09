import SwiftUI

/// Device connection: scan → connect (found / pairing / connected) → device overview.
struct DeviceView: View {
    @Environment(DeviceManager.self) private var device
    @State private var showingSync = false

    var body: some View {
        List {
            switch device.state {
            case .connected(let info):
                connectedSections(info)
            case .connecting(let target):
                connectingSections(target)
            case .disconnected, .scanning:
                scanSections
            }
        }
        .navigationTitle(device.connectedDevice == nil ? "Connect Device" : "Device Connected")
        .navigationDestination(isPresented: $showingSync) { SyncView() }
    }

    // MARK: Connected

    @ViewBuilder
    private func connectedSections(_ info: DeviceInfo) -> some View {
        Section {
            HStack(spacing: 16) {
                DeviceIcon()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Polar Verity Sense").font(.headline)
                    Text(info.name).font(.caption).foregroundStyle(.secondary)
                    BatteryLabel(percent: info.batteryPercent)
                }
            }
            .padding(.vertical, 4)

            PrimaryButton(title: "Sync Recordings") { showingSync = true }
                .padding(.vertical, 4)

            if device.pendingRecordings.isEmpty {
                Label("No new recordings", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "\(device.pendingRecordings.count) new recordings (\(device.pendingBytes.fileSizeText))",
                    systemImage: "tray.and.arrow.down"
                )
                .foregroundStyle(.secondary)
            }
        }

        Section {
            NavigationLink {
                DeviceDetailsView(info: info)
            } label: {
                Label("Device Settings", systemImage: "gearshape")
            }
            NavigationLink {
                RecordingSettingsView()
            } label: {
                Label("Recording Configuration", systemImage: "slider.horizontal.3")
            }
            LabeledContent {
                Text("\(info.batteryPercent)%")
            } label: {
                Label("Battery Status", systemImage: "battery.75")
            }
            LabeledContent {
                Text(info.firmwareVersion)
            } label: {
                Label("Firmware Version", systemImage: "cpu")
            }
        }

        Section {
            Button("Disconnect", role: .destructive) {
                device.disconnect()
            }
        }
    }

    // MARK: Connecting

    @ViewBuilder
    private func connectingSections(_ target: DiscoveredDevice) -> some View {
        Section {
            VStack(spacing: 12) {
                DeviceIcon(size: 96)
                Text("Polar Verity Sense").font(.headline)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting…").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }

        Section {
            ChecklistRow(title: "Device found", status: .done)
            ChecklistRow(title: "Pairing…", status: status(for: .pairing))
            ChecklistRow(title: "Connected", status: status(for: .connected))
        }

        Section {
            SecondaryButton(title: "Cancel") {
                device.cancelConnect()
            }
            .plainListRow()
        }
    }

    private func status(for step: DeviceManager.ConnectStep) -> ChecklistRow.Status {
        if device.connectStep > step { return .done }
        if device.connectStep == step { return step == .connected ? .done : .active }
        return .pending
    }

    // MARK: Scanning

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
            PrimaryButton(title: device.isScanning ? "Stop Scanning" : "Scan for Devices") {
                if device.isScanning {
                    device.stopScan()
                } else {
                    device.startScan()
                }
            }
            .plainListRow()
        }
    }
}

private struct DeviceDetailsView: View {
    let info: DeviceInfo

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Model", value: info.model)
                LabeledContent("Device ID", value: info.id)
                LabeledContent("Firmware", value: info.firmwareVersion)
                LabeledContent("Battery", value: "\(info.batteryPercent)%")
            }
            Section("Supported sensors") {
                ForEach(SensorStream.allCases) { stream in
                    LabeledContent {
                        Text(stream.rateLabel)
                    } label: {
                        Label(stream.title, systemImage: stream.systemImage)
                    }
                }
            }
        }
        .navigationTitle("Device Settings")
    }
}

/// Stand-in for a product photo of the sensor.
struct DeviceIcon: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(.black)
            Circle()
                .stroke(.gray, lineWidth: size * 0.04)
                .padding(size * 0.22)
            Text("POLAR")
                .font(.system(size: size * 0.12, weight: .heavy))
                .foregroundStyle(.red)
                .offset(y: size * 0.36)
        }
        .frame(width: size, height: size)
    }
}

struct BatteryLabel: View {
    let percent: Int

    var body: some View {
        Label("\(percent)%", systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(percent < 20 ? .red : .green)
    }

    private var symbol: String {
        switch percent {
        case 88...: "battery.100"
        case 63...: "battery.75"
        case 38...: "battery.50"
        case 13...: "battery.25"
        default: "battery.0"
        }
    }
}

#Preview {
    NavigationStack {
        DeviceView()
    }
    .previewEnvironment()
}
