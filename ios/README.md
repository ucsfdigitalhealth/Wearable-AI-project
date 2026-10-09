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

Follows Ali's end-to-end workflow diagram: **record on the Verity Sense → sync over BLE →
save as CSV on the phone → upload to Dropbox**.

| Where | Screen |
|---|---|
| First launch | Onboarding: welcome → how to wear it → connect device → recording settings |
| Home tab | Daily Summary: device status and sync button, steps, heart rate, sleep, stress |
| Trends tab | Week / month charts: steps, resting HR, sleep, active minutes |
| Insights tab | Day / week / month comparisons ("You were 15% more active…") |
| More → Device | Scan, connect (found / pairing / connected), battery, firmware, new recordings |
| More → Recording Settings | Turn PPG / accelerometer / gyroscope / magnetometer on or off, continuous or scheduled |
| More → Sync Recordings | Progress ring and steps: connecting → downloading → saving → converting to CSV |
| More → Recordings | Synced recordings, each with charts and stats |
| More → Export to CSV | Choose streams and time range, write CSV files |
| More → Upload to Dropbox | Choose files, upload with progress (simulated for now) |
| More → Live Data | Developer screen: live PPG / accelerometer / HR stream |

## Code layout

```
WearableAI/
  AppServices.swift  Creates the shared objects (swap the mock device here)
  Models/        Sensor samples, recordings, device info, recording settings, daily summaries
  Services/      SensorDataSource (protocol) + MockVeritySenseSource, DeviceManager,
                 SyncManager, SessionStore, ExportStore (CSV), UploadManager (Dropbox)
  Processing/    Activity classification and per-recording summaries
  Views/         SwiftUI screens and shared components
```

## Data format (placeholder — update to match the team's common format)

| Stream | Rate | CSV columns |
|---|---|---|
| PPG | 55 Hz | `timestamp_ns, ppg0, ppg1, ppg2, ambient` |
| Accelerometer | 52 Hz | `timestamp_ns, x_mg, y_mg, z_mg` |
| Gyroscope | 52 Hz | `timestamp_ns, x_dps, y_dps, z_dps` |
| Magnetometer | 50 Hz | `timestamp_ns, x_gauss, y_gauss, z_gauss` |
| HR & PPI | ~1 Hz | `timestamp_ns, hr_bpm, ppi_ms, contact` |

Timestamps are nanoseconds since the Unix epoch. CSVs are saved per day as
`Documents/Exports/<yyyy-MM-dd>/<stream>_<yyyyMMdd>.csv` and uploaded to
`/VeritySense_Study/<participant>/<yyyy-MM-dd>/` in Dropbox.

The diagram lists PPG at 28 Hz and the motion sensors at 26 Hz. The rates above are the
Verity Sense defaults from Polar's SDK and are set in one place (`VeritySense` in
`Models/SensorSamples.swift`).

## Screenshots without a Mac

Every push that changes `ios/` runs the **iOS build** GitHub Action: it builds the app on a
macOS runner, opens each screen in the iPhone Simulator, and saves screenshots as the
`ios-screenshots` artifact on the run page.

## Next steps

- Match the models to Ethan's common data format once it's defined.
- Add the Polar BLE SDK (Swift Package: `https://github.com/polarofficial/polar-ble-sdk`)
  and write a `PolarVeritySenseSource` that conforms to `SensorDataSource`, then use it in
  `AppServices.swift` instead of the mock. This needs a real iPhone, because the
  Simulator has no Bluetooth.
- Connect real Dropbox uploads (needs a Dropbox app key for the study; SwiftyDropbox SDK).
- Replace the simulated daily summaries and insights with real processed data.
- Keep the screens consistent with the Android app.
