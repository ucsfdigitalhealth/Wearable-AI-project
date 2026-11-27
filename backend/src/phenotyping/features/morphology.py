"""Basic pulse-wave morphology (EXPERIMENTAL).

Computed on the wide band-passed (0.5-8 Hz), inverted PPG so that the
systolic upstroke rises. Only beats that close a valid interval are used.

Limitations:
* Amplitudes are raw ADC counts after filtering (arbitrary units, "a.u."):
  LED current / gain are not exported, so amplitudes are comparable only
  within one recording/session, not across people or sessions.
* An AC/DC perfusion index is NOT computed: the raw DC level includes an
  unknown ADC offset (earlier recordings had negative raw values), so AC/DC
  would not be physiologically meaningful.
* ``foot_to_peak_ms`` is the time from the pulse foot to the *detected* peak.
  Where the pulse has an early systolic shoulder and a later dominant peak (as
  in the audited recording), this is NOT the classic systolic upstroke time.
* Band-pass filtering and 55 Hz sampling (~18 ms) limit timing precision.
  Dicrotic notch / second-derivative features are not attempted.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

NAN = float("nan")


def beat_morphology(morph: np.ndarray, fs: float, beat_samples: np.ndarray, max_search_s: float = 0.5) -> pd.DataFrame:
    """Per-beat pulse amplitude and foot-to-peak time.

    For each peak, the foot is the minimum of ``morph`` between the previous
    peak (or ``max_search_s`` earlier, whichever is later) and the peak.

    Returns
    -------
    DataFrame: ``sample``, ``pulse_amplitude_au`` (peak - foot, a.u.),
    ``foot_to_peak_ms`` (ms). NaN where the foot cannot be located.
    """
    x = np.asarray(morph, float)
    peaks = np.asarray(beat_samples, int)
    amp = np.full(peaks.size, np.nan)
    f2p = np.full(peaks.size, np.nan)
    max_n = int(max_search_s * fs)
    for i, p in enumerate(peaks):
        lo = max(p - max_n, peaks[i - 1] if i > 0 else 0, 0)
        if p - lo < 2:
            continue
        seg = x[lo : p + 1]
        if not np.isfinite(seg).all():
            continue
        foot = lo + int(np.argmin(seg))
        if foot >= p:
            continue
        amp[i] = x[p] - x[foot]
        f2p[i] = (p - foot) / fs * 1000.0
    return pd.DataFrame({"sample": peaks, "pulse_amplitude_au": amp, "foot_to_peak_ms": f2p})


def morphology_summary(beat_morph: pd.DataFrame, min_beats: int = 5) -> dict:
    """Median amplitude / foot-to-peak time over the beats provided (already filtered to valid beats)."""
    a = beat_morph["pulse_amplitude_au"].dropna().to_numpy() if len(beat_morph) else np.array([])
    r = beat_morph["foot_to_peak_ms"].dropna().to_numpy() if len(beat_morph) else np.array([])
    if a.size < min_beats:
        return {"pulse_amplitude_au": NAN, "pulse_foot_to_peak_ms": NAN, "morph_n_beats": int(a.size),
                "morph_status": f"insufficient_valid_beats({a.size}<{min_beats})"}
    return {"pulse_amplitude_au": float(np.median(a)), "pulse_foot_to_peak_ms": float(np.median(r)),
            "morph_n_beats": int(a.size), "morph_status": "experimental"}
