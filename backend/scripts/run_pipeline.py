"""Run the phenotyping pipeline on one recording directory.

Example (from backend/):
    python scripts/run_pipeline.py --input data/samples/recording_001 --output results/recording_001
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running without `pip install -e .`
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from phenotyping.ingestion.loaders import SensorFileError  # noqa: E402
from phenotyping.pipeline import PipelineConfig, run_pipeline  # noqa: E402


def _fmt(v, unit="", nd=1):
    try:
        return "NaN" if v != v else f"{v:.{nd}f}{unit}"
    except TypeError:
        return str(v)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, type=Path, help="Directory containing acc_/gyro_/mag_/ppg_/hr_*.csv")
    ap.add_argument("--output", required=True, type=Path, help="Output directory (created if missing)")
    ap.add_argument("--recording-id", default=None, help="Defaults to the input directory name")
    ap.add_argument("--window-s", type=float, default=None, help="Feature window length in seconds (default 60)")
    ap.add_argument("--epoch-s", type=float, default=None, help="Activity epoch length in seconds (default 5)")
    ap.add_argument("--ppg-channel", default=None, help="ch0, ch1, ch2 or auto (default)")
    ap.add_argument("--no-motion-mask", action="store_true", help="Do not use ACC to flag PPG motion artefacts")
    ap.add_argument("--no-plots", action="store_true")
    ap.add_argument("--config", type=Path, default=None, help="JSON file with PipelineConfig overrides")
    args = ap.parse_args(argv)

    cfg = PipelineConfig.from_json(args.config) if args.config else PipelineConfig()
    if args.window_s is not None:
        cfg.window_s = args.window_s
    if args.epoch_s is not None:
        cfg.epoch_s = args.epoch_s
    if args.ppg_channel:
        cfg.ppg_channel = args.ppg_channel
    if args.no_motion_mask:
        cfg.use_acc_motion_mask = False
    if args.no_plots:
        cfg.make_plots = False

    try:
        res = run_pipeline(args.input, args.output, cfg, args.recording_id)
    except SensorFileError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    md = res.metadata
    print(f"Recording {md['recording_id']}: {md['recording_start_utc']} -> {md['recording_end_utc']} "
          f"({md['recording_duration_s']:.1f} s)")
    for name, s in md["streams"].items():
        print(f"  {name:5s} {s['sampling_rate_hz']:7.2f} Hz  {s['duration_s']:7.1f} s  gaps={s['n_gaps']}")
    if md["streams_missing"]:
        print(f"  missing streams: {', '.join(md['streams_missing'])}")
    common = md["overlap"]["common"]
    print(f"  all-stream overlap: {_fmt(common['duration_s'], ' s') if common else 'none'}")
    p = md.get("ppg_processing")
    if p:
        print(f"PPG: channel {p['channel_used']}, {p['n_beats']} beats, {p['n_intervals_valid']}/{p['n_intervals']} "
              f"intervals accepted; rejected: {p['interval_rejection_reasons']}")
    f = res.features
    print(f"\nFeature windows: {len(f)} x {cfg.window_s:g} s")
    for _, r in f.iterrows():
        print(f"  [{r['window_start_utc'][11:19]}] "
              f"HR {_fmt(r.get('hr_mean_bpm'))} bpm ({r.get('hr_status')}), "
              f"RMSSD {_fmt(r.get('prv_rmssd_ms'))} ms, SDNN {_fmt(r.get('prv_sdnn_ms'))} ms, "
              f"device HR {_fmt(r.get('device_hr_mean_bpm'))} bpm, "
              f"ENMO {_fmt(r.get('acc_enmo_mean_mg'))} mg ({r.get('activity_level')}), "
              f"PPG quality {r.get('ppg_quality')}")
    print(f"\nExtracted: {', '.join(md['features_extracted'])}")
    print("Skipped:")
    for k, v in md["features_skipped"].items():
        print(f"  - {k}: {v}")
    if md["data_quality_warnings"]:
        print("Warnings:")
        for w in md["data_quality_warnings"]:
            print(f"  - {w}")
    print(f"\nOutputs written to {res.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
