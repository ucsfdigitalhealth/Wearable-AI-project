# Wearable AI — backend processing pipeline

Python pipeline that turns raw Polar Verity Sense CSV exports (PPG, ACC, GYRO,
MAG, device HR) into per-window features, diagnostic plots and metadata.

> **Status: initial version, not validated.** PPG-derived values are *pulse
> rate* and *pulse rate variability (PRV)*. They are not interchangeable with
> ECG heart rate / HRV, and nothing here has been compared with a reference
> device yet. See [Known limitations](#known-limitations).

## Architecture

```
data/samples/recording_001/*.csv      (raw, never modified)
        │
        ▼
ingestion/loaders.py      parse headers & units, sensor ns → UTC, sampling rate,
                          gaps, phone-vs-sensor clock, stream overlap
        │
        ├── processing/accelerometer.py   |a|, ENMO, motion mask, gravity check
        │           │ motion mask (shared sensor clock)
        │           ▼
        ├── processing/ppg.py             channel selection, band-pass, inversion,
        │                                 discontinuities, beat detection (sub-sample),
        │                                 beat-template quality, interval cleaning
        ▼
features/heart_rate.py  hrv.py (PRV)  morphology.py  activity.py  inertial.py
        │
        ▼
pipeline.py   fixed windows → features.csv, ppg_intervals.csv,
              activity_epochs.csv, metadata.json, plots/ (visualization/plots.py)
```

Every feature group has a `*_status` column. A NaN value always comes with a
status that explains it (missing stream, too little data, poor quality).
Nothing is imputed.

## Installation

Python ≥ 3.10.

```bash
cd backend
python -m pip install -r requirements.txt     # numpy, pandas, scipy, matplotlib, pytest
# optional: python -m pip install -e .         # makes `phenotyping` importable everywhere
```

## Running

```bash
cd backend
python scripts/run_pipeline.py --input data/samples/recording_001 --output results/recording_001
```

Options: `--window-s 60` (feature window), `--epoch-s 5` (activity epochs),
`--ppg-channel auto|ch0|ch1|ch2`, `--no-motion-mask`, `--no-plots`,
`--recording-id NAME`, `--config params.json` (any `PipelineConfig` field,
e.g. `{"motion_threshold_mg": 30, "prv_min_rmssd_valid_s": 30}`).

Tests: `python -m pytest` (56 tests; synthetic signals with known answers, plus
a regression check on `recording_001` that is skipped if the data are absent).

## Input requirements

One directory per recording containing any subset of:

| File name pattern | Required columns (after the two timestamp columns) |
|---|---|
| `ppg_YYYYMMDD_HHMMSS.csv` | `channel 0`, `channel 1`, `channel 2`, `ambient` |
| `acc_…csv` | `X [mg]`, `Y [mg]`, `Z [mg]` |
| `gyro_…csv` | `X [dps]`, `Y [dps]`, `Z [dps]` |
| `mag_…csv` | `X [gauss]`, `Y [gauss]`, `Z [gauss]` |
| `hr_…csv` | `HR [bpm]` (optional: `PPI [ms]`, `contact`) |

* `;` separator, one header row; first two columns `Phone timestamp`,
  `sensor timestamp [ns]` (ns since 2000-01-01 UTC). Sensor time is the reference clock.
* Only one file per stream type per directory; other files (e.g. `demo_*.txt`) are ignored.
* Malformed files raise `SensorFileError` with the reason (missing column,
  headerless file, non-numeric timestamps, no rows, mixed recordings).
* Missing values stay NaN; unsorted/duplicate timestamps are sorted/dropped with a warning.

## Outputs (`results/<recording>/`)

| File | Content |
|---|---|
| `features.csv` | One row per window (default 60 s, anchored at the earliest sample). |
| `ppg_intervals.csv` | Every pulse-to-pulse interval: time, `ibi_ms`, `valid`, rejection `reason`, instantaneous rate, beat template correlation, amplitude. |
| `activity_epochs.csv` | 5-s ACC epochs: |a|, ENMO, MAD, intensity. |
| `metadata.json` | Input files + SHA-256, streams, start/end, sampling rates, units, overlap, all parameters, features extracted / skipped with reasons, quality warnings, PPG-vs-device HR agreement. |
| `plots/01_ppg_peaks.png` | Raw PPG, filtered pulse wave, accepted/rejected peaks, unreliable segments, 10-s zoom. |
| `plots/02_heart_rate.png` | Beat-to-beat pulse rate (accepted/rejected) and device HR. |
| `plots/03_acc_xyz.png` | Raw ACC X/Y/Z. |
| `plots/04_acc_activity.png` | |a|, movement periods, ENMO and epoch intensity. |
| `plots/05_gyro_mag.png` | Gyroscope and magnetometer axes and magnitude. |

## Feature definitions (`features.csv`)

**Window / coverage:** `window_start_utc`, `window_end_utc`, `window_length_s`;
`<stream>_coverage_s` = seconds of samples of each stream inside the window.

**PPG quality**

| Column | Definition |
|---|---|
| `ppg_channel` | Channel used (highest pulse spectral SNR unless set). |
| `ppg_valid_interval_fraction` | Accepted / all pulse intervals in window. |
| `ppg_median_template_corr` | Median correlation of beats with their local median template (−1…1). |
| `ppg_unreliable_fraction` | Fraction of PPG samples flagged unreliable (motion, jumps, flat, NaN). |
| `ppg_motion_fraction` | Fraction flagged by the ACC motion mask. |
| `ppg_quality` | `good` (valid fraction ≥ 0.7 and template corr ≥ 0.9), `fair` (≥ 0.4), else `poor`. |

An interval is rejected (`reason` in `ppg_intervals.csv`) if: outside 30–200 bpm
(`range`); either beat lies in an unreliable segment (`unreliable`); either beat's
template correlation < 0.8 (`morphology`); or it deviates > 20% from the median of
its ±5 neighbours (`outlier`).

**Pulse rate** (from accepted intervals only)

| Column | Unit | Definition |
|---|---|---|
| `hr_mean_bpm` | bpm | 60000 / mean accepted interval |
| `hr_median_bpm`, `hr_min_bpm`, `hr_max_bpm` | bpm | of beat-to-beat rates 60000/IBI |
| `ibi_mean_ms` | ms | mean pulse interval |
| `n_intervals`, `n_intervals_valid`, `valid_coverage` | –, –, 0–1 | coverage = accepted interval time / PPG time |
| `hr_status` | | `ok` (coverage ≥ 0.5), `low_coverage` (0.25–0.5), or why NaN |

**PRV** (time domain, accepted consecutive intervals only)

| Column | Unit | Requirement |
|---|---|---|
| `prv_rmssd_ms`, `prv_sdsd_ms` | ms | ≥ 20 s of accepted intervals and ≥ 10 consecutive pairs |
| `prv_sdnn_ms` | ms | ≥ 50 s of accepted intervals |
| `prv_pnn50_pct`, `prv_pnn20_pct` | % | ≥ 50 s of accepted intervals |
| `prv_n_successive_pairs`, `prv_valid_s` | –, s | inputs actually used |
| `prv_status` | | `ok`, `ok_ultra_short` (RMSSD only), or reasons |

**Pulse morphology (experimental):** `pulse_amplitude_au` (median peak − foot of the
0.5–8 Hz inverted pulse, ADC a.u., within-session comparison only),
`pulse_foot_to_peak_ms` (foot → detected peak; not the classic systolic upstroke
time when the pulse has a systolic shoulder), `morph_n_beats`, `morph_status`.

**Device HR (Polar algorithm, unvalidated):** `device_hr_mean/min/max_bpm`,
`device_hr_n`, `device_hr_status`. Zeros (no estimate) are excluded.

**Accelerometer** (units mg; 1 g = 1000 mg)

| Column | Definition |
|---|---|
| `acc_x/y/z_mean_mg` | Mean per axis (depends on orientation / placement) |
| `acc_magnitude_mean_mg`, `acc_magnitude_sd_mg` | Vector magnitude √(x²+y²+z²) |
| `acc_enmo_mean_mg` | Mean of max(|a| − 1000 mg, 0) |
| `acc_mad_mg` | Mean amplitude deviation of |a| |
| `acc_dominant_freq_hz` | Peak of the 0.3–10 Hz spectrum of the first principal component of detrended X/Y/Z; NaN when movement power < 25 mg². Only meaningful for rhythmic activity (e.g. walking). |
| `acc_movement_fraction` | Fraction of samples in movement (1-s total X/Y/Z SD > 40 mg) |
| `activity_level` | ENMO cut-points: sedentary < 45, light < 100, moderate < 400, vigorous ≥ 400 mg (Hildebrand 2014, **wrist**; provisional for Verity Sense placement) |

**Gyroscope / magnetometer:** `gyro_speed_mean/p95/max_dps` (|ω|),
`gyro_total_rotation_deg` (∫|ω|dt; bias not removed); `mag_field_mean_gauss`,
`mag_field_sd_gauss`, `mag_status` (flags magnitudes outside Earth's 0.25–0.65 G range).

## Results: recording_001 (47 s, 2026-11-27 01:56 UTC)

See `docs/recording_001_audit.md` for the full data audit.

* PPG pulse rate **76.5 bpm** (beat-to-beat 67–101 bpm), from 22 of 56 intervals
  (`low_coverage`, PPG quality `poor`: most rejections are during 4 movement periods).
* Device HR mean 84.7 bpm; mean absolute difference vs PPG beat rate 11 bpm.
  The clean PPG waveform supports the lower PPG values, but neither is validated.
* RMSSD / SDNN: **not computed**, too little clean data (17 s of accepted intervals).
* ACC: device mostly still (ENMO 7.7 mg, `sedentary`), 4 handling bursts (36% of samples).
* Magnetometer uncalibrated; device PPI column empty; `contact` always false.

## Known limitations

* **Not validated.** No ECG reference; PRV ≠ HRV. Thresholds (motion 40 mg,
  template corr 0.8, outlier 20%, quality labels) are heuristics tuned on one
  47-s recording and must be revisited with more data.
* 55 Hz PPG → ~18 ms sample spacing; parabolic interpolation reduces but does not
  remove timing error, which inflates RMSSD at low variability.
* Peak-based fiducial; the pulse's systolic shoulder makes peak timing sensitive
  to wave reflection. A max-slope fiducial is a planned improvement.
* Activity intensity cut-points come from wrist accelerometry.
* Gyroscope bias not removed; magnetometer not calibrated (no heading).
* Not implemented: frequency-domain PRV, sleep/rest, circadian, reactivity/recovery
  (need longer recordings and event markers).

## Data handling

Raw recordings (`data/samples/recording_*/`) and `results/` are git-ignored because
they contain personal health data. The pipeline verifies by SHA-256 that input
files are unchanged after processing.
