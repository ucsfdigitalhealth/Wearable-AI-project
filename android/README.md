# WearableAI Android — BLE sync, CSV export, Dropbox, passive sensing

This is a **standalone Android reference implementation**, based on the workflow and screen hierarchy on the [`ios` branch](https://github.com/ucsfdigitalhealth/Wearable-AI-project/tree/ios/ios/screenshots) and Ethan's [`data-pipeline` branch](https://github.com/ucsfdigitalhealth/Wearable-AI-project/tree/data-pipeline/backend). The previous local Kotlin app was **not accessible** in the remote repository, so this is not a merge into unknown local code. No screenshots or sensor results are fabricated.

## Implemented

| Workflow | Android location | Status |
|---|---|---|
| Scan / connect / auto reconnect over Polar BLE | Device → Scan / Connect | Coded, needs phone + physical device test |
| Start / stop **offline** PPG and ACC recording on Verity Sense | Device → Recording settings | Coded, needs device firmware test |
| Download offline PPG / ACC / GYRO / MAG files | Device → Sync | Coded, needs real device test |
| Save one local CSV per source recording | `RecordingStore.kt` | Coded, CSV serializer smoke-tested |
| Save any CSV to another provider via Android file picker | Sessions / Data → Save | Coded, needs on-device test |
| Dropbox OAuth2 PKCE, explicitly invoked uploads | Data → Connect Dropbox / Upload | Coded, requires study Dropbox app key + live account test |
| Foreground passive GPS, ACC/GYRO/MAG, step counter, screen on/off | Phone → Enable | Coded, needs Android phone + permission test |
| Live HR from Polar SDK | Device → Live heart rate | Coded, needs wearable test |

This implementation does **not** claim production readiness, sustained 100-hour data validation, automatic cloud sync, or complete backend feature extraction. Ethan owns the Python analysis. No wearable hardware was available for testing in this environment.

## Build

1. Open **the `android/` directory** in Android Studio. Android 13+ (`minSdk 33`), JDK 21, Android SDK 35 required. Polar BLE SDK resolves through JitPack.
2. Sync Gradle. Install on a **physical Android phone** with Bluetooth. The Android Emulator cannot test the real Verity Sense BLE workflow.
3. Grant Bluetooth scan/connect permissions at first use. If the app asks for them when you tap Scan, tap Scan again after granting.
4. Go to Device → Scan → tap Verity Sense → Connect. Wait until its offline-recording feature is ready.
5. Press Start recording (runs on device without continuous BLE), Stop recording, then **Sync to phone** to download and persist CSVs.
6. Select Sessions or Data to export CSVs using the Android system file picker.
7. To record phone data, open Phone → Enable. Grant location permission. The app uses an ongoing **foreground location-service notification**. Tap Stop to stop collecting.

> If testing with your **existing local Android Studio project**, copy/adapt these components to that project rather than replacing its `MainActivity` without comparing the current code.

## Dropbox setup

1. Register a Dropbox app with **App Folder** access and `files.content.write` scope. No app secret is used (OAuth2 PKCE).
2. Add `DROPBOX_APP_KEY=YOUR_PUBLIC_APP_KEY` to your local **`~/.gradle/gradle.properties`** (do not commit tokens or secrets). Rebuild the APK so the callback scheme matches.
3. Data → Connect Dropbox and approve access; then enter a participant ID, and press Upload.
4. Destination: `/VeritySense_Study/<participant ID>/<YYYY-MM-DD>/<CSV filename>` relative to the Dropbox app's root. The user is asked to connect Dropbox **once per app process**, as credentials are intentionally held in memory only. Production needs encrypted credential persistence before auto-upload is implemented.
5. Files over 140 MB are rejected rather than silently failing the single-request Dropbox limit; add chunked upload sessions before full-day production recordings.

There are **no embedded Dropbox credentials**, no silent uploads, and no fake or simulated upload success. If the key is not configured, local CSV export still works.

## Schema

Polar samples use **semicolon** separators and match the headers in `backend/data/samples/` and the iOS `SessionCSV.swift`:

```
Phone timestamp;sensor timestamp [ns];channel 0;channel 1;channel 2;ambient
2000-01-01T00:00:00.000;0;100;101;102;10

Phone timestamp;sensor timestamp [ns];X [mg];Y [mg];Z [mg]
2000-01-01T00:00:00.000;0;30;0;1000
```

* The Polar `sensor timestamp [ns]` is **nanoseconds since UTC 2000-01-01**. No reinterpretation as Unix time.
* For offline recordings the displayed `Phone timestamp` is **reconstructed UTC time from the Polar sample timestamp**, not a measured phone receipt time; name retained for backend schema compatibility. This is important during cross-device validation.
* `ppg` uses Verity Sense's expected 3 optical channels + 1 ambient. Nonconforming PPG channel counts fail visibly rather than inventing values.
* ACC values are in milli-g; GYRO in degrees/second; MAG in gauss (according to SDK output conventions).
* Phone passive files are **comma**-delimited, use `timestamp_ns` Unix epoch ns, and are named `phone_gps_*`, `phone_motion_*`, `phone_activity_*`, `phone_screen_*`.
* **Important discrepancy:** Ethan's `demo_ppg.txt` and `demo_acc.txt` contain ISO phone timestamps inconsistent with 2000-epoch sensor timestamps (for example `599628000000000000` ns maps to **2019-01-01 03:20 UTC**, not 2026-06-10). Verify the intended interpretation against actual Verity Sense files before running backend time-alignment analyses.

## Storage/report

- Internal local path: `files/Exports/YYYY-MM-DD/` inside the app sandbox; accessible through UI and exported via Storage Access Framework. No unnecessary external-storage permission.
- CSVs are written to a temporary `.partial` file then renamed; incomplete failed syncs do not overwrite previous finished CSV files.
- File name includes sensor type, recording start time and SHA-256 digest prefix of sensor ID + source path, so resync of the same device recording skips duplicates.
- Device recordings are **never deleted automatically** after sync; review the CSVs first.
- Data is **not encrypted at rest beyond Android application sandbox protections**. If studying identifiable health data or location data, obtain study-approved encryption, participant consent, access control, retention/deletion policy, and backend transfer safeguards before deployment.
- Upload requires explicit user interaction; Dropbox uses OAuth2 PKCE and Dropbox app-folder scope.
- Foreground phone collection stops on process death; Android battery management/location permissions can reduce sampling. This app does not claim always-on capture or full availability after device reboot.
- See `QA_CHECKLIST.md` for what must be demonstrated before a presentation or study rollout.

## Unit test

Run `gradle testDebugUnitTest` in `android/` using Gradle 8.9 after Gradle is configured. (This standalone package does not bundle the Gradle wrapper JAR.) `CsvCodecTest` covers the Polar epoch, a backend-shaped sensor row, and quoting.
