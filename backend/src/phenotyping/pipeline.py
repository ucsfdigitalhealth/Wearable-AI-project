"""End-to-end processing of one Polar Verity Sense recording directory.

Steps: load streams -> check overlap -> ACC processing (+ motion mask) ->
PPG processing (beats, intervals, quality) -> per-window features ->
features.csv, per-beat and per-epoch CSVs, plots, metadata.json.

Every feature group has a ``*_status`` column. A NaN value always has a
status explaining why. Nothing is imputed for missing streams.
"""

from __future__ import annotations

import hashlib
import json
import platform
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from phenotyping import __version__
from phenotyping.features.activity import DEFAULT_INTENSITY_CUTPOINTS_MG, activity_features, epoch_summaries
from phenotyping.features.heart_rate import (compare_with_device_hr, device_hr_summary, heart_rate_summary,
                                             instantaneous_hr_bpm)
from phenotyping.features.hrv import prv_time_domain
from phenotyping.features.inertial import gyro_features, mag_features
from phenotyping.features.morphology import beat_morphology, morphology_summary
from phenotyping.ingestion.loaders import Recording, compute_overlap, load_recording
from phenotyping.processing import accelerometer as accp
from phenotyping.processing.ppg import PPGResult, process_ppg


@dataclass
class PipelineConfig:
    """All tunable processing parameters (written to metadata.json)."""

    window_s: float = 60.0
    epoch_s: float = 5.0
    gap_factor: float = 1.5
    # PPG
    ppg_channel: str = "auto"
    ppg_invert: bool = True
    ppg_band_hz: tuple[float, float] = (0.5, 4.0)
    ppg_morph_band_hz: tuple[float, float] = (0.5, 8.0)
    ppg_filter_order: int = 2
    min_hr_bpm: float = 30.0
    max_hr_bpm: float = 200.0
    beat_rel_prominence: float = 0.35
    jump_threshold_mad: float = 12.0
    jump_pad_s: float = 1.0
    max_interval_rel_deviation: float = 0.20
    min_template_corr: float = 0.80
    use_acc_motion_mask: bool = True
    # HR / PRV
    hr_min_valid_intervals: int = 5
    hr_min_valid_coverage: float = 0.25
    hr_good_coverage: float = 0.5
    prv_min_rmssd_valid_s: float = 20.0
    prv_min_successive_pairs: int = 10
    prv_min_sdnn_valid_s: float = 50.0
    morph_min_beats: int = 5
    # ACC
    motion_window_s: float = 1.0
    motion_threshold_mg: float = 40.0
    motion_pad_s: float = 0.5
    min_movement_power_mg2: float = 25.0
    intensity_cutpoints_mg: dict[str, float] = field(default_factory=lambda: dict(DEFAULT_INTENSITY_CUTPOINTS_MG))
    min_stream_coverage_s: float = 5.0
    # Output
    make_plots: bool = True

    @classmethod
    def from_json(cls, path: str | Path) -> "PipelineConfig":
        """Load overrides from a JSON file of ``{parameter: value}``."""
        data = json.loads(Path(path).read_text())
        unknown = set(data) - set(cls.__dataclass_fields__)
        if unknown:
            raise ValueError(f"Unknown config parameter(s): {sorted(unknown)}")
        for k in ("ppg_band_hz", "ppg_morph_band_hz"):
            if k in data:
                data[k] = tuple(data[k])
        return cls(**data)


@dataclass
class PipelineResult:
    features: pd.DataFrame
    intervals: pd.DataFrame | None
    epochs: pd.DataFrame | None
    metadata: dict
    output_dir: Path
    ppg: PPGResult | None = None


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _round_numeric(df: pd.DataFrame, nd: int = 3) -> pd.DataFrame:
    out = df.copy()
    cols = out.select_dtypes("float").columns
    out[cols] = out[cols].round(nd)
    return out


def _slice(df: pd.DataFrame, start: pd.Timestamp, end: pd.Timestamp) -> pd.DataFrame:
    t = df["time"]
    return df.loc[(t >= start) & (t < end)]


def _json_default(o):
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return None if not np.isfinite(o) else float(o)
    if isinstance(o, (np.bool_,)):
        return bool(o)
    if isinstance(o, (pd.Timestamp, datetime)):
        return o.isoformat()
    if isinstance(o, Path):
        return str(o)
    if isinstance(o, tuple):
        return list(o)
    raise TypeError(f"Not JSON serialisable: {type(o)}")


def _clean_nan(obj):
    """Replace float NaN with None recursively so metadata.json is valid JSON."""
    if isinstance(obj, dict):
        return {k: _clean_nan(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_clean_nan(v) for v in obj]
    if isinstance(obj, float) and not np.isfinite(obj):
        return None
    return obj


def run_pipeline(input_dir: str | Path, output_dir: str | Path, config: PipelineConfig | None = None,
                 recording_id: str | None = None) -> PipelineResult:
    """Process one recording directory and write all outputs to ``output_dir``."""
    cfg = config or PipelineConfig()
    input_dir, output_dir = Path(input_dir), Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    hashes_before = {p.name: _sha256(p) for p in sorted(input_dir.glob("*.csv"))}

    rec: Recording = load_recording(input_dir, recording_id, gap_factor=cfg.gap_factor)
    streams = rec.streams
    warnings: list[str] = list(rec.warnings)
    for s in streams.values():
        warnings += [f"[{s.name}] {w}" for w in s.warnings]
    overlap = compute_overlap(streams)
    t0 = rec.start

    # ---------------- ACC ----------------
    acc = acc_motion = None
    acc_fs = None
    calib = None
    if "acc" in streams:
        acc_fs = streams["acc"].sampling.fs_hz
        acc = accp.add_derived_columns(streams["acc"].data)
        acc_motion = accp.motion_mask(acc["x_mg"], acc["y_mg"], acc["z_mg"], acc_fs, cfg.motion_window_s,
                                      cfg.motion_threshold_mg, cfg.motion_pad_s)
        calib = accp.gravity_calibration_check(acc["magnitude_mg"].to_numpy(), acc_fs)
        if calib["ok"] is False:
            warnings.append(f"[acc] {calib['message']}")

    # ---------------- PPG ----------------
    ppg_res: PPGResult | None = None
    intervals_out = None
    beat_morph = None
    ppg_motion = None
    if "ppg" in streams:
        ppg = streams["ppg"]
        extra = None
        if acc is not None and cfg.use_acc_motion_mask:
            # Map ACC motion onto PPG samples via the shared sensor clock.
            # PPG samples outside ACC coverage get no motion information (False).
            acc_ns = acc["sensor_ns"].to_numpy()
            ppg_ns = ppg.data["sensor_ns"].to_numpy()
            idx = np.clip(np.searchsorted(acc_ns, ppg_ns), 0, len(acc_ns) - 1)
            inside = (ppg_ns >= acc_ns[0]) & (ppg_ns <= acc_ns[-1])
            ppg_motion = acc_motion[idx] & inside
            extra = ppg_motion
        ppg_res = process_ppg(
            ppg.data, ppg.sampling.fs_hz, channel=cfg.ppg_channel, invert=cfg.ppg_invert,
            band_hz=cfg.ppg_band_hz, morph_band_hz=cfg.ppg_morph_band_hz, filter_order=cfg.ppg_filter_order,
            max_hr_bpm=cfg.max_hr_bpm, min_hr_bpm=cfg.min_hr_bpm, rel_prominence=cfg.beat_rel_prominence,
            jump_threshold=cfg.jump_threshold_mad, jump_pad_s=cfg.jump_pad_s, extra_unreliable=extra,
            max_rel_deviation=cfg.max_interval_rel_deviation, min_template_corr=cfg.min_template_corr,
        )
        if ppg_res.jumps:
            warnings.append(f"[ppg] {len(ppg_res.jumps)} abrupt discontinuity(ies) detected; surrounding samples excluded.")
        ppg_start = ppg.start
        iv = ppg_res.intervals.copy()
        iv.insert(0, "time_utc", ppg_start + pd.to_timedelta(iv["t_s"], unit="s"))
        iv["instantaneous_hr_bpm"] = instantaneous_hr_bpm(iv["ibi_ms"])
        iv = iv.rename(columns={"t_s": "t_since_ppg_start_s"})
        intervals_out = iv
        beat_morph = beat_morphology(ppg_res.morph, ppg_res.fs_hz, ppg_res.beats["sample"].to_numpy(int))
        beat_morph["time_utc"] = ppg_start + pd.to_timedelta(ppg_res.beats["t_s"].to_numpy(), unit="s")
        # A beat is usable for morphology if it closes a valid interval.
        valid_close = np.zeros(len(beat_morph), bool)
        valid_close[1:] = ppg_res.intervals["valid"].to_numpy(bool)
        beat_morph["valid"] = valid_close

    # ---------------- Windows ----------------
    total_s = (rec.end - t0).total_seconds()
    n_win = max(1, int(np.ceil(total_s / cfg.window_s - 1e-9)))
    rows = []
    for k in range(n_win):
        ws = t0 + pd.Timedelta(seconds=k * cfg.window_s)
        we = ws + pd.Timedelta(seconds=cfg.window_s)
        row: dict = {"window_start_utc": ws.isoformat(), "window_end_utc": we.isoformat(), "window_length_s": cfg.window_s}
        for name in ("ppg", "acc", "gyro", "mag", "hr"):
            if name in streams:
                sl = _slice(streams[name].data, ws, we)
                row[f"{name}_coverage_s"] = round(len(sl) / streams[name].sampling.fs_hz, 2)
            else:
                row[f"{name}_coverage_s"] = 0.0

        # PPG / HR / PRV / morphology
        if ppg_res is not None:
            p = streams["ppg"]
            sl_idx = np.flatnonzero(((p.data["time"] >= ws) & (p.data["time"] < we)).to_numpy())
            ppg_secs = len(sl_idx) / p.sampling.fs_hz
            iv_w = intervals_out[(intervals_out["time_utc"] >= ws) & (intervals_out["time_utc"] < we)]
            hr = heart_rate_summary(iv_w, ppg_secs, cfg.hr_min_valid_intervals, cfg.hr_min_valid_coverage,
                                    cfg.hr_good_coverage)
            prv = prv_time_domain(iv_w, cfg.prv_min_rmssd_valid_s, cfg.prv_min_successive_pairs, cfg.prv_min_sdnn_valid_s)
            bm_w = beat_morph[(beat_morph["time_utc"] >= ws) & (beat_morph["time_utc"] < we) & beat_morph["valid"]]
            morph = morphology_summary(bm_w, cfg.morph_min_beats)
            beats_w = ppg_res.beats[(ppg_res.beats["sample"] >= (sl_idx[0] if len(sl_idx) else 0)) &
                                    (ppg_res.beats["sample"] <= (sl_idx[-1] if len(sl_idx) else -1))]
            valid_frac = hr["n_intervals_valid"] / hr["n_intervals"] if hr["n_intervals"] else np.nan
            tc = float(np.nanmedian(beats_w["template_corr"])) if len(beats_w) and beats_w["template_corr"].notna().any() else np.nan
            if not np.isfinite(valid_frac):
                label = "no_beats"
            elif valid_frac >= 0.7 and tc >= 0.9:
                label = "good"
            elif valid_frac >= 0.4:
                label = "fair"
            else:
                label = "poor"
            row.update({
                "ppg_channel": ppg_res.channel,
                "ppg_valid_interval_fraction": valid_frac,
                "ppg_median_template_corr": tc,
                "ppg_unreliable_fraction": float(ppg_res.unreliable[sl_idx].mean()) if len(sl_idx) else np.nan,
                "ppg_motion_fraction": float(ppg_motion[sl_idx].mean()) if ppg_motion is not None and len(sl_idx) else np.nan,
                "ppg_quality": label,
            })
            row.update(hr)
            row.update(prv)
            row.update(morph)
        else:
            row.update({"ppg_quality": "stream_missing", "hr_status": "stream_missing", "prv_status": "stream_missing",
                        "morph_status": "stream_missing"})

        # Device HR
        if "hr" in streams:
            row.update(device_hr_summary(_slice(streams["hr"].data, ws, we)))
        else:
            row["device_hr_status"] = "stream_missing"

        # ACC
        if acc is not None:
            m = ((acc["time"] >= ws) & (acc["time"] < we)).to_numpy()
            row.update(activity_features(acc.loc[m], acc_fs, acc_motion[m], cfg.min_stream_coverage_s,
                                         cfg.intensity_cutpoints_mg, cfg.min_movement_power_mg2))
        else:
            row.update({"activity_level": "unknown", "acc_status": "stream_missing"})

        # GYRO / MAG
        if "gyro" in streams:
            row.update(gyro_features(_slice(streams["gyro"].data, ws, we), streams["gyro"].sampling.fs_hz,
                                     cfg.min_stream_coverage_s))
        else:
            row["gyro_status"] = "stream_missing"
        if "mag" in streams:
            row.update(mag_features(_slice(streams["mag"].data, ws, we), streams["mag"].sampling.fs_hz,
                                    cfg.min_stream_coverage_s))
        else:
            row["mag_status"] = "stream_missing"
        rows.append(row)

    features = pd.DataFrame(rows)
    float_cols = features.select_dtypes("float").columns
    features[float_cols] = features[float_cols].round(4)
    features.to_csv(output_dir / "features.csv", index=False)

    epochs = None
    if acc is not None:
        epochs = epoch_summaries(acc, acc_fs, cfg.epoch_s, t0=t0, cutpoints=cfg.intensity_cutpoints_mg)
        _round_numeric(epochs).to_csv(output_dir / "activity_epochs.csv", index=False)
    if intervals_out is not None:
        out_iv = intervals_out.copy()
        out_iv["template_corr_closing_beat"] = ppg_res.beats["template_corr"].to_numpy()[1:]
        out_iv["pulse_amplitude_au"] = beat_morph["pulse_amplitude_au"].to_numpy()[1:]
        out_iv["foot_to_peak_ms"] = beat_morph["foot_to_peak_ms"].to_numpy()[1:]
        _round_numeric(out_iv).to_csv(output_dir / "ppg_intervals.csv", index=False)

    plots: list[str] = []
    if cfg.make_plots:
        from phenotyping.visualization import plots as vis
        plots = vis.make_all_plots(rec, ppg_res, acc, acc_motion, intervals_out, epochs, output_dir / "plots")

    # ---------------- Metadata ----------------
    extracted, skipped = _feature_inventory(features, streams, rec.missing_streams)
    hashes_after = {p.name: _sha256(p) for p in sorted(input_dir.glob("*.csv"))}
    if hashes_after != hashes_before:
        warnings.append("Input files changed during processing (hash mismatch)!")
    metadata = {
        "recording_id": rec.recording_id,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "software": {"phenotyping": __version__, "python": platform.python_version(),
                     "numpy": np.__version__, "pandas": pd.__version__},
        "input_directory": str(input_dir),
        "input_files": {s.name: {"file": s.source_path.name, "sha256": hashes_before.get(s.source_path.name),
                                 "rows": len(s.data), "raw_columns": s.raw_columns} for s in streams.values()},
        "streams_processed": sorted(streams),
        "streams_missing": rec.missing_streams,
        "recording_start_utc": rec.start.isoformat(),
        "recording_end_utc": rec.end.isoformat(),
        "recording_duration_s": round(total_s, 3),
        "streams": {
            s.name: {"start_utc": s.start.isoformat(), "end_utc": s.end.isoformat(), "duration_s": round(s.duration_s, 3),
                     "sampling_rate_hz": round(s.sampling.fs_hz, 4), "median_dt_ms": round(s.sampling.median_dt_ms, 4),
                     "max_dt_ms": round(s.sampling.max_dt_ms, 4), "n_gaps": s.sampling.n_gaps, "units": s.units,
                     "phone_minus_sensor_ms": s.phone_sensor_offset_ms}
            for s in streams.values()
        },
        "time_reference": "sensor timestamp [ns] since 2000-01-01T00:00:00Z (Polar epoch), reported in UTC",
        "overlap": overlap,
        "ppg_processing": None if ppg_res is None else {
            "channel_used": ppg_res.channel, "channel_spectral_snr": ppg_res.channel_snr, "inverted": ppg_res.inverted,
            "n_beats": int(len(ppg_res.beats)), "n_intervals": int(len(ppg_res.intervals)),
            "n_intervals_valid": int(ppg_res.intervals["valid"].sum()) if len(ppg_res.intervals) else 0,
            "interval_rejection_reasons": ppg_res.intervals["reason"][~ppg_res.intervals["valid"]].value_counts().to_dict()
            if len(ppg_res.intervals) else {},
            "n_discontinuities": len(ppg_res.jumps),
            "unreliable_sample_fraction": float(ppg_res.unreliable.mean()),
        },
        "acc_calibration_check": calib,
        "ppg_vs_device_hr": compare_with_device_hr(intervals_out, streams["hr"].data)
        if intervals_out is not None and "hr" in streams else None,
        "config": asdict(cfg),
        "features_extracted": extracted,
        "features_skipped": skipped,
        "data_quality_warnings": warnings,
        "outputs": {"features": "features.csv", "intervals": "ppg_intervals.csv" if intervals_out is not None else None,
                    "epochs": "activity_epochs.csv" if epochs is not None else None, "plots": plots},
        "notes": [
            "PPG-derived values are pulse rate / pulse rate variability (PRV), not ECG heart rate / HRV.",
            "No feature in this output has been validated against a reference device.",
            "Activity intensity labels use wrist-derived ENMO cut-points; provisional for Verity Sense placement.",
        ],
    }
    (output_dir / "metadata.json").write_text(json.dumps(_clean_nan(json.loads(json.dumps(metadata, default=_json_default))), indent=2))
    return PipelineResult(features, intervals_out, epochs, metadata, output_dir, ppg_res)


# Feature groups -> (value columns, status column)
FEATURE_GROUPS = {
    "heart_rate": (["hr_mean_bpm", "hr_median_bpm", "hr_min_bpm", "hr_max_bpm", "ibi_mean_ms"], "hr_status"),
    "prv_rmssd": (["prv_rmssd_ms", "prv_sdsd_ms"], "prv_status"),
    "prv_sdnn_pnn": (["prv_sdnn_ms", "prv_pnn50_pct", "prv_pnn20_pct"], "prv_status"),
    "pulse_morphology": (["pulse_amplitude_au", "pulse_foot_to_peak_ms"], "morph_status"),
    "device_hr": (["device_hr_mean_bpm", "device_hr_min_bpm", "device_hr_max_bpm"], "device_hr_status"),
    "accelerometer": (["acc_magnitude_mean_mg", "acc_enmo_mean_mg", "acc_mad_mg"], "acc_status"),
    "acc_dominant_frequency": (["acc_dominant_freq_hz"], "acc_status"),
    "gyroscope": (["gyro_speed_mean_dps", "gyro_total_rotation_deg"], "gyro_status"),
    "magnetometer_magnitude": (["mag_field_mean_gauss"], "mag_status"),
}


def _feature_inventory(features: pd.DataFrame, streams: dict, missing: list[str]) -> tuple[list[str], dict[str, str]]:
    extracted, skipped = [], {}
    for group, (cols, status_col) in FEATURE_GROUPS.items():
        present = [c for c in cols if c in features and features[c].notna().any()]
        if present:
            extracted.append(group)
        else:
            statuses = features[status_col].dropna().unique().tolist() if status_col in features else ["stream_missing"]
            reason = "; ".join(map(str, statuses))
            if group == "acc_dominant_frequency":
                reason = "too little movement power in every window"
            skipped[group] = reason
    # Features that this recording cannot support at all.
    if "hr" in streams:
        ppi = streams["hr"].data.get("ppi_ms")
        if ppi is None or ppi.notna().sum() == 0:
            skipped["device_ppi_prv"] = "PPI [ms] column is empty in the hr file; PRV computed from raw PPG instead."
        contact = streams["hr"].data.get("contact")
        if contact is not None and not contact.astype(bool).any():
            skipped["skin_contact_flag"] = "contact is false for every sample although a pulse is visible; flag not used."
    skipped["prv_frequency_domain"] = "Needs >= 2-5 min of clean intervals; not implemented in this version."
    skipped["mag_heading_orientation"] = "Magnetometer is uncalibrated; heading not computed."
    skipped["sleep_circadian"] = "Requires multi-hour / multi-day recordings."
    for s in missing:
        skipped[f"{s}_stream"] = "file not present in recording directory"
    return extracted, skipped
