"""PPG preprocessing, beat detection, beat-interval cleaning and quality.

Conventions
-----------
* Raw Polar Verity Sense PPG values are photodiode ADC counts (no physical
  unit). In the audited recording the pulse wave is *inverted*: counts fall
  when blood volume rises. Verified on an ensemble average of clean beats:
  after inversion the steepest edge is the rising one (systolic upstroke,
  slope ~2x the falling edge), the physiological pattern.
  ``invert=True`` therefore flips the sign before beat detection.
* Times are seconds relative to the first PPG sample unless stated.
* Fiducial point: the maximum of the 0.5-4 Hz band-passed pulse. In the
  audited recording the pulse has an early systolic shoulder followed by a
  later, higher peak; the detector locks onto the later peak. A slope-based
  fiducial (max upstroke) may give lower-jitter intervals; not yet implemented.
* A detected pulse peak is a PPG feature, not an ECG R-peak. Intervals between
  pulse peaks are pulse-to-pulse intervals (PPI). Variability computed from
  them is pulse rate variability (PRV), not ECG heart rate variability (HRV).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import signal

PPG_CHANNELS = ("ch0", "ch1", "ch2")


# --------------------------------------------------------------------------
# Filtering
# --------------------------------------------------------------------------
def _finite_runs(x: np.ndarray) -> list[tuple[int, int]]:
    """Return ``[(start, stop), ...]`` for runs of finite values."""
    finite = np.isfinite(x)
    if not finite.any():
        return []
    edges = np.diff(np.concatenate(([0], finite.astype(int), [0])))
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)))


def bandpass_filter(x: np.ndarray, fs: float, low_hz: float, high_hz: float, order: int = 2) -> np.ndarray:
    """Zero-phase Butterworth band-pass filter.

    Parameters
    ----------
    x: signal (any unit). NaNs are *not* interpolated: each finite run is
       filtered separately and runs too short to filter become NaN.
    fs: sampling rate (Hz).
    low_hz, high_hz: pass band edges (Hz).
    order: Butterworth order (applied forwards and backwards).

    Returns
    -------
    Filtered signal in the same unit, same length as ``x``.
    """
    if not 0 < low_hz < high_hz < fs / 2:
        raise ValueError(f"Invalid band {low_hz}-{high_hz} Hz for fs={fs:.2f} Hz.")
    sos = signal.butter(order, [low_hz, high_hz], btype="band", fs=fs, output="sos")
    x = np.asarray(x, dtype=float)
    out = np.full_like(x, np.nan)
    min_len = 3 * (2 * len(sos) + 1) + 1
    for a, b in _finite_runs(x):
        if b - a >= min_len:
            out[a:b] = signal.sosfiltfilt(sos, x[a:b])
    return out


def pulse_spectral_snr(x: np.ndarray, fs: float, hr_band_hz: tuple[float, float] = (0.7, 3.5),
                       window_s: float = 8.0, peak_halfwidth_hz: float = 0.2) -> float:
    """Median (over windows) fraction of 0.5-8 Hz power near the dominant pulse frequency.

    For each ``window_s`` window, finds the highest spectral peak inside
    ``hr_band_hz`` and returns the power within +/- ``peak_halfwidth_hz`` of it
    and of its first harmonic, divided by total power in 0.5-8 Hz.
    Unitless, 0-1. Higher means a more periodic pulse. NaN if too short.
    """
    x = np.asarray(x, dtype=float)
    n = int(window_s * fs)
    if n < 16 or np.isfinite(x).sum() < n:
        return float("nan")
    vals = []
    for s in range(0, len(x) - n + 1, n // 2):
        seg = x[s : s + n]
        if not np.isfinite(seg).all():
            continue
        f, p = signal.welch(signal.detrend(seg), fs, nperseg=n, nfft=max(1024, n))
        band = (f >= hr_band_hz[0]) & (f <= hr_band_hz[1])
        total = p[(f >= 0.5) & (f <= 8)].sum()
        if total <= 0 or not band.any():
            continue
        f0 = f[band][np.argmax(p[band])]
        near = (np.abs(f - f0) <= peak_halfwidth_hz) | (np.abs(f - 2 * f0) <= peak_halfwidth_hz)
        vals.append(p[near].sum() / total)
    return float(np.median(vals)) if vals else float("nan")


def select_ppg_channel(ppg: pd.DataFrame, fs: float, channels: tuple[str, ...] = PPG_CHANNELS,
                       band_hz: tuple[float, float] = (0.5, 4.0)) -> tuple[str, dict[str, float]]:
    """Choose the PPG channel with the highest pulse spectral SNR.

    Returns ``(best_channel, {channel: snr})``.
    """
    scores = {}
    for ch in channels:
        if ch in ppg:
            filt = bandpass_filter(ppg[ch].to_numpy(float), fs, *band_hz)
            scores[ch] = pulse_spectral_snr(filt, fs)
    valid = {k: v for k, v in scores.items() if np.isfinite(v)}
    if not valid:
        raise ValueError("No PPG channel has enough finite data to assess.")
    return max(valid, key=valid.get), scores


# --------------------------------------------------------------------------
# Discontinuities / unreliable segments
# --------------------------------------------------------------------------
def detect_discontinuities(x: np.ndarray, fs: float, threshold: float = 12.0, pad_s: float = 1.0) -> tuple[np.ndarray, list[int]]:
    """Flag abrupt jumps in a raw signal (gain changes, contact loss, motion spikes).

    A sample-to-sample difference is a jump when ``|dx| > threshold x MAD``
    of all differences (MAD scaled to a normal SD). Samples within ``pad_s``
    seconds of a jump are marked unreliable.

    Returns
    -------
    mask: boolean array, True = unreliable.
    jump_indices: indices ``i`` where the jump is between samples i and i+1.
    """
    x = np.asarray(x, dtype=float)
    mask = ~np.isfinite(x)
    dx = np.diff(x)
    good = np.isfinite(dx)
    if good.sum() < 10:
        return np.ones_like(mask), []
    med = np.median(dx[good])
    mad = 1.4826 * np.median(np.abs(dx[good] - med))
    if mad == 0:
        mad = np.std(dx[good]) or 1.0
    jumps = np.flatnonzero(good & (np.abs(dx - med) > threshold * mad))
    pad = int(round(pad_s * fs))
    for j in jumps:
        mask[max(0, j - pad) : j + pad + 2] = True
    return mask, jumps.tolist()


def flat_segments(x: np.ndarray, fs: float, min_s: float = 0.5) -> np.ndarray:
    """Mark runs of identical consecutive values lasting >= ``min_s`` s (saturation / dropout)."""
    x = np.asarray(x, dtype=float)
    mask = np.zeros(len(x), dtype=bool)
    same = np.concatenate(([False], np.diff(x) == 0))
    min_n = max(2, int(min_s * fs))
    run_start = None
    for i, s in enumerate(np.append(same, False)):
        if s and run_start is None:
            run_start = i - 1
        elif not s and run_start is not None:
            if i - run_start >= min_n:
                mask[run_start:i] = True
            run_start = None
    return mask


# --------------------------------------------------------------------------
# Beat detection
# --------------------------------------------------------------------------
def _parabolic_offset(y_prev: float, y0: float, y_next: float) -> float:
    """Sub-sample offset (in samples, within +/-0.5) of a parabola vertex."""
    denom = y_prev - 2 * y0 + y_next
    if denom == 0 or not np.isfinite(denom):
        return 0.0
    return float(np.clip(0.5 * (y_prev - y_next) / denom, -0.5, 0.5))


def detect_beats(x_filt: np.ndarray, fs: float, max_hr_bpm: float = 200.0,
                 rel_prominence: float = 0.35, local_window_s: float = 5.0) -> pd.DataFrame:
    """Detect pulse peaks in a band-passed, correctly oriented PPG signal.

    Parameters
    ----------
    x_filt: band-passed PPG with systolic peaks pointing up (arbitrary units).
    fs: sampling rate (Hz).
    max_hr_bpm: refractory limit; peaks closer than 60/max_hr_bpm s are merged.
    rel_prominence: a peak is kept if its prominence >= ``rel_prominence`` x
        the local signal scale (2 x SD over ``local_window_s`` centred window).
    local_window_s: window for the local amplitude scale (s).

    Returns
    -------
    DataFrame, one row per beat: ``sample`` (int index), ``t_s`` (s, refined
    with parabolic interpolation, which reduces the 1/fs timing quantisation),
    ``prominence`` (signal units).
    """
    x = np.asarray(x_filt, dtype=float)
    cols = ["sample", "t_s", "prominence"]
    if np.isfinite(x).sum() < fs:
        return pd.DataFrame(columns=cols)
    xz = np.where(np.isfinite(x), x, np.nanmin(x))
    distance = max(1, int(np.floor(fs * 60.0 / max_hr_bpm)))
    peaks, props = signal.find_peaks(xz, distance=distance, prominence=0)
    if peaks.size == 0:
        return pd.DataFrame(columns=cols)
    win = max(3, int(local_window_s * fs))
    local_sd = pd.Series(x).rolling(win, center=True, min_periods=win // 3).std().to_numpy()
    keep = props["prominences"] >= rel_prominence * 2 * local_sd[peaks]
    keep &= np.isfinite(x[peaks])
    peaks, prom = peaks[keep], props["prominences"][keep]
    t = []
    for p in peaks:
        off = _parabolic_offset(x[p - 1], x[p], x[p + 1]) if 0 < p < len(x) - 1 else 0.0
        t.append((p + off) / fs)
    return pd.DataFrame({"sample": peaks.astype(int), "t_s": np.asarray(t, float), "prominence": prom})


def beat_template_correlation(x_filt: np.ndarray, fs: float, beat_samples: np.ndarray,
                              pre_s: float = 0.25, post_s: float = 0.35, n_neighbours: int = 8) -> np.ndarray:
    """Pearson correlation of each beat with a *local* median beat template.

    Each beat is the segment [peak - pre_s, peak + post_s]. The template for
    beat i is the sample-wise median of up to ``n_neighbours`` beats on each
    side (including beat i), so slow changes in heart rate and pulse shape do
    not count as poor quality. Beats that do not fit inside the signal or
    contain NaN get NaN. Unitless, -1..1.
    """
    x = np.asarray(x_filt, dtype=float)
    pre, post = int(pre_s * fs), int(post_s * fs)
    segs, idx = [], []
    for i, p in enumerate(beat_samples):
        if p - pre >= 0 and p + post < len(x):
            seg = x[p - pre : p + post + 1]
            if np.isfinite(seg).all():
                segs.append(seg)
                idx.append(i)
    corr = np.full(len(beat_samples), np.nan)
    if len(segs) < 3:
        return corr
    segs = np.vstack(segs)
    for k, (row, i) in enumerate(zip(segs, idx)):
        lo, hi = max(0, k - n_neighbours), min(len(segs), k + n_neighbours + 1)
        template = np.median(segs[lo:hi], axis=0)
        if np.std(row) > 0 and np.std(template) > 0:
            corr[i] = np.corrcoef(row, template)[0, 1]
    return corr


# --------------------------------------------------------------------------
# Intervals
# --------------------------------------------------------------------------
def compute_intervals(beats: pd.DataFrame, unreliable: np.ndarray | None = None, fs: float | None = None,
                      min_ibi_ms: float = 300.0, max_ibi_ms: float = 2000.0,
                      max_rel_deviation: float = 0.20, neighbourhood: int = 5,
                      min_template_corr: float = 0.8) -> pd.DataFrame:
    """Convert pulse peaks to pulse-to-pulse intervals and flag artefacts.

    An interval (from beat i-1 to beat i) is invalid when any of:

    * ``range``: outside [min_ibi_ms, max_ibi_ms] (default 30-200 bpm);
    * ``unreliable``: either beat falls in an unreliable sample (``unreliable``
      mask indexed by PPG sample, needs ``fs``-consistent ``sample`` column);
    * ``morphology``: either beat's template correlation < ``min_template_corr``
      (uses a ``template_corr`` column in ``beats`` if present);
    * ``outlier``: deviates more than ``max_rel_deviation`` from the median of
      up to ``neighbourhood`` intervals on each side (missed / extra beats).

    Returns
    -------
    DataFrame with ``t_s`` (time of the closing beat, s), ``ibi_ms``,
    ``valid`` (bool) and ``reason`` ("" when valid; otherwise the first failed rule).
    """
    cols = ["t_s", "ibi_ms", "valid", "reason"]
    if len(beats) < 2:
        return pd.DataFrame(columns=cols)
    t = beats["t_s"].to_numpy(float)
    ibi = np.diff(t) * 1000.0
    reason = np.full(ibi.size, "", dtype=object)

    def set_reason(mask: np.ndarray, label: str) -> None:
        reason[(reason == "") & mask] = label

    set_reason((ibi < min_ibi_ms) | (ibi > max_ibi_ms), "range")
    if unreliable is not None:
        s = beats["sample"].to_numpy(int)
        bad_beat = np.asarray(unreliable, bool)[np.clip(s, 0, len(unreliable) - 1)]
        set_reason(bad_beat[:-1] | bad_beat[1:], "unreliable")
    if "template_corr" in beats:
        c = beats["template_corr"].to_numpy(float)
        bad = ~(c >= min_template_corr)  # NaN counts as bad
        set_reason(bad[:-1] | bad[1:], "morphology")
    in_range = (ibi >= min_ibi_ms) & (ibi <= max_ibi_ms)
    for i in range(ibi.size):
        lo, hi = max(0, i - neighbourhood), min(ibi.size, i + neighbourhood + 1)
        neigh = np.concatenate((ibi[lo:i], ibi[i + 1 : hi]))
        neigh = neigh[(neigh >= min_ibi_ms) & (neigh <= max_ibi_ms)]
        if in_range[i] and neigh.size >= 2:
            ref = np.median(neigh)
            if abs(ibi[i] - ref) > max_rel_deviation * ref:
                set_reason(np.arange(ibi.size) == i, "outlier")
    return pd.DataFrame({"t_s": t[1:], "ibi_ms": ibi, "valid": reason == "", "reason": reason})


# --------------------------------------------------------------------------
# One-call processing
# --------------------------------------------------------------------------
@dataclass
class PPGResult:
    """Output of :func:`process_ppg`. Time arrays are seconds since first PPG sample."""

    channel: str
    channel_snr: dict[str, float]
    fs_hz: float
    t_s: np.ndarray
    raw: np.ndarray            # selected channel, raw ADC counts (not inverted)
    filtered: np.ndarray       # band-passed, oriented so pulses point up (a.u.)
    morph: np.ndarray          # wider band-pass for morphology (a.u.)
    unreliable: np.ndarray     # bool per sample
    jumps: list[int]
    beats: pd.DataFrame        # sample, t_s, prominence, template_corr
    intervals: pd.DataFrame    # t_s, ibi_ms, valid, reason
    inverted: bool


def process_ppg(ppg: pd.DataFrame, fs: float, channel: str = "auto", invert: bool = True,
                band_hz: tuple[float, float] = (0.5, 4.0), morph_band_hz: tuple[float, float] = (0.5, 8.0),
                filter_order: int = 2, max_hr_bpm: float = 200.0, min_hr_bpm: float = 30.0,
                rel_prominence: float = 0.35, jump_threshold: float = 12.0, jump_pad_s: float = 1.0,
                extra_unreliable: np.ndarray | None = None, max_rel_deviation: float = 0.20,
                min_template_corr: float = 0.8) -> PPGResult:
    """Full PPG chain: channel selection, filtering, quality masks, beats, intervals.

    ``ppg`` is the ``data`` frame of a loaded PPG ``SensorStream``.
    ``extra_unreliable`` (bool per PPG sample) lets callers add masks from
    other sensors, e.g. accelerometer motion. See module docstring for units.
    """
    if channel == "auto":
        channel, snr = select_ppg_channel(ppg, fs, band_hz=band_hz)
    else:
        if channel not in ppg:
            raise ValueError(f"PPG channel '{channel}' not in data ({list(ppg.columns)}).")
        snr = {channel: pulse_spectral_snr(bandpass_filter(ppg[channel].to_numpy(float), fs, *band_hz), fs)}
    raw = ppg[channel].to_numpy(float)
    sign = -1.0 if invert else 1.0
    filt = sign * bandpass_filter(raw, fs, *band_hz, order=filter_order)
    morph = sign * bandpass_filter(raw, fs, *morph_band_hz, order=filter_order)

    unreliable, jumps = detect_discontinuities(raw, fs, jump_threshold, jump_pad_s)
    if "ambient" in ppg:
        amb_mask, _ = detect_discontinuities(ppg["ambient"].to_numpy(float), fs, jump_threshold, jump_pad_s)
        unreliable |= amb_mask
    unreliable |= flat_segments(raw, fs)
    unreliable |= ~np.isfinite(filt)
    if extra_unreliable is not None:
        unreliable |= np.asarray(extra_unreliable, bool)

    beats = detect_beats(filt, fs, max_hr_bpm=max_hr_bpm, rel_prominence=rel_prominence)
    beats["template_corr"] = beat_template_correlation(filt, fs, beats["sample"].to_numpy(int))
    intervals = compute_intervals(
        beats, unreliable, fs,
        min_ibi_ms=60000.0 / max_hr_bpm, max_ibi_ms=60000.0 / min_hr_bpm,
        max_rel_deviation=max_rel_deviation, min_template_corr=min_template_corr,
    )
    return PPGResult(channel, snr, fs, ppg["t_s"].to_numpy(float), raw, filt, morph, unreliable,
                     jumps, beats, intervals, invert)
