"""Time-domain pulse rate variability (PRV) from PPG pulse-to-pulse intervals.

PRV is NOT interchangeable with ECG-derived HRV. Pulse arrival time varies
with vascular factors and motion, and peak timing from a 55 Hz PPG has
~18 ms sample spacing (reduced, not removed, by parabolic peak interpolation),
which inflates short-term variability such as RMSSD. Column names use the
``prv_`` prefix to keep this distinction visible.

Minimum-data rules (configurable):

* RMSSD / SDSD: >= ``min_rmssd_valid_s`` seconds of valid intervals and
  >= ``min_successive_pairs`` pairs of consecutive valid intervals. Windows
  shorter than ``min_sdnn_valid_s`` are labelled ``ok_ultra_short``: ultra-short
  RMSSD is commonly reported, but is less stable than the 5-min standard.
* SDNN / pNN50 / pNN20: >= ``min_sdnn_valid_s`` (default 50 s, i.e. ~80% of
  a 1-min window) of valid intervals, because they depend strongly on
  recording length. A 1-min SDNN is still far shorter than the 5-min
  short-term standard and must not be compared with 5-min norms.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

NAN = float("nan")


def successive_differences(ibi_ms: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """Differences between consecutive intervals, only where both are valid (ms)."""
    ibi = np.asarray(ibi_ms, float)
    ok = np.asarray(valid, bool)
    pair_ok = ok[:-1] & ok[1:]
    return np.diff(ibi)[pair_ok]


def rmssd(diffs_ms: np.ndarray) -> float:
    """Root mean square of successive differences (ms)."""
    d = np.asarray(diffs_ms, float)
    return float(np.sqrt(np.mean(d**2))) if d.size else NAN


def sdnn(ibi_ms: np.ndarray) -> float:
    """Sample standard deviation (ddof=1) of intervals (ms)."""
    x = np.asarray(ibi_ms, float)
    return float(np.std(x, ddof=1)) if x.size >= 2 else NAN


def pnn(diffs_ms: np.ndarray, threshold_ms: float) -> float:
    """Percentage of successive differences with |d| > ``threshold_ms`` (%)."""
    d = np.asarray(diffs_ms, float)
    return float(100.0 * np.mean(np.abs(d) > threshold_ms)) if d.size else NAN


def prv_time_domain(intervals: pd.DataFrame, min_rmssd_valid_s: float = 20.0, min_successive_pairs: int = 10,
                    min_sdnn_valid_s: float = 50.0) -> dict:
    """Time-domain PRV for one window.

    Parameters
    ----------
    intervals: window rows of ``compute_intervals`` output, in time order
        (``ibi_ms``, ``valid``).

    Returns
    -------
    dict with ``prv_rmssd_ms``, ``prv_sdsd_ms``, ``prv_sdnn_ms``,
    ``prv_pnn50_pct``, ``prv_pnn20_pct``, ``prv_n_successive_pairs``,
    ``prv_valid_s`` and ``prv_status`` (explains any NaN).
    """
    out = {"prv_rmssd_ms": NAN, "prv_sdsd_ms": NAN, "prv_sdnn_ms": NAN, "prv_pnn50_pct": NAN,
           "prv_pnn20_pct": NAN, "prv_n_successive_pairs": 0, "prv_valid_s": 0.0}
    if len(intervals) == 0:
        out["prv_status"] = "no_intervals"
        return out
    ibi = intervals["ibi_ms"].to_numpy(float)
    valid = intervals["valid"].to_numpy(bool)
    diffs = successive_differences(ibi, valid)
    valid_s = float(ibi[valid].sum() / 1000.0)
    out["prv_n_successive_pairs"] = int(diffs.size)
    out["prv_valid_s"] = round(valid_s, 2)

    reasons = []
    if valid_s >= min_rmssd_valid_s and diffs.size >= min_successive_pairs:
        out["prv_rmssd_ms"] = rmssd(diffs)
        out["prv_sdsd_ms"] = float(np.std(diffs, ddof=1)) if diffs.size >= 2 else NAN
    else:
        reasons.append(f"rmssd:insufficient({valid_s:.0f}s valid,{diffs.size} pairs; need "
                       f"{min_rmssd_valid_s:.0f}s,{min_successive_pairs})")
    if valid_s >= min_sdnn_valid_s:
        out["prv_sdnn_ms"] = sdnn(ibi[valid])
        out["prv_pnn50_pct"] = pnn(diffs, 50.0)
        out["prv_pnn20_pct"] = pnn(diffs, 20.0)
    else:
        reasons.append(f"sdnn_pnn:insufficient({valid_s:.0f}s<{min_sdnn_valid_s:.0f}s valid)")

    if not reasons:
        out["prv_status"] = "ok"
    elif np.isfinite(out["prv_rmssd_ms"]):
        out["prv_status"] = "ok_ultra_short;" + ";".join(reasons)
    else:
        out["prv_status"] = ";".join(reasons)
    return out
