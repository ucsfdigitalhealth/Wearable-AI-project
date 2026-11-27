"""Accelerometer movement features per window / epoch.

Input: an ACC frame with ``x_mg``, ``y_mg``, ``z_mg``, ``magnitude_mg``,
``enmo_mg`` (see ``processing.accelerometer.add_derived_columns``).

Activity intensity uses ENMO cut-points from wrist-worn accelerometry
(Hildebrand et al. 2014: sedentary < 45 mg, light 45-100 mg, moderate
100-400 mg, vigorous >= 400 mg). The Verity Sense is worn on the upper arm or
temple, so these labels are PROVISIONAL and not validated for this placement.
Cut-points were derived for longer epochs of free-living activity; on short
recordings they mostly reflect handling/arm movements.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from phenotyping.processing.accelerometer import dominant_frequency, principal_movement_signal

NAN = float("nan")

DEFAULT_INTENSITY_CUTPOINTS_MG = {"light": 45.0, "moderate": 100.0, "vigorous": 400.0}


def classify_intensity(enmo_mean_mg: float, cutpoints: dict[str, float] | None = None) -> str:
    """Map mean ENMO (mg) to ``sedentary``/``light``/``moderate``/``vigorous`` (or ``unknown`` for NaN)."""
    c = cutpoints or DEFAULT_INTENSITY_CUTPOINTS_MG
    if not np.isfinite(enmo_mean_mg):
        return "unknown"
    if enmo_mean_mg >= c["vigorous"]:
        return "vigorous"
    if enmo_mean_mg >= c["moderate"]:
        return "moderate"
    if enmo_mean_mg >= c["light"]:
        return "light"
    return "sedentary"


def mean_amplitude_deviation(magnitude_mg: np.ndarray) -> float:
    """MAD: mean |(|a| - mean |a|)| in mg (Vaha-Ypya et al. 2015). Orientation independent."""
    m = np.asarray(magnitude_mg, float)
    m = m[np.isfinite(m)]
    return float(np.mean(np.abs(m - m.mean()))) if m.size else NAN


def activity_features(acc: pd.DataFrame, fs: float, motion: np.ndarray | None = None,
                      min_coverage_s: float = 5.0, cutpoints: dict[str, float] | None = None,
                      min_movement_power_mg2: float = 25.0) -> dict:
    """Movement features for one window.

    Returns
    -------
    dict (units in key names): mean X/Y/Z (mg, orientation-dependent), mean and SD
    of |a| (mg), mean ENMO (mg), MAD (mg), dominant movement frequency of |a| (Hz,
    NaN if little movement; computed on the first principal component of
    detrended X/Y/Z, not on |a|), fraction of samples flagged as movement,
    ``activity_level`` and ``acc_status``.
    """
    n = len(acc)
    cov = n / fs
    keys = ["acc_x_mean_mg", "acc_y_mean_mg", "acc_z_mean_mg", "acc_magnitude_mean_mg", "acc_magnitude_sd_mg",
            "acc_enmo_mean_mg", "acc_mad_mg", "acc_dominant_freq_hz", "acc_movement_fraction"]
    out = {k: NAN for k in keys}
    out["activity_level"] = "unknown"
    if cov < min_coverage_s:
        out["acc_status"] = f"insufficient_data({cov:.1f}s<{min_coverage_s}s)"
        return out
    m = acc["magnitude_mg"].to_numpy(float)
    enmo_mean = float(np.nanmean(acc["enmo_mg"]))
    pc = principal_movement_signal(acc["x_mg"], acc["y_mg"], acc["z_mg"])
    freq, _ = dominant_frequency(pc, fs, min_power_mg2=min_movement_power_mg2)
    out.update(
        acc_x_mean_mg=float(acc["x_mg"].mean()), acc_y_mean_mg=float(acc["y_mg"].mean()),
        acc_z_mean_mg=float(acc["z_mg"].mean()), acc_magnitude_mean_mg=float(np.nanmean(m)),
        acc_magnitude_sd_mg=float(np.nanstd(m, ddof=1)), acc_enmo_mean_mg=enmo_mean,
        acc_mad_mg=mean_amplitude_deviation(m), acc_dominant_freq_hz=freq,
        acc_movement_fraction=float(np.mean(motion)) if motion is not None and len(motion) else NAN,
        activity_level=classify_intensity(enmo_mean, cutpoints),
        acc_status="ok_provisional_cutpoints",
    )
    return out


def epoch_summaries(acc: pd.DataFrame, fs: float, epoch_s: float = 5.0, t0: pd.Timestamp | None = None,
                    cutpoints: dict[str, float] | None = None) -> pd.DataFrame:
    """Fixed-length epoch summaries (|a| mean/SD, ENMO mean, MAD, intensity).

    Epochs start at ``t0`` (default: first sample). Epochs with < 50% of the
    expected samples are kept but labelled ``partial``.
    """
    t0 = t0 if t0 is not None else acc["time"].iloc[0]
    rel = (acc["time"] - t0).dt.total_seconds().to_numpy()
    idx = np.floor(rel / epoch_s).astype(int)
    rows = []
    for k in np.unique(idx):
        e = acc.loc[idx == k]
        start = t0 + pd.Timedelta(seconds=k * epoch_s)
        enmo_mean = float(e["enmo_mg"].mean())
        rows.append({
            "epoch_start_utc": start, "epoch_end_utc": start + pd.Timedelta(seconds=epoch_s),
            "n_samples": len(e), "partial": len(e) < 0.5 * epoch_s * fs,
            "acc_magnitude_mean_mg": float(e["magnitude_mg"].mean()),
            "acc_magnitude_sd_mg": float(e["magnitude_mg"].std()),
            "acc_enmo_mean_mg": enmo_mean, "acc_mad_mg": mean_amplitude_deviation(e["magnitude_mg"]),
            "activity_level": classify_intensity(enmo_mean, cutpoints),
        })
    return pd.DataFrame(rows)
