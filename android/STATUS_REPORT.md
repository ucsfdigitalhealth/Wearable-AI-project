# Android implementation update — for Ali, Ethan, and Beni

**Prepared:** November 6, 2026

## Workflow implemented in source

1. User explicitly selects **Scan** and connects Polar Verity Sense via Polar BLE SDK.
2. User can start/stop offline PPG and accelerometer recordings on the sensor.
3. With device reconnected, user presses **Sync to phone**. Android enumerates offline recordings, skips files previously downloaded, retrieves data, converts rows into semicolon-delimited CSVs, and writes them into private app storage.
4. User can save individual CSVs using Android's document picker. The export UI shows all saved files, grouped by recording date in storage.
5. User can connect a study Dropbox account via OAuth2 PKCE (after the study's app key is configured) and upload local CSVs to a participant/date folder. This is an explicit foreground action, not background auto-upload.
6. With explicit consent and an ongoing Android foreground-service notification, Android logs GPS, accelerometer, gyroscope, magnetometer, optional step-counter data, and screen-state events into `phone_*.csv` alongside the wearable data.

## Storage configuration

- **Phone:** `files/Exports/YYYY-MM-DD/` (sandbox-protected internal storage). One file per device offline-recording entry, with deterministic name to skip repeated syncs. Atomic temp-file replace protects incomplete output. No deletion from sensor on sync.
- **Wearable schema:** Semicolon CSV matching `demo_acc.txt` header and iOS's `SessionCSV.swift`; native Polar nanosecond timestamp since 2000-01-01 preserved. `Phone timestamp` is derived from raw Polar time for offline records, not a wall-clock measurement at receipt.
- **Phone passive schema:** Comma-separated CSV with Unix nanosecond timestamps. Captures actual system GPS/motion/screen events only while the service is active.
- **Cloud:** Dropbox app-folder path `/VeritySense_Study/<participant>/<day>/<file>`, short-lived OAuth credentials held only in current app process. An app key must be provided by the study; no tokens or secrets in GitHub.
- **Privacy:** No automatic upload, app sandbox storage, optional permission-based phone sensing. Study-grade encryption at rest, long-term retention/deletion policy, and access-control review are **not yet implemented**.

## Relationship to feature extraction

The Android side provides the raw streams needed by Ethan's feature scripts. In particular:

| Raw stream | Candidate features for backend extraction |
|---|---|
| PPG | Pulse rate/IBIs, PPI, HR, HRV/PRV (SDNN, RMSSD, pNN50, SD1/SD2), morphology, signal-quality indices, pulse amplitude and width |
| Polar accelerometer / phone accelerometer | Magnitude, activity intensity, variance, counts, jerk, bouts, rest/sedentary periods, dominant frequency, movement regularity |
| Phone gyroscope | Angular velocity, rotational variance, smoothness, tremor/rotation frequency |
| Phone magnetometer | Field magnitude, heading variability (requires calibration / fusion) |
| GPS / step counter / screen | Contextual movement and activity, behavior, sleep/wake proxies with appropriate inference models |
| Time-aligned PPG + ACC | HR–activity coupling, motion artifacts, responses to movement, recovery after activity |

**Not yet established:** all Ali-requested features, including sample entropy, LF/HF power, full circadian rhythms, sleep fragmentation, and recovery indices, are **backend-analysis requirements** requiring validated algorithms and sufficient longitudinal data. The mobile app does not claim to calculate them. Standardized timezone handling and heart rate from waveform/PPI need agreement with Ethan and Beni.

## Verification status and next actions

- **Verified here:** Kotlin `CsvCodec.kt` compiles under `kotlinc`, smoke tests pass for Polar epoch conversion and escaping.
- **Coded but unverified:** Android APK build, real BLE connection/offline recording/sync, foreground GPS + motion on phone, Dropbox OAuth/upload. Full device/Dropbox integration test not possible in this environment.
- **Blocked:** Existing local Kotlin project was not in the remote repository. GitHub API denied creating the requested feature branch (`403 Resource not accessible by integration`). Source and a Windows PowerShell push script are provided in the ZIP. Someone with GitHub write authorization must push.
- **Next for team:** run Android CI, schedule physical-device test with Ethan's Verity Sense, validate sample counts/timestamp alignment in Ethan's Python loader, register study-owned Dropbox app and run a real upload; then capture evidence/screenshots for Ali's presentation.

## Time-alignment caution

Ethan's synthetic sample files show mismatches between ISO timestamps and raw sensor timestamps if the sensor clock is interpreted as Polar epoch 2000. Example: `599628000000000000` ns converts to **2019-01-01 03:20:00 UTC** but sample row says `2026-06-10T22:00:00.000`. The team should decide whether these are intentionally synthetic independent columns or a schema bug. Never silently overwrite the raw timestamp to make dates match.
