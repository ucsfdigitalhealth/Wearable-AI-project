"""Shared fixtures. EVERYTHING HERE IS SYNTHETIC TEST DATA with known ground truth.

Synthetic files are written to pytest's tmp_path in the same CSV format as
real Polar exports; they never touch data/samples.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

# 2026-11-27T01:56:26Z expressed as ns since the Polar epoch (2000-01-01Z).
T0_NS = int((pd.Timestamp("2026-11-27T01:56:26Z") - pd.Timestamp("2000-01-01T00:00:00Z")).value)


def synthetic_ppg_signal(ibis_ms: np.ndarray, fs: float = 54.82, noise_sd: float = 0.0, seed: int = 0,
                         lead_s: float = 1.0) -> tuple[np.ndarray, np.ndarray]:
    """SYNTHETIC PPG: pulse wave (systolic + reflected Gaussian) at known beat times.

    Returns ``(raw_counts, beat_times_s)``. The raw signal is *inverted* like
    the Verity Sense (counts fall when blood volume rises) and sits on a DC
    level of 100000 counts with a slow 0.1 Hz baseline drift.
    """
    rng = np.random.default_rng(seed)
    beats = lead_s + np.concatenate(([0.0], np.cumsum(np.asarray(ibis_ms, float) / 1000.0)))
    dur = beats[-1] + 1.0
    t = np.arange(0, dur, 1 / fs)
    pulse = np.zeros_like(t)
    for b in beats:
        pulse += 1000 * np.exp(-0.5 * ((t - b) / 0.06) ** 2) + 450 * np.exp(-0.5 * ((t - b - 0.25) / 0.08) ** 2)
    raw = 100000 - pulse + 300 * np.sin(2 * np.pi * 0.1 * t) + rng.normal(0, noise_sd, t.size)
    return raw, beats


def ppg_frame(raw: np.ndarray, fs: float = 54.82, t0_ns: int = T0_NS) -> pd.DataFrame:
    """Build a canonical PPG frame (as returned by the loader) around a SYNTHETIC signal."""
    ns = t0_ns + np.round(np.arange(raw.size) * 1e9 / fs).astype("int64")
    return pd.DataFrame({
        "time": pd.Timestamp("2000-01-01", tz="UTC") + pd.to_timedelta(ns, unit="ns"),
        "sensor_ns": ns, "t_s": (ns - ns[0]) / 1e9,
        "ch0": raw, "ch1": raw + 500, "ch2": raw - 500, "ambient": np.full(raw.size, -170000.0),
    })


def write_polar_csv(path: Path, header: list[str], sensor_ns: np.ndarray, values: list[np.ndarray],
                    fmt: str = "{:.6g}") -> Path:
    """Write a SYNTHETIC file in the Polar export format (';' separated, header row)."""
    phone = (pd.Timestamp("2000-01-01") + pd.to_timedelta(sensor_ns, unit="ns")).strftime("%Y-%m-%dT%H:%M:%S.%f").str[:-3]
    lines = [";".join(["Phone timestamp", "sensor timestamp [ns]"] + header)]
    for i in range(len(sensor_ns)):
        vals = [("" if (isinstance(v[i], float) and np.isnan(v[i])) else
                 (str(v[i]).lower() if isinstance(v[i], (bool, np.bool_)) else fmt.format(v[i]))) for v in values]
        lines.append(";".join([phone[i], str(int(sensor_ns[i]))] + vals))
    path.write_text("\n".join(lines) + "\n")
    return path


def make_recording_dir(root: Path, duration_s: float = 90.0, streams=("acc", "gyro", "mag", "ppg", "hr"),
                       hr_bpm: float = 70.0, move_from_s: float | None = None) -> tuple[Path, dict]:
    """Create a SYNTHETIC recording directory. Returns (dir, ground_truth).

    * PPG: constant pulse rate ``hr_bpm`` with small alternating variability
      (+/-15 ms), so RMSSD is known exactly (30 ms before timing error).
    * ACC: device at rest (|a| = 1000 mg) with a 2 Hz, 300 mg movement on the
      X axis after ``move_from_s`` (if given).
    """
    d = root / "recording_syn"
    d.mkdir(parents=True, exist_ok=True)
    truth: dict = {}
    if "ppg" in streams:
        base = 60000.0 / hr_bpm
        n = int(duration_s * 1000 / base) - 2
        ibis = base + np.where(np.arange(n) % 2 == 0, 15.0, -15.0)
        raw, beats = synthetic_ppg_signal(ibis, noise_sd=5.0)
        fs = 54.82
        ns = T0_NS + np.round(np.arange(raw.size) * 1e9 / fs).astype("int64")
        write_polar_csv(d / "ppg_20261126_175627.csv", ["channel 0", "channel 1", "channel 2", "ambient"], ns,
                        [np.round(raw), np.round(raw + 500), np.round(raw - 500), np.full(raw.size, -170000.0)], "{:.0f}")
        truth.update(ibis=ibis, mean_hr=60000.0 / ibis.mean(), rmssd=30.0)
    if "acc" in streams:
        fs = 52.0
        t = np.arange(0, duration_s, 1 / fs)
        x = np.zeros_like(t)
        if move_from_s is not None:
            x = np.where(t >= move_from_s, 300 * np.sin(2 * np.pi * 2.0 * t), 0.0)
        ns = T0_NS + np.round(t * 1e9).astype("int64")
        write_polar_csv(d / "acc_20261126_175628.csv", ["X [mg]", "Y [mg]", "Z [mg]"], ns,
                        [np.round(x), np.zeros_like(t), np.full_like(t, 1000.0)], "{:.0f}")
    if "gyro" in streams:
        fs = 52.0
        t = np.arange(0, duration_s, 1 / fs)
        ns = T0_NS + np.round(t * 1e9).astype("int64")
        write_polar_csv(d / "gyro_20261126_175629.csv", ["X [dps]", "Y [dps]", "Z [dps]"], ns,
                        [np.full_like(t, 3.0), np.full_like(t, 4.0), np.zeros_like(t)])
        truth["gyro_speed"] = 5.0
    if "mag" in streams:
        fs = 50.0
        t = np.arange(0, duration_s, 1 / fs)
        ns = T0_NS + np.round(t * 1e9).astype("int64")
        write_polar_csv(d / "mag_20261126_175629.csv", ["X [gauss]", "Y [gauss]", "Z [gauss]"], ns,
                        [np.full_like(t, 0.3), np.full_like(t, 0.4), np.zeros_like(t)])
    if "hr" in streams:
        t = np.arange(0, int(duration_s))
        ns = T0_NS + t.astype("int64") * 1_000_000_000
        hr = np.full(t.size, float(round(hr_bpm)))
        hr[0] = 0.0
        write_polar_csv(d / "hr_20261126_175630.csv", ["HR [bpm]", "PPI [ms]", "contact"], ns,
                        [hr, np.full(t.size, np.nan), np.full(t.size, False)], "{:.0f}")
    return d, truth


@pytest.fixture
def synthetic_recording(tmp_path):
    return make_recording_dir(tmp_path, move_from_s=60.0)


REAL_RECORDING = Path(__file__).resolve().parents[1] / "data" / "samples" / "recording_001"
