"""HR, PRV, morphology, accelerometer and inertial features (SYNTHETIC inputs, known answers)."""

import numpy as np
import pandas as pd
import pytest

from phenotyping.features.activity import (
    activity_features, classify_intensity, epoch_summaries, mean_amplitude_deviation,
)
from phenotyping.features.heart_rate import (
    compare_with_device_hr, device_hr_summary, heart_rate_summary, instantaneous_hr_bpm,
)
from phenotyping.features.hrv import pnn, prv_time_domain, rmssd, sdnn, successive_differences
from phenotyping.features.inertial import gyro_features, mag_features
from phenotyping.features.morphology import beat_morphology, morphology_summary
from phenotyping.processing.accelerometer import (
    dominant_frequency, enmo, gravity_calibration_check, motion_mask, vector_magnitude,
)


def iv_frame(ibis, valid=None):
    ibis = np.asarray(ibis, float)
    return pd.DataFrame({"t_s": np.cumsum(ibis) / 1000, "ibi_ms": ibis,
                         "valid": np.ones(ibis.size, bool) if valid is None else np.asarray(valid, bool)})


# ---------------- heart rate ----------------
def test_instantaneous_hr():
    assert instantaneous_hr_bpm(np.array([1000.0, 500.0, 0.0])).tolist()[:2] == [60.0, 120.0]
    assert np.isnan(instantaneous_hr_bpm(np.array([0.0]))[0])


def test_heart_rate_summary_known_values():
    ibis = [1000, 800, 1000, 800, 1000, 800]
    hr = heart_rate_summary(iv_frame(ibis), window_ppg_s=5.4)
    assert hr["hr_mean_bpm"] == pytest.approx(60000 / 900)
    assert hr["hr_min_bpm"] == pytest.approx(60) and hr["hr_max_bpm"] == pytest.approx(75)
    assert hr["ibi_mean_ms"] == pytest.approx(900)
    assert hr["hr_status"] == "ok"


def test_heart_rate_excludes_invalid_and_reports_low_coverage():
    ibis = [800] * 10
    valid = [True] * 5 + [False] * 5
    hr = heart_rate_summary(iv_frame(ibis, valid), window_ppg_s=10.0)
    assert hr["n_intervals_valid"] == 5 and hr["valid_coverage"] == pytest.approx(0.4)
    assert hr["hr_status"] == "low_coverage" and hr["hr_mean_bpm"] == pytest.approx(75)


def test_heart_rate_insufficient_data_returns_nan_with_reason():
    hr = heart_rate_summary(iv_frame([800, 800]), window_ppg_s=60)
    assert np.isnan(hr["hr_mean_bpm"]) and hr["hr_status"].startswith("insufficient_valid_intervals")
    hr = heart_rate_summary(iv_frame([800] * 6), window_ppg_s=60)  # 4.8 s of 60 s
    assert np.isnan(hr["hr_mean_bpm"]) and hr["hr_status"].startswith("insufficient_coverage")
    assert heart_rate_summary(iv_frame([]), 0)["hr_status"] == "no_ppg_in_window"


def test_device_hr_ignores_zero():
    d = device_hr_summary(pd.DataFrame({"hr_bpm": [0, 70, 80]}))
    assert d["device_hr_mean_bpm"] == 75 and d["device_hr_n"] == 2
    assert device_hr_summary(pd.DataFrame({"hr_bpm": [0, 0]}))["device_hr_status"] == "no_valid_device_hr"


def test_compare_with_device_hr():
    t = pd.Timestamp("2026-01-01", tz="UTC") + pd.to_timedelta(np.arange(10), unit="s")
    iv = pd.DataFrame({"time_utc": t, "valid": True, "instantaneous_hr_bpm": 70.0 + np.arange(10)})
    dev = pd.DataFrame({"time": t, "hr_bpm": 65.0 + np.arange(10)})
    c = compare_with_device_hr(iv, dev)
    assert c["n_matched"] == 10 and c["mean_diff_bpm"] == pytest.approx(5) and c["corr"] == pytest.approx(1)


# ---------------- PRV ----------------
def test_prv_primitives():
    ibis = np.array([800, 830, 800, 830, 800.0])
    d = successive_differences(ibis, np.ones(5, bool))
    assert rmssd(d) == pytest.approx(30.0)
    assert sdnn(ibis) == pytest.approx(np.std(ibis, ddof=1))
    assert pnn(d, 20) == 100.0 and pnn(d, 50) == 0.0


def test_successive_differences_skip_invalid_pairs():
    ibis = np.array([800, 830, 2000, 800, 830.0])
    d = successive_differences(ibis, np.array([True, True, False, True, True]))
    assert d.tolist() == [30.0, 30.0]


def test_prv_full_window_ok():
    ibis = np.tile([785.0, 815.0], 50)  # 80 s
    p = prv_time_domain(iv_frame(ibis))
    assert p["prv_status"] == "ok"
    assert p["prv_rmssd_ms"] == pytest.approx(30.0) and p["prv_sdnn_ms"] == pytest.approx(15.08, abs=0.01)
    assert p["prv_pnn20_pct"] == 100.0 and p["prv_pnn50_pct"] == 0.0


def test_prv_ultra_short_window_gives_rmssd_only():
    p = prv_time_domain(iv_frame(np.tile([785.0, 815.0], 20)))  # 32 s (< 50 s)
    assert p["prv_rmssd_ms"] == pytest.approx(30.0)
    assert np.isnan(p["prv_sdnn_ms"]) and np.isnan(p["prv_pnn50_pct"])
    assert p["prv_status"].startswith("ok_ultra_short")


def test_prv_too_short_returns_nan_with_reason():
    p = prv_time_domain(iv_frame([800.0] * 8))
    assert np.isnan(p["prv_rmssd_ms"]) and "rmssd:insufficient" in p["prv_status"]
    assert prv_time_domain(iv_frame([]))["prv_status"] == "no_intervals"


# ---------------- morphology ----------------
def test_beat_morphology_amplitude_and_timing():
    fs = 50.0
    t = np.arange(0, 10, 1 / fs)
    x = np.zeros_like(t)
    peaks = []
    for b in np.arange(1, 9):
        x += 100 * np.exp(-0.5 * ((t - b) / 0.08) ** 2)
        peaks.append(int(b * fs))
    m = beat_morphology(x, fs, np.array(peaks))
    assert m["pulse_amplitude_au"].iloc[1:].to_numpy() == pytest.approx(100, abs=1)
    assert (m["foot_to_peak_ms"].iloc[1:] > 200).all()
    s = morphology_summary(m)
    assert s["morph_status"] == "experimental" and s["morph_n_beats"] >= 5
    assert morphology_summary(m.iloc[:2])["morph_status"].startswith("insufficient")


# ---------------- accelerometer ----------------
def test_vector_magnitude_and_enmo():
    m = vector_magnitude(np.array([0, 600]), np.array([0, 0]), np.array([1000, 800]))
    assert m.tolist() == [1000.0, 1000.0]
    assert enmo(np.array([900.0, 1000.0, 1250.0])).tolist() == [0.0, 0.0, 250.0]


def test_gravity_check():
    fs = 50
    still = np.full(500, 1000.0) + np.random.default_rng(0).normal(0, 2, 500)
    assert gravity_calibration_check(still, fs)["ok"] is True
    assert gravity_calibration_check(still + 200, fs)["ok"] is False
    noisy = np.random.default_rng(0).normal(1000, 100, 500)
    assert gravity_calibration_check(noisy, fs)["ok"] is None


def test_motion_mask_detects_burst_only():
    fs = 52
    x = np.zeros(52 * 20)
    x[52 * 10 : 52 * 12] += 200 * np.sin(np.arange(104))  # perpendicular to gravity
    mask = motion_mask(x, np.zeros_like(x), np.full_like(x, 1000.0), fs)
    assert mask[52 * 10 + 10 : 52 * 12 - 10].all()
    assert not mask[: 52 * 8].any() and not mask[52 * 14 :].any()


def test_dominant_frequency():
    fs = 52.0
    t = np.arange(0, 20, 1 / fs)
    f, _ = dominant_frequency(1000 + 200 * np.sin(2 * np.pi * 2.0 * t), fs)
    assert f == pytest.approx(2.0, abs=0.1)
    f_still, _ = dominant_frequency(np.full(t.size, 1000.0), fs)
    assert np.isnan(f_still)


def test_intensity_classification_and_mad():
    assert [classify_intensity(v) for v in (10, 50, 150, 500, np.nan)] == [
        "sedentary", "light", "moderate", "vigorous", "unknown"]
    assert mean_amplitude_deviation(np.array([990.0, 1010.0])) == 10.0


def _acc_frame(x, fs=52.0):
    t = pd.Timestamp("2026-01-01", tz="UTC") + pd.to_timedelta(np.arange(len(x)) / fs, unit="s")
    df = pd.DataFrame({"time": t, "x_mg": x, "y_mg": 0.0, "z_mg": 1000.0})
    df["magnitude_mg"] = vector_magnitude(df["x_mg"], df["y_mg"], df["z_mg"])
    df["enmo_mg"] = enmo(df["magnitude_mg"])
    return df


def test_activity_features_rest_and_short():
    a = activity_features(_acc_frame(np.zeros(52 * 30)), 52.0)
    assert a["acc_enmo_mean_mg"] == 0 and a["activity_level"] == "sedentary"
    assert np.isnan(a["acc_dominant_freq_hz"])
    short = activity_features(_acc_frame(np.zeros(52)), 52.0)
    assert np.isnan(short["acc_enmo_mean_mg"]) and short["acc_status"].startswith("insufficient")


def test_epoch_summaries():
    e = epoch_summaries(_acc_frame(np.zeros(52 * 12)), 52.0, epoch_s=5)
    assert len(e) == 3 and e["partial"].tolist() == [False, False, True]


# ---------------- gyro / mag ----------------
def test_gyro_and_mag_features():
    n = 52 * 10
    g = pd.DataFrame({"x_dps": np.full(n, 3.0), "y_dps": 4.0, "z_dps": 0.0})
    gf = gyro_features(g, 52.0)
    assert gf["gyro_speed_mean_dps"] == pytest.approx(5.0) and gf["gyro_total_rotation_deg"] == pytest.approx(50.0)
    m = pd.DataFrame({"x_gauss": np.full(n, 0.3), "y_gauss": 0.4, "z_gauss": 0.0})
    assert mag_features(m, 52.0)["mag_status"] == "ok"
    m2 = m * 2
    assert mag_features(m2, 52.0)["mag_status"].startswith("uncalibrated")
    assert gyro_features(g.iloc[:10], 52.0)["gyro_status"].startswith("insufficient")


def test_principal_movement_signal_keeps_true_frequency():
    from phenotyping.processing.accelerometer import principal_movement_signal
    fs = 52.0
    t = np.arange(0, 20, 1 / fs)
    x = 300 * np.sin(2 * np.pi * 2.0 * t)  # perpendicular to gravity
    z = np.full_like(t, 1000.0)
    f_mag, _ = dominant_frequency(vector_magnitude(x, 0 * t, z), fs)
    f_pc, _ = dominant_frequency(principal_movement_signal(x, 0 * t, z), fs)
    assert f_mag == pytest.approx(4.0, abs=0.1)  # |a| doubles the frequency
    assert f_pc == pytest.approx(2.0, abs=0.1)
