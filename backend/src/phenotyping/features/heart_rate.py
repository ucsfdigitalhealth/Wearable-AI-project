"""Heart-rate features from PPG pulse intervals, plus device-reported HR.

All PPG-derived values are *pulse rate* (from pulse-to-pulse intervals of the
optical signal), which approximates but is not identical to ECG heart rate.
None of these values has been validated against an ECG reference.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

NAN = float("nan")


def instantaneous_hr_bpm(ibi_ms: np.ndarray) -> np.ndarray:
    """Beat-to-beat pulse rate: 60000 / interval (ms) -> beats per minute."""
    ibi = np.asarray(ibi_ms, float)
    with np.errstate(divide="ignore", invalid="ignore"):
        return np.where(ibi > 0, 60000.0 / ibi, np.nan)


def heart_rate_summary(intervals: pd.DataFrame, window_ppg_s: float, min_valid_intervals: int = 5,
                       min_valid_coverage: float = 0.25, good_coverage: float = 0.5) -> dict:
    """Summarise pulse rate within one window.

    Parameters
    ----------
    intervals: rows of :func:`phenotyping.processing.ppg.compute_intervals`
        falling inside the window (``ibi_ms``, ``valid``).
    window_ppg_s: seconds of PPG signal inside the window.
    min_valid_intervals: fewer valid intervals -> NaN.
    min_valid_coverage: valid interval time / PPG time below this -> NaN.
    good_coverage: coverage below this is reported as ``low_coverage``.

    Returns
    -------
    dict with ``hr_mean_bpm`` (= 60000 / mean valid interval, i.e. beats per
    minute over the clean beats), ``hr_median_bpm``, ``hr_min_bpm``,
    ``hr_max_bpm`` (from instantaneous rates of valid intervals),
    ``ibi_mean_ms`` (mean pulse interval), ``n_intervals``,
    ``n_intervals_valid``, ``valid_coverage`` (0-1) and ``hr_status``.
    """
    n_total = int(len(intervals))
    valid = intervals.loc[intervals["valid"].astype(bool), "ibi_ms"].to_numpy(float) if n_total else np.array([])
    coverage = float(valid.sum() / 1000.0 / window_ppg_s) if window_ppg_s > 0 else 0.0
    out = {
        "hr_mean_bpm": NAN, "hr_median_bpm": NAN, "hr_min_bpm": NAN, "hr_max_bpm": NAN,
        "ibi_mean_ms": NAN, "n_intervals": n_total, "n_intervals_valid": int(valid.size),
        "valid_coverage": round(min(coverage, 1.0), 3),
    }
    if window_ppg_s <= 0:
        out["hr_status"] = "no_ppg_in_window"
        return out
    if valid.size < min_valid_intervals:
        out["hr_status"] = f"insufficient_valid_intervals({valid.size}<{min_valid_intervals})"
        return out
    if coverage < min_valid_coverage:
        out["hr_status"] = f"insufficient_coverage({coverage:.2f}<{min_valid_coverage})"
        return out
    inst = instantaneous_hr_bpm(valid)
    out.update(
        hr_mean_bpm=60000.0 / valid.mean(),
        hr_median_bpm=float(np.median(inst)),
        hr_min_bpm=float(inst.min()),
        hr_max_bpm=float(inst.max()),
        ibi_mean_ms=float(valid.mean()),
        hr_status="ok" if coverage >= good_coverage else "low_coverage",
    )
    return out


def device_hr_summary(hr: pd.DataFrame) -> dict:
    """Summarise the HR values reported by the Polar device itself.

    ``hr`` is the window slice of the loaded ``hr`` stream (column ``hr_bpm``).
    Values <= 0 mean "no estimate" and are excluded. The device algorithm is a
    black box with its own smoothing; values are reported for comparison only.
    """
    v = hr["hr_bpm"].to_numpy(float) if len(hr) else np.array([])
    v = v[np.isfinite(v) & (v > 0)]
    if v.size == 0:
        return {"device_hr_mean_bpm": NAN, "device_hr_min_bpm": NAN, "device_hr_max_bpm": NAN,
                "device_hr_n": 0, "device_hr_status": "no_valid_device_hr"}
    return {"device_hr_mean_bpm": float(v.mean()), "device_hr_min_bpm": float(v.min()),
            "device_hr_max_bpm": float(v.max()), "device_hr_n": int(v.size), "device_hr_status": "ok_unvalidated"}


def compare_with_device_hr(intervals: pd.DataFrame, device_hr: pd.DataFrame, max_lag_s: float = 1.0) -> dict:
    """Compare accepted PPG pulse rates with time-matched device HR samples.

    ``intervals`` needs ``time_utc``, ``valid``, ``instantaneous_hr_bpm``;
    ``device_hr`` needs ``time`` and ``hr_bpm`` (values <= 0 ignored). Each
    accepted interval is matched to the nearest device sample within
    ``max_lag_s``. This is an agreement check between two unvalidated
    estimates, NOT a validation: the device output is itself smoothed.

    Returns ``{"n_matched", "mean_diff_bpm" (PPG - device), "mean_abs_diff_bpm",
    "corr"}``; NaN when fewer than 3 matches.
    """
    v = intervals[intervals["valid"].astype(bool)].sort_values("time_utc")
    d = device_hr[device_hr["hr_bpm"] > 0].sort_values("time")
    nan = {"n_matched": 0, "mean_diff_bpm": NAN, "mean_abs_diff_bpm": NAN, "corr": NAN}
    if v.empty or d.empty:
        return nan
    m = pd.merge_asof(v[["time_utc", "instantaneous_hr_bpm"]], d[["time", "hr_bpm"]], left_on="time_utc",
                      right_on="time", direction="nearest", tolerance=pd.Timedelta(seconds=max_lag_s)).dropna()
    if len(m) < 3:
        return {**nan, "n_matched": int(len(m))}
    diff = m["instantaneous_hr_bpm"] - m["hr_bpm"]
    a, b = m["instantaneous_hr_bpm"].to_numpy(), m["hr_bpm"].to_numpy()
    corr = float(np.corrcoef(a, b)[0, 1]) if a.std() > 0 and b.std() > 0 else NAN
    return {"n_matched": int(len(m)), "mean_diff_bpm": float(diff.mean()), "mean_abs_diff_bpm": float(diff.abs().mean()),
            "corr": corr}
