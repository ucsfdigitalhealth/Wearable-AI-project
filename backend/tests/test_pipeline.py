"""End-to-end pipeline tests: SYNTHETIC recordings, plus the real recording if present."""

import json

import numpy as np
import pandas as pd
import pytest
from conftest import REAL_RECORDING, make_recording_dir

from phenotyping.pipeline import PipelineConfig, run_pipeline


def test_synthetic_recording_end_to_end(tmp_path):
    d, truth = make_recording_dir(tmp_path, duration_s=150, move_from_s=120)
    out = tmp_path / "out"
    res = run_pipeline(d, out, PipelineConfig(window_s=60))
    f = res.features
    assert (out / "features.csv").exists() and (out / "metadata.json").exists()
    assert len(f) == 3
    # Full, clean windows: HR and PRV recovered.
    w0 = f.iloc[0]
    assert w0["hr_mean_bpm"] == pytest.approx(truth["mean_hr"], abs=0.5)
    assert w0["prv_rmssd_ms"] == pytest.approx(truth["rmssd"], abs=4.0)
    assert np.isfinite(w0["prv_sdnn_ms"])
    assert w0["device_hr_mean_bpm"] == pytest.approx(70)
    assert w0["activity_level"] == "sedentary"
    assert w0["gyro_speed_mean_dps"] == pytest.approx(5.0)
    # Last window: 2 Hz, 300 mg movement starts at 120 s -> detected.
    w2 = f.iloc[2]
    assert w2["acc_dominant_freq_hz"] == pytest.approx(2.0, abs=0.1)
    assert w2["acc_movement_fraction"] > 0.9
    md = json.loads((out / "metadata.json").read_text())
    assert md["streams_missing"] == []
    assert "heart_rate" in md["features_extracted"]
    assert "device_ppi_prv" in md["features_skipped"]
    assert len(md["outputs"]["plots"]) == 5
    assert all((out / "plots" / p).exists() for p in md["outputs"]["plots"])


def test_raw_input_unchanged(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=30)
    before = {p.name: p.read_bytes() for p in d.iterdir()}
    run_pipeline(d, tmp_path / "out", PipelineConfig(make_plots=False))
    assert before == {p.name: p.read_bytes() for p in d.iterdir()}


def test_missing_ppg_stream(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=30, streams=("acc",))
    res = run_pipeline(d, tmp_path / "out", PipelineConfig(make_plots=False))
    r = res.features.iloc[0]
    assert r["hr_status"] == "stream_missing" and r["gyro_status"] == "stream_missing"
    assert "hr_mean_bpm" not in res.features or np.isnan(r["hr_mean_bpm"])
    assert np.isfinite(r["acc_enmo_mean_mg"])
    assert "ppg_stream" in res.metadata["features_skipped"]


def test_missing_acc_stream(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=70, streams=("ppg",))
    res = run_pipeline(d, tmp_path / "out", PipelineConfig(make_plots=True))
    r = res.features.iloc[0]
    assert r["acc_status"] == "stream_missing" and r["activity_level"] == "unknown"
    assert np.isfinite(r["hr_mean_bpm"])
    assert np.isnan(r["ppg_motion_fraction"])


def test_short_recording_reports_insufficient_prv(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=15)
    r = run_pipeline(d, tmp_path / "out", PipelineConfig(make_plots=False)).features.iloc[0]
    assert np.isnan(r["prv_rmssd_ms"]) and "insufficient" in r["prv_status"]
    assert np.isnan(r["prv_sdnn_ms"])


def test_config_from_json(tmp_path):
    p = tmp_path / "cfg.json"
    p.write_text(json.dumps({"window_s": 30, "ppg_band_hz": [0.6, 3.5]}))
    cfg = PipelineConfig.from_json(p)
    assert cfg.window_s == 30 and cfg.ppg_band_hz == (0.6, 3.5)
    p.write_text(json.dumps({"not_a_param": 1}))
    with pytest.raises(ValueError):
        PipelineConfig.from_json(p)


@pytest.mark.skipif(not REAL_RECORDING.is_dir(), reason="real recording not available (not committed to git)")
def test_real_recording_regression(tmp_path):
    """REAL DATA: behaviour checks on recording_001 (not ground truth).

    Checks the pipeline's outputs stay physiologically plausible and that
    limitations are reported, e.g. no PRV claimed from < 20 s of clean beats.
    """
    res = run_pipeline(REAL_RECORDING, tmp_path / "out", PipelineConfig(make_plots=False))
    r = res.features.iloc[0]
    assert len(res.features) == 1
    assert 50 < r["hr_mean_bpm"] < 110
    assert r["ppg_channel"] in ("ch0", "ch1", "ch2")
    assert r["acc_magnitude_mean_mg"] == pytest.approx(1000, abs=10)
    assert r["mag_status"].startswith("uncalibrated")
    md = res.metadata
    assert md["overlap"]["common"]["duration_s"] == pytest.approx(40.82, abs=0.05)
    assert md["ppg_processing"]["inverted"] is True
    assert "device_ppi_prv" in md["features_skipped"]
    if not np.isfinite(r["prv_rmssd_ms"]):
        assert "insufficient" in r["prv_status"]
