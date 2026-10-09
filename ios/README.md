# WearableAI — iOS app

Native SwiftUI app for collecting and viewing Polar Verity Sense data. It runs on
**simulated data** for now, in the same format the Polar BLE SDK delivers, so it can be
switched to the real device later.

## Requirements

- macOS with **Xcode 16 or newer** (the project uses Xcode 16's synchronized folders)
- iOS 17+ (Simulator or iPhone)

## Run it

1. Open `WearableAI.xcodeproj` in Xcode.
2. Pick an iPhone simulator and press **Run** (⌘R).
3. Go to **Device → Scan for devices**, tap a device, then open the **Live** tab.

If the project won't open, regenerate it with XcodeGen:
`brew install xcodegen && xcodegen` (run from this folder).

New `.swift` files added under `WearableAI/` are picked up automatically.

## Screens

| Tab | What it does |
|---|---|
| Live | Heart rate, activity level, raw PPG waveform, accelerometer x/y/z, HR trend, record button |
| Device | Scan, connect, device details (battery, firmware), active streams, disconnect |
| Sessions | Saved recordings → detail view with HR and movement charts, summary stats, CSV export |
| Settings | Data source info, generate or delete sample sessions |

## Code layout

```
WearableAI/
  Models/        PPGSample, ACCSample, HRSample, RecordingSession, device info
  Services/      SensorDataSource (protocol), MockVeritySenseSource, synthetic signals,
                 DeviceManager (connection + live data + recording), SessionStore, CSV export
  Processing/    Activity classification and session summaries
  Views/         SwiftUI screens and shared components
```

## Data format (placeholder — update to match the team's common format)

| Stream | Rate | Fields |
|---|---|---|
| PPG | 55 Hz | `timestamp_ns, ppg0, ppg1, ppg2, ambient` (raw ints) |
| Accelerometer | 52 Hz | `timestamp_ns, x_mg, y_mg, z_mg` |
| Heart rate | ~1 Hz | `timestamp_ns, hr_bpm, rr_ms, contact` |

Timestamps are nanoseconds since the Unix epoch. Sessions are saved as JSON in the app's
Documents/Sessions folder, and each stream can be exported as CSV in the format above.

## Next steps

- Match the models to Ethan's common data format once it's defined.
- Add the Polar BLE SDK (Swift Package: `https://github.com/polarofficial/polar-ble-sdk`)
  and write a `PolarVeritySenseSource` that conforms to `SensorDataSource`, then use it in
  `WearableAIApp.swift` instead of the mock. This needs a real iPhone, because the
  Simulator has no Bluetooth.
- Keep the screens consistent with the Android app.
