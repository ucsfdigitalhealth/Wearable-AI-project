# Audit: recording_001 (Polar Verity Sense, 2026-11-26)

Audited 2026-11-26. Files: `data/samples/recording_001/` (moved unchanged from
`data/samples/`; SHA-256 verified identical after the move; not committed to git).

Local recording time (from filenames) 17:56 on 2026-11-26 = **2026-11-27 01:56 UTC**
(timestamps inside the files are UTC; the filename uses phone local time, apparently UTC-8).

## 1. Per-file summary

| | PPG | ACC | GYRO | MAG | HR |
|---|---|---|---|---|---|
| File | `ppg_20261126_175627.csv` | `acc_20261126_175628.csv` | `gyro_20261126_175629.csv` | `mag_20261126_175629.csv` | `hr_20261126_175630.csv` |
| Rows | 2560 | 2460 | 2285 | 2232 | 44 |
| Value columns | `channel 0`, `channel 1`, `channel 2`, `ambient` | `X [mg]`, `Y [mg]`, `Z [mg]` | `X [dps]`, `Y [dps]`, `Z [dps]` | `X [gauss]`, `Y [gauss]`, `Z [gauss]` | `HR [bpm]`, `PPI [ms]`, `contact` |
| Units | raw ADC counts (no unit) | milli-g | deg/s | gauss | bpm, ms, bool |
| Value type | int | int | float | float | int, empty, `true/false` |
| Sampling rate (1/median dt) | 54.82 Hz | 52.45 Hz | 52.45 Hz | 49.61 Hz | 1.00 Hz |
| dt range | 18.18-18.24 ms | 19.07-19.23 ms | 19.07-19.23 ms | 20.00-20.17 ms | exactly 1000 ms |
| Duration | 46.67 s | 46.90 s | 43.56 s | 44.95 s | 43.00 s |
| Start (UTC) | 01:56:26.565 | 01:56:26.877 | 01:56:27.260 | 01:56:27.377 | 01:56:30.000 |
| Missing values | none | none | none | none | **`PPI [ms]` empty in all 44 rows** |
| Gaps (> 1.5 x median dt) | 0 | 0 | 0 | 0 | 0 |
| Non-monotonic timestamps | 0 | 0 | 0 | 0 | 0 |

**Common format:** `;`-separated, one header row, columns 1-2 are
`Phone timestamp` (ISO-8601, ms resolution, no timezone) and
`sensor timestamp [ns]` (int64 ns since 2000-01-01T00:00:00Z, the Polar epoch).
The phone timestamp equals the sensor timestamp converted to UTC within 0-1 ms in
every file, i.e. it is derived from the sensor clock rather than being an
independent phone clock.

**Regular jitter:** ACC/GYRO dt alternates 19.067 ms with periodic 19.231 ms
steps; PPG/MAG show similar small batch jitter. Irrelevant for the features here.

## 2. Synchronisation

All streams share the device clock, so they can be aligned directly on
`sensor timestamp [ns]`; no resampling or offset estimation is needed.

* Overlap of all five streams: **01:56:30.000 -> 01:57:10.821 UTC = 40.8 s**
* PPG / ACC overlap: 46.4 s
* Movement bursts in ACC/GYRO (0.3-4.6 s, 12-17 s, 31-33.6 s, 38.7-44 s after
  the recording start) coincide exactly with PPG artefacts, confirming alignment.

## 3. Quality observations

**PPG**
* Clear pulse waves on all three channels (channels correlate strongly; ch2 has the
  highest spectral pulse SNR, 0.76).
* **Polarity is inverted**: counts fall as blood volume rises. On an ensemble
  average of clean beats, the steepest edge after inversion is the rising one
  (~2x the falling slope), which is the systolic upstroke.
* Pulse shape: an early systolic shoulder followed by a later, higher peak. The
  beat detector uses the later peak as fiducial point.
* Motion artefacts in the four movement periods; ~36% of PPG samples fall in
  movement. No abrupt gain jumps (unlike the old `demo_ppg.txt`), no flat-lining;
  ambient channel stable (-170 215 to -169 900).
* Irregular beats also at ~8-12 s without large ACC movement (a small ~4 Hz
  oscillation of up to ~30 mg is present 4-12 s).

**ACC**: median |a| during still periods 996.4 mg, so calibrated to within 0.4%.
The device was mostly still with four handling/arm movements; peak |a| 1749 mg.

**GYRO**: up to 257 deg/s during handling; ~4 deg/s at rest (bias/noise, not removed).

**MAG**: |B| = 0.46-1.10 G and changes with every movement, while Earth's field
is ~0.25-0.65 G. **Uncalibrated** (hard/soft-iron offsets). Heading/orientation
cannot be derived without a calibration procedure.

**HR (device output)**
* `HR [bpm]` is the Verity Sense's own HR estimate at 1 Hz. The first value is 0
  (no estimate yet), then 95 -> 73 bpm with a smooth, steady decline.
* `PPI [ms]` is **empty**: no device beat-to-beat intervals were recorded.
  (Check whether the app enabled PPI; on the Verity Sense PPI may not be
  available simultaneously with raw PPG streaming. To be confirmed with the
  Polar SDK documentation.)
* `contact` is `false` in **every** row, although a pulse is clearly present. The
  flag is therefore not usable as a wear/contact indicator.
* Device HR is ~11 bpm (mean absolute difference) away from the beat-to-beat
  PPG rate, mostly reading higher during 15-38 s (PPG ~67-78 bpm, device
  84-90 bpm). Counting pulse waves in the clean 20-30 s stretch gives ~72 bpm,
  consistent with the PPG pipeline; the device values look heavily smoothed or
  lagged. Neither is validated: an ECG reference is required to settle this.

## 4. Comparison with the previous sample files

| | Old samples (`demo_acc.txt`, `demo_ppg.txt`, Nov-17 PPG) | recording_001 |
|---|---|---|
| Real data | demo_acc looked synthetic (round start time, perfect timing) | yes |
| Simultaneous streams | no (different dates) | yes, 5 streams on one clock |
| ACC rate | 26 Hz | 52 Hz |
| Gyro / Mag | none | present |
| Device HR reference | none | 1 Hz HR |
| PPG quality | demo: gain step; Nov-17: no consistent pulse | clear pulse outside movement |
| Header | demo_ppg headerless | consistent headers |
| Duration | 30-120 s | **~47 s (shorter than expected)** |

## 5. What this recording supports

| Feature | Status |
|---|---|
| Pulse rate (mean/min/max/over time), mean pulse interval | Extracted from PPG, coverage-flagged (22 of 56 intervals accepted, covering 37% of the PPG time) |
| PRV RMSSD | **Not reliable**: only ~17 s of accepted intervals (< 20 s minimum) |
| PRV SDNN, pNN50 | **Not possible**: needs >= 50 s of clean intervals |
| Device PPI-based PRV | **Not possible**: PPI column empty |
| Frequency-domain PRV | Not possible: needs >= 2-5 min |
| Pulse amplitude, foot-to-peak time | Extracted, experimental, arbitrary units |
| ACC magnitude, ENMO, MAD, epochs, intensity | Extracted; intensity cut-points provisional (wrist-derived) |
| ACC dominant movement frequency | Computed but not meaningful here (no rhythmic activity) |
| Gyro angular speed, total rotation | Extracted (bias not removed) |
| Mag field magnitude | Extracted, flagged uncalibrated; no heading |
| Sleep, circadian, reactivity/recovery | Not possible: recording too short, no event markers |

## 6. Requests for the next recording

1. **Duration**: >= 5 min seated still (PRV), ideally a longer free-living block.
2. **PPI**: check if the device PPI stream can be enabled (or recorded in a separate session) as a beat-detection reference.
3. **Reference**: a Polar H10 ECG chest strap recorded simultaneously, for HR/PRV validation.
4. **Metadata**: wear location (upper arm / forearm / temple), side, timezone, and event markers (e.g. rest / task / recovery).
5. **Magnetometer calibration**: figure-eight rotation at the start if heading is needed.
