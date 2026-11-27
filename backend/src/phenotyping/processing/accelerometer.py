"""Accelerometer preprocessing.

Units: input X/Y/Z are milli-g (mg) as exported by Polar (1 g = 1000 mg,
assumed; checked by :func:`gravity_calibration_check`). The audited recording
has mean |a| = 997.6 mg, consistent with a calibrated sensor.

Placement: the Verity Sense is normally worn on the upper arm or temple.
Axis orientation relative to the body depends on how it was strapped on and is
not recorded, so features here are orientation-independent (vector magnitude
based) unless stated.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from scipy import signal

G_MG = 1000.0


def vector_magnitude(x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
    """Euclidean norm sqrt(x^2 + y^2 + z^2), same unit as the inputs (mg)."""
    return np.sqrt(np.asarray(x, float) ** 2 + np.asarray(y, float) ** 2 + np.asarray(z, float) ** 2)


def enmo(magnitude_mg: np.ndarray, g_mg: float = G_MG) -> np.ndarray:
    """Euclidean Norm Minus One, truncated at zero: max(|a| - 1 g, 0), in mg.

    Assumes the sensor is calibrated so that |a| = 1 g at rest. Negative values
    are set to 0 (standard ENMO definition, van Hees et al. 2013).
    """
    return np.maximum(np.asarray(magnitude_mg, float) - g_mg, 0.0)


def gravity_calibration_check(magnitude_mg: np.ndarray, fs: float, still_sd_mg: float = 10.0,
                              window_s: float = 2.0, tolerance_mg: float = 50.0) -> dict:
    """Check that |a| ~ 1000 mg during still periods.

    Still periods are ``window_s`` windows whose |a| SD < ``still_sd_mg``.
    Returns ``{"still_windows", "median_still_magnitude_mg", "ok", "message"}``.
    ``ok`` is None when there are no still windows to judge from.
    """
    m = np.asarray(magnitude_mg, float)
    n = max(2, int(window_s * fs))
    means = [np.nanmean(m[i : i + n]) for i in range(0, len(m) - n + 1, n) if np.nanstd(m[i : i + n]) < still_sd_mg]
    if not means:
        return {"still_windows": 0, "median_still_magnitude_mg": float("nan"), "ok": None,
                "message": "No still periods found; calibration not checked."}
    med = float(np.median(means))
    ok = abs(med - G_MG) <= tolerance_mg
    msg = f"Median |a| at rest = {med:.1f} mg" + ("" if ok else f" (deviates > {tolerance_mg} mg from 1 g; ENMO may be biased)")
    return {"still_windows": len(means), "median_still_magnitude_mg": med, "ok": ok, "message": msg}


def motion_mask(x_mg: np.ndarray, y_mg: np.ndarray, z_mg: np.ndarray, fs: float, window_s: float = 1.0,
                threshold_mg: float = 40.0, pad_s: float = 0.5) -> np.ndarray:
    """Boolean mask of samples during movement.

    Movement = total rolling SD over ``window_s`` (centred),
    sqrt(SD_x^2 + SD_y^2 + SD_z^2) in mg, above ``threshold_mg``, expanded by
    ``pad_s`` on each side. The total SD is rotation-invariant, unlike the SD
    of |a|, which almost ignores movement perpendicular to gravity.

    Used to flag PPG beats likely corrupted by motion. The default threshold is
    a heuristic tuned on ONE recording (recording_001: rest 8-10 mg, a low-amplitude
    ~4 Hz oscillation up to ~30 mg that did not disturb the PPG, handling
    bursts > 40 mg); it is not a validated cut-point.
    """
    n = max(3, int(window_s * fs))
    var = np.zeros(len(np.asarray(x_mg)))
    for v in (x_mg, y_mg, z_mg):
        var += pd.Series(np.asarray(v, float)).rolling(n, center=True, min_periods=max(2, n // 2)).var().to_numpy()
    moving = np.sqrt(var) > threshold_mg
    pad = int(pad_s * fs)
    if pad and moving.any():
        moving = np.convolve(moving.astype(int), np.ones(2 * pad + 1, int), mode="same") > 0
    return moving


def dominant_frequency(x: np.ndarray, fs: float, band_hz: tuple[float, float] = (0.3, 10.0),
                       min_power_mg2: float = 25.0) -> tuple[float, float]:
    """Dominant movement frequency of a signal (e.g. |a| in mg).

    The signal is detrended and its Welch spectrum searched within
    ``band_hz``. If the signal variance within the band is below
    ``min_power_mg2`` (i.e. little movement) the frequency is meaningless and
    NaN is returned.

    Returns
    -------
    (frequency_hz, band_power_mg2)
    """
    x = np.asarray(x, float)
    x = x[np.isfinite(x)]
    if x.size < int(2 * fs):
        return float("nan"), float("nan")
    nper = min(x.size, int(8 * fs))
    f, p = signal.welch(signal.detrend(x), fs, nperseg=nper)
    band = (f >= band_hz[0]) & (f <= min(band_hz[1], fs / 2))
    if not band.any():
        return float("nan"), float("nan")
    df = f[1] - f[0]
    power = float(p[band].sum() * df)
    if power < min_power_mg2:
        return float("nan"), power
    return float(f[band][np.argmax(p[band])]), power


def principal_movement_signal(x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
    """Project detrended X/Y/Z onto their first principal component (mg).

    Gives a 1-D movement signal along the dominant movement axis, whatever
    the sensor orientation. Preferred over |a| for frequency analysis: an
    oscillation perpendicular to gravity appears in |a| at TWICE its true
    frequency (|a| depends on the square of the perpendicular component).
    Rows with NaN are dropped.
    """
    xyz = np.column_stack([np.asarray(v, float) for v in (x, y, z)])
    xyz = xyz[np.isfinite(xyz).all(axis=1)]
    if xyz.shape[0] < 3:
        return np.array([])
    xyz = signal.detrend(xyz, axis=0)
    _, _, vt = np.linalg.svd(xyz, full_matrices=False)
    return xyz @ vt[0]


def add_derived_columns(acc: pd.DataFrame) -> pd.DataFrame:
    """Return a copy of a loaded ACC frame with ``magnitude_mg`` and ``enmo_mg`` added."""
    out = acc.copy()
    out["magnitude_mg"] = vector_magnitude(out["x_mg"], out["y_mg"], out["z_mg"])
    out["enmo_mg"] = enmo(out["magnitude_mg"])
    return out
