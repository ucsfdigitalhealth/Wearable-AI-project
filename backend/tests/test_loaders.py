"""CSV loading, timestamp parsing, sampling rate and overlap (synthetic files)."""

import numpy as np
import pandas as pd
import pytest
from conftest import T0_NS, make_recording_dir, write_polar_csv

from phenotyping.ingestion.loaders import (
    SensorFileError, compute_overlap, discover_stream_files, estimate_sampling, load_recording, load_stream,
    sensor_ns_to_utc,
)


def test_polar_epoch_conversion_matches_real_row():
    # First row of the real ACC file: phone timestamp 2026-11-27T01:56:26.877
    t = sensor_ns_to_utc(np.array([849059786877283968])).iloc[0]
    assert t == pd.Timestamp("2026-11-27T01:56:26.877283968Z")


def test_estimate_sampling_rate_and_gaps():
    ns = T0_NS + np.round(np.arange(0, 1040) * 1e9 / 52).astype("int64")
    ns[500:] += 2_000_000_000  # insert a 2-s gap
    info = estimate_sampling(ns)
    assert info.fs_hz == pytest.approx(52.0, rel=1e-3)
    assert info.n_gaps == 1
    assert info.gaps[0][1] == pytest.approx(2.0 + 1 / 52, abs=1e-3)


def test_estimate_sampling_needs_two_samples():
    with pytest.raises(SensorFileError):
        estimate_sampling(np.array([1]))


def test_load_acc_canonical_columns_units_and_time(tmp_path):
    ns = T0_NS + np.arange(100) * 19_230_769
    p = write_polar_csv(tmp_path / "acc_20261126_175628.csv", ["X [mg]", "Y [mg]", "Z [mg]"], ns,
                        [np.zeros(100), np.zeros(100), np.full(100, 1000.0)])
    s = load_stream(p)
    assert s.name == "acc"
    assert list(s.data.columns) == ["time", "sensor_ns", "t_s", "x_mg", "y_mg", "z_mg"]
    assert s.units == {"x_mg": "mg", "y_mg": "mg", "z_mg": "mg"}
    assert str(s.data["time"].dt.tz) == "UTC"
    assert s.data["t_s"].iloc[0] == 0
    assert s.sampling.fs_hz == pytest.approx(52.0, rel=1e-3)
    assert abs(s.phone_sensor_offset_ms["median"]) < 1.0
    assert s.warnings == []


def test_missing_values_are_kept_as_nan_and_warned(tmp_path):
    ns = T0_NS + np.arange(50) * 20_000_000
    x = np.zeros(50)
    x[10] = np.nan
    p = write_polar_csv(tmp_path / "mag_20261126_175629.csv", ["X [gauss]", "Y [gauss]", "Z [gauss]"], ns,
                        [x, np.zeros(50), np.zeros(50)])
    s = load_stream(p)
    assert np.isnan(s.data["x_gauss"].iloc[10])
    assert any("missing value" in w for w in s.warnings)


def test_unsorted_and_duplicate_timestamps_are_fixed_with_warning(tmp_path):
    ns = T0_NS + np.arange(20) * 20_000_000
    ns = np.concatenate((ns[:10], ns[12:], ns[10:12], ns[5:6]))  # out of order + duplicate
    p = write_polar_csv(tmp_path / "gyro_20261126_175629.csv", ["X [dps]", "Y [dps]", "Z [dps]"], ns,
                        [np.arange(ns.size, dtype=float), np.zeros(ns.size), np.zeros(ns.size)])
    s = load_stream(p)
    assert s.data["sensor_ns"].is_monotonic_increasing and s.data["sensor_ns"].is_unique
    assert len(s.data) == 20
    assert any("not strictly increasing" in w for w in s.warnings)


def test_empty_optional_column_is_reported(tmp_path):
    ns = T0_NS + np.arange(5) * 1_000_000_000
    p = write_polar_csv(tmp_path / "hr_20261126_175630.csv", ["HR [bpm]", "PPI [ms]", "contact"], ns,
                        [np.full(5, 70.0), np.full(5, np.nan), np.full(5, True)], "{:.0f}")
    s = load_stream(p)
    assert s.data["contact"].all()
    assert any("PPI [ms]" in w and "no values" in w for w in s.warnings)


@pytest.mark.parametrize("content,match", [
    ("", "empty"),
    ("2026-11-27T01:56:26.000;849059786000000000;1;2;3;4;\n", "first two columns"),  # headerless (old demo)
    ("Phone timestamp;sensor timestamp [ns];X [mg];Y [mg]\n2026-11-27T01:56:26.000;849059786000000000;1;2\n",
     "missing required"),
    ("Phone timestamp;sensor timestamp [ns];X [mg];Y [mg];Z [mg]\n", "no data rows"),
    ("Phone timestamp;sensor timestamp [ns];X [mg];Y [mg];Z [mg]\nx;abc;1;2;3\n", "no numeric"),
])
def test_malformed_files_raise_useful_errors(tmp_path, content, match):
    p = tmp_path / "acc_20261126_175628.csv"
    p.write_text(content)
    with pytest.raises(SensorFileError, match=match):
        load_stream(p)


def test_unknown_stream_name_rejected(tmp_path):
    p = tmp_path / "ecg_20261126_175628.csv"
    p.write_text("Phone timestamp;sensor timestamp [ns];ECG [uV]\n")
    with pytest.raises(SensorFileError, match="stream type"):
        load_stream(p)


def test_discover_rejects_mixed_recordings(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=10, streams=("acc",))
    (d / "acc_20261127_090000.csv").write_text((d / "acc_20261126_175628.csv").read_text())
    with pytest.raises(SensorFileError, match="more than one file"):
        discover_stream_files(d)


def test_discover_ignores_other_files_and_errors_when_none(tmp_path):
    (tmp_path / "demo_ppg.txt").write_text("x")
    with pytest.raises(SensorFileError, match="no sensor files"):
        discover_stream_files(tmp_path)


def test_load_recording_reports_missing_streams_and_overlap(tmp_path):
    d, _ = make_recording_dir(tmp_path, duration_s=20, streams=("acc", "ppg"))
    rec = load_recording(d)
    assert set(rec.streams) == {"acc", "ppg"}
    assert set(rec.missing_streams) == {"gyro", "mag", "hr"}
    ov = compute_overlap(rec.streams)
    assert ov["common"]["duration_s"] == pytest.approx(min(s.duration_s for s in rec.streams.values()), abs=0.05)


def test_non_overlapping_streams_detected(tmp_path):
    ns1 = T0_NS + np.arange(50) * 20_000_000
    ns2 = ns1 + 3_600_000_000_000  # one hour later
    a = write_polar_csv(tmp_path / "acc_20261126_175628.csv", ["X [mg]", "Y [mg]", "Z [mg]"], ns1,
                        [np.zeros(50)] * 2 + [np.full(50, 1000.0)])
    g = write_polar_csv(tmp_path / "gyro_20261126_185628.csv", ["X [dps]", "Y [dps]", "Z [dps]"], ns2, [np.zeros(50)] * 3)
    ov = compute_overlap({"acc": load_stream(a), "gyro": load_stream(g)})
    assert ov["common"] is None
    assert ov["pairwise"]["acc|gyro"] == 0.0
    rec = load_recording(tmp_path)
    assert any("do not all overlap" in w for w in rec.warnings)
