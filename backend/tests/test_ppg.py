"""PPG processing on SYNTHETIC signals with known beat times."""

import numpy as np
import pytest
from conftest import ppg_frame, synthetic_ppg_signal

from phenotyping.processing.ppg import (
    bandpass_filter, compute_intervals, detect_beats, detect_discontinuities, flat_segments, process_ppg,
    pulse_spectral_snr,
)

FS = 54.82


def test_bandpass_removes_dc_and_keeps_pulse_band():
    t = np.arange(0, 30, 1 / FS)
    x = 5000 + 100 * np.sin(2 * np.pi * 1.2 * t) + 100 * np.sin(2 * np.pi * 15 * t)
    y = bandpass_filter(x, FS, 0.5, 4.0)
    mid = slice(int(5 * FS), int(25 * FS))
    assert abs(np.mean(y[mid])) < 2
    assert np.std(y[mid]) == pytest.approx(100 / np.sqrt(2), rel=0.1)  # 1.2 Hz kept, 15 Hz removed


def test_bandpass_does_not_fill_nans():
    x = np.sin(np.arange(1000) / 10.0)
    x[400:410] = np.nan
    y = bandpass_filter(x, FS, 0.5, 4.0)
    assert np.isnan(y[400:410]).all()
    assert np.isfinite(y[:400]).all()


def test_bandpass_rejects_invalid_band():
    with pytest.raises(ValueError):
        bandpass_filter(np.zeros(100), FS, 4.0, 40.0)


def test_spectral_snr_higher_for_clean_pulse():
    raw, _ = synthetic_ppg_signal(np.full(40, 800.0))
    rng = np.random.default_rng(1)
    clean = bandpass_filter(-raw, FS, 0.5, 4)
    noisy = bandpass_filter(-raw + rng.normal(0, 2000, raw.size), FS, 0.5, 4)
    assert pulse_spectral_snr(clean, FS) > 0.6 > pulse_spectral_snr(noisy, FS)


def test_beat_detection_recovers_known_intervals_within_timing_resolution():
    ibis = 800 + 40 * np.sin(np.arange(60) / 4)  # 69-79 bpm, smooth variability
    raw, beats = synthetic_ppg_signal(ibis, noise_sd=5)
    filt = bandpass_filter(-raw, FS, 0.5, 4.0)
    det = detect_beats(filt, FS)
    det_ibi = np.diff(det["t_s"].to_numpy()) * 1000
    assert len(det) == len(beats)
    # Interior intervals (filter edge effects excluded) within ~1/3 sample.
    err = det_ibi[2:-2] - ibis[2:-2]
    assert np.max(np.abs(err)) < 8.0
    assert abs(np.mean(err)) < 1.0


def test_polarity_matters():
    raw, beats = synthetic_ppg_signal(np.full(40, 750.0), noise_sd=2)
    res_ok = process_ppg(ppg_frame(raw), FS, channel="ch0", invert=True)
    res_wrong = process_ppg(ppg_frame(raw), FS, channel="ch0", invert=False)
    # Correct orientation: beats all valid, near true count.
    assert abs(len(res_ok.beats) - len(beats)) <= 1
    assert res_ok.intervals["valid"].mean() > 0.9
    assert res_wrong.beats["t_s"].sub(res_ok.beats["t_s"].reindex(res_wrong.beats.index)).abs().median() > 0.1


def test_discontinuity_detection_flags_step():
    raw, _ = synthetic_ppg_signal(np.full(40, 800.0), noise_sd=5)
    raw[1000:] -= 500000  # gain change like old demo_ppg.txt
    mask, jumps = detect_discontinuities(raw, FS, threshold=12, pad_s=1.0)
    assert 999 in jumps
    assert mask[990:1010].all()
    assert mask.mean() < 0.1


def test_flat_segments():
    x = np.random.default_rng(0).normal(size=500)
    x[100:150] = 7.0
    m = flat_segments(x, FS, min_s=0.5)
    assert m[100:150].all() and not m[:99].any() and not m[151:].any()


def test_interval_rules():
    import pandas as pd
    t = np.cumsum([0, 0.8, 0.8, 0.8, 0.4, 0.4, 0.8, 0.8, 0.8, 0.8, 2.5, 0.8])
    beats = pd.DataFrame({"sample": (t * FS).astype(int), "t_s": t, "template_corr": 0.99})
    beats.loc[8, "template_corr"] = 0.3
    iv = compute_intervals(beats, None, FS)
    reasons = dict(zip(np.round(iv["ibi_ms"]).astype(int).tolist(), iv["reason"]))
    assert iv.loc[3, "reason"] == "outlier" and iv.loc[4, "reason"] == "outlier"  # extra beat splits interval
    assert reasons[2500] == "range"
    assert iv.loc[7, "reason"] == "morphology" and iv.loc[8, "reason"] == "morphology"
    assert iv.loc[0, "valid"] and iv.loc[1, "valid"]


def test_unreliable_mask_invalidates_intervals():
    raw, _ = synthetic_ppg_signal(np.full(40, 800.0), noise_sd=2)
    mask = np.zeros(raw.size, bool)
    mask[int(10 * FS):int(15 * FS)] = True
    res = process_ppg(ppg_frame(raw), FS, channel="ch0", extra_unreliable=mask)
    iv = res.intervals
    inside = (iv["t_s"] > 10.5) & (iv["t_s"] < 15)
    assert (iv.loc[inside, "reason"] == "unreliable").all()
    assert iv.loc[~inside & (iv["t_s"] > 3) & (iv["t_s"] < 30), "valid"].mean() > 0.8


def test_pure_noise_yields_few_valid_intervals():
    noise = np.random.default_rng(3).normal(0, 1000, int(60 * FS)) + 1e5
    res = process_ppg(ppg_frame(noise), FS, channel="ch0")
    assert res.intervals["valid"].mean() < 0.5
