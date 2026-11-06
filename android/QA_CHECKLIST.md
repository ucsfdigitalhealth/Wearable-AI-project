# Android QA checklist — what is implemented vs. verified

## Before presenting to Ali

- [ ] Open `android/` in Android Studio and confirm `assembleDebug` is green. A full Android SDK/Gradle build was **not available** in the assistant environment.
- [ ] Run unit tests with `gradle testDebugUnitTest`.
- [ ] On Android 13+ phone, grant Bluetooth permissions and scan the actual Polar Verity Sense.
- [ ] Verify connect, disconnect, reconnect, battery level (not implemented in UI), and `FEATURE_POLAR_OFFLINE_RECORDING` readiness.
- [ ] Start PPG + ACC offline recording, move away from the phone, reconnect, stop, sync.
- [ ] Compare downloaded sample count/timestamps to Polar SDK reference output. Check units and UTC conversion.
- [ ] Sync the same recording twice: no duplicate files; zero data loss and no empty/malformed CSV.
- [ ] Open resulting PPG/ACC CSVs in Ethan's Python loader and compare sample data and statistics.
- [ ] Confirm data files remain after app process restart; test low-storage error paths.
- [ ] Grant/revoke GPS and motion permissions, start phone collection, lock screen, move phone, stop.
- [ ] Check GPS, ACC, GYRO, MAG, step-counter and screen-event CSV contents; test background recording with a visible notification.
- [ ] Register the study Dropbox app, configure public app key, connect via PKCE, upload a small CSV, verify remote folder structure.
- [ ] Test Dropbox authentication cancellation, network loss, invalid participant ID and large-file rejection.
- [ ] Establish encrypted storage, data governance, participant consent, transfer policy, and long-term retention before live participant data collection.

## Ownership / handoff

- Android Kotlin BLE, local CSV, foreground phone data, Android UI, Dropbox integration: **Aiden** — code drafted in this package, unverified on real devices.
- iOS SwiftUI app: **Beni** — reference branch `ios` and its screenshots.
- Backend CSV parsing, feature engineering and server storage: **Ethan** — reference branch `data-pipeline`.

## Known unfinished work

- Not integrated into Aiden's unpublished local Android Studio files.
- No real Polar Verity Sense or Dropbox account available for device/transfer verification.
- No continuous live PPG / ACC dashboard (live HR only); primary flow is offline sensor recording → sync.
- No robust chunked Dropbox upload >140 MB, encrypted credential persistence, WorkManager background upload, or server-side feature extraction.
- No Phone Data scheduling over device reboot; Android foreground service is an opt-in, user-visible session.
