"""Loaders for Polar Verity Sense CSV exports.

Supported format (established by auditing ``data/samples/recording_001``;
see ``docs/recording_001_audit.md``):

* One file per sensor stream, named ``<stream>_<YYYYMMDD>_<HHMMSS>.csv`` where
  ``<stream>`` is one of ``acc``, ``gyro``, ``mag``, ``ppg``, ``hr``.
* Semicolon separated, one header row.
* Column 1 ``Phone timestamp``: ISO-8601 text, no timezone. In the audited
  recording it equals the sensor timestamp (UTC) to within 1 ms.
* Column 2 ``sensor timestamp [ns]``: integer nanoseconds since
  2000-01-01T00:00:00 UTC (the Polar epoch).
* Remaining columns: sensor values. Units are read from the ``[unit]`` suffix
  of each header; PPG channels have no unit (raw ADC counts).

The raw files are never modified. Values are copied into a canonical
DataFrame with a UTC ``time`` column and snake_case value columns that carry
their unit (e.g. ``x_mg``).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

POLAR_EPOCH = pd.Timestamp("2000-01-01T00:00:00", tz="UTC")

PHONE_TS_COL = "Phone timestamp"
SENSOR_TS_COL = "sensor timestamp [ns]"

FILENAME_RE = re.compile(r"^(?P<stream>acc|gyro|mag|ppg|hr)_(?P<date>\d{8})_(?P<time>\d{6})\.csv$", re.IGNORECASE)


class SensorFileError(ValueError):
    """Raised when a sensor file is malformed or not in a supported format."""


@dataclass(frozen=True)
class ColumnSpec:
    """Expected raw column and the canonical name it is mapped to."""

    raw: str
    canonical: str
    unit: str
    required: bool = True


# Expected columns for every supported stream. Names are matched exactly
# (after stripping whitespace) against the file header.
STREAM_SPECS: dict[str, list[ColumnSpec]] = {
    "acc": [
        ColumnSpec("X [mg]", "x_mg", "mg"),
        ColumnSpec("Y [mg]", "y_mg", "mg"),
        ColumnSpec("Z [mg]", "z_mg", "mg"),
    ],
    "gyro": [
        ColumnSpec("X [dps]", "x_dps", "deg/s"),
        ColumnSpec("Y [dps]", "y_dps", "deg/s"),
        ColumnSpec("Z [dps]", "z_dps", "deg/s"),
    ],
    "mag": [
        ColumnSpec("X [gauss]", "x_gauss", "gauss"),
        ColumnSpec("Y [gauss]", "y_gauss", "gauss"),
        ColumnSpec("Z [gauss]", "z_gauss", "gauss"),
    ],
    "ppg": [
        ColumnSpec("channel 0", "ch0", "adc_counts"),
        ColumnSpec("channel 1", "ch1", "adc_counts"),
        ColumnSpec("channel 2", "ch2", "adc_counts"),
        ColumnSpec("ambient", "ambient", "adc_counts"),
    ],
    "hr": [
        ColumnSpec("HR [bpm]", "hr_bpm", "bpm"),
        ColumnSpec("PPI [ms]", "ppi_ms", "ms", required=False),
        ColumnSpec("contact", "contact", "bool", required=False),
    ],
}


@dataclass
class SamplingInfo:
    """Sampling statistics computed from sensor timestamps.

    Attributes
    ----------
    fs_hz:
        Effective sampling rate, 1 / median sample interval (Hz).
    median_dt_ms, min_dt_ms, max_dt_ms:
        Sample-interval statistics (ms).
    n_gaps:
        Number of intervals longer than ``gap_factor`` x median interval.
    gaps:
        List of ``(start_time_utc_iso, duration_s)`` for each gap.
    """

    fs_hz: float
    median_dt_ms: float
    min_dt_ms: float
    max_dt_ms: float
    n_gaps: int
    gaps: list[tuple[str, float]] = field(default_factory=list)


@dataclass
class SensorStream:
    """One loaded sensor stream.

    ``data`` always contains ``time`` (tz-aware UTC), ``sensor_ns`` (int64,
    ns since Polar epoch), ``t_s`` (float seconds since the stream's first
    sample) and the canonical value columns listed in ``units``.
    """

    name: str
    source_path: Path
    data: pd.DataFrame
    units: dict[str, str]
    raw_columns: list[str]
    sampling: SamplingInfo
    phone_sensor_offset_ms: dict[str, float]
    warnings: list[str] = field(default_factory=list)

    @property
    def start(self) -> pd.Timestamp:
        return self.data["time"].iloc[0]

    @property
    def end(self) -> pd.Timestamp:
        return self.data["time"].iloc[-1]

    @property
    def duration_s(self) -> float:
        return float((self.data["sensor_ns"].iloc[-1] - self.data["sensor_ns"].iloc[0]) / 1e9)


@dataclass
class Recording:
    """All sensor streams found in one recording directory."""

    recording_id: str
    directory: Path
    streams: dict[str, SensorStream]
    missing_streams: list[str]
    warnings: list[str] = field(default_factory=list)

    @property
    def start(self) -> pd.Timestamp:
        return min(s.start for s in self.streams.values())

    @property
    def end(self) -> pd.Timestamp:
        return max(s.end for s in self.streams.values())


def sensor_ns_to_utc(sensor_ns: np.ndarray | pd.Series) -> pd.Series:
    """Convert Polar sensor timestamps to tz-aware UTC datetimes.

    Parameters
    ----------
    sensor_ns:
        Integer nanoseconds since 2000-01-01T00:00:00 UTC.

    Returns
    -------
    pandas.Series of ``datetime64[ns, UTC]``.
    """
    ns = pd.Series(np.asarray(sensor_ns, dtype="int64"))
    return POLAR_EPOCH + pd.to_timedelta(ns, unit="ns")


def estimate_sampling(sensor_ns: np.ndarray, gap_factor: float = 1.5) -> SamplingInfo:
    """Estimate sampling rate and detect gaps from sensor timestamps.

    Parameters
    ----------
    sensor_ns:
        Strictly increasing integer timestamps (ns).
    gap_factor:
        An interval longer than ``gap_factor`` x the median interval is a gap.

    Returns
    -------
    SamplingInfo. Raises ``SensorFileError`` if fewer than 2 samples.
    """
    ns = np.asarray(sensor_ns, dtype="int64")
    if ns.size < 2:
        raise SensorFileError("At least two samples are needed to estimate the sampling rate.")
    dt = np.diff(ns).astype(float)
    med = float(np.median(dt))
    if med <= 0:
        raise SensorFileError("Median sample interval is not positive; timestamps are invalid.")
    gap_idx = np.flatnonzero(dt > gap_factor * med)
    gaps = [
        (sensor_ns_to_utc(ns[i : i + 1]).iloc[0].isoformat(), float(dt[i] / 1e9))
        for i in gap_idx
    ]
    return SamplingInfo(
        fs_hz=1e9 / med,
        median_dt_ms=med / 1e6,
        min_dt_ms=float(dt.min() / 1e6),
        max_dt_ms=float(dt.max() / 1e6),
        n_gaps=int(gap_idx.size),
        gaps=gaps,
    )


def parse_stream_name(path: Path) -> str | None:
    """Return the stream type encoded in a Polar export filename, or None."""
    m = FILENAME_RE.match(path.name)
    return m.group("stream").lower() if m else None


def _read_header(path: Path) -> list[str]:
    with open(path, encoding="utf-8-sig") as fh:
        first = fh.readline().strip()
    if not first:
        raise SensorFileError(f"{path.name}: file is empty.")
    return [c.strip() for c in first.rstrip(";").split(";")]


def load_stream(path: str | Path, stream: str | None = None, gap_factor: float = 1.5) -> SensorStream:
    """Load one Polar sensor CSV into a canonical ``SensorStream``.

    Parameters
    ----------
    path:
        Path to the CSV file. The file is only read, never modified.
    stream:
        Stream type (``acc``, ``gyro``, ``mag``, ``ppg``, ``hr``). If omitted it
        is taken from the filename.
    gap_factor:
        Passed to :func:`estimate_sampling`.

    Raises
    ------
    SensorFileError
        For missing/renamed columns, a missing header, non-numeric values,
        unknown stream type or too few samples.
    """
    path = Path(path)
    if not path.is_file():
        raise SensorFileError(f"{path}: file not found.")
    stream = (stream or parse_stream_name(path) or "").lower()
    if stream not in STREAM_SPECS:
        raise SensorFileError(
            f"{path.name}: cannot determine stream type. Expected a filename like "
            f"'ppg_20261126_175627.csv' with one of {sorted(STREAM_SPECS)}."
        )

    header = _read_header(path)
    if header[:2] != [PHONE_TS_COL, SENSOR_TS_COL]:
        raise SensorFileError(
            f"{path.name}: first two columns must be '{PHONE_TS_COL}' and '{SENSOR_TS_COL}', "
            f"got {header[:2]}. Headerless files (e.g. the old demo_ppg.txt) are not supported."
        )
    specs = STREAM_SPECS[stream]
    missing = [s.raw for s in specs if s.required and s.raw not in header]
    if missing:
        raise SensorFileError(f"{path.name}: missing required {stream} column(s) {missing}; header is {header}.")

    raw = pd.read_csv(path, sep=";", encoding="utf-8-sig", dtype={PHONE_TS_COL: str})
    raw.columns = [str(c).strip() for c in raw.columns]
    raw = raw.loc[:, [c for c in raw.columns if not c.startswith("Unnamed")]]
    warnings: list[str] = []
    if raw.empty:
        raise SensorFileError(f"{path.name}: no data rows.")

    # --- timestamps -------------------------------------------------------
    sensor_ns = pd.to_numeric(raw[SENSOR_TS_COL], errors="coerce")
    bad_ts = sensor_ns.isna()
    if bad_ts.all():
        raise SensorFileError(f"{path.name}: '{SENSOR_TS_COL}' contains no numeric values.")
    if bad_ts.any():
        warnings.append(f"{int(bad_ts.sum())} row(s) with missing/invalid sensor timestamp dropped.")
        raw = raw.loc[~bad_ts]
        sensor_ns = sensor_ns.loc[~bad_ts]
    sensor_ns = sensor_ns.astype("int64")

    out = pd.DataFrame({"sensor_ns": sensor_ns.to_numpy()})
    units: dict[str, str] = {}
    for spec in specs:
        if spec.raw not in raw.columns:
            warnings.append(f"Optional column '{spec.raw}' not present.")
            continue
        col = raw[spec.raw]
        if spec.unit == "bool":
            vals = col.astype(str).str.strip().str.lower().map({"true": True, "false": False})
            out[spec.canonical] = vals.to_numpy()
        else:
            vals = pd.to_numeric(col, errors="coerce")
            n_bad = int(vals.isna().sum() - col.isna().sum())
            if n_bad:
                warnings.append(f"Column '{spec.raw}': {n_bad} non-numeric value(s) set to NaN.")
            out[spec.canonical] = vals.to_numpy(dtype=float)
            n_nan = int(np.isnan(out[spec.canonical]).sum())
            if n_nan == len(out):
                warnings.append(f"Column '{spec.raw}' is present but contains no values.")
            elif n_nan and spec.required:
                warnings.append(f"Column '{spec.raw}': {n_nan} missing value(s) (left as NaN, not imputed).")
        units[spec.canonical] = spec.unit

    phone = pd.to_datetime(raw[PHONE_TS_COL].to_numpy(), errors="coerce", format="ISO8601")

    # Ordering / duplicates
    order_ok = bool(np.all(np.diff(out["sensor_ns"].to_numpy()) > 0))
    if not order_ok:
        n_before = len(out)
        out["_phone"] = phone
        out = out.sort_values("sensor_ns", kind="stable").drop_duplicates("sensor_ns", keep="first")
        phone = pd.DatetimeIndex(out.pop("_phone"))
        warnings.append(
            f"Timestamps were not strictly increasing; rows sorted and {n_before - len(out)} duplicate(s) dropped."
        )
    out = out.reset_index(drop=True)
    if len(out) < 2:
        raise SensorFileError(f"{path.name}: fewer than two valid samples.")

    out.insert(0, "time", sensor_ns_to_utc(out["sensor_ns"]).to_numpy())
    out["time"] = pd.to_datetime(out["time"], utc=True)
    out.insert(2, "t_s", (out["sensor_ns"] - out["sensor_ns"].iloc[0]) / 1e9)

    # Phone vs sensor clock (phone column has no timezone; compare as UTC).
    phone_utc = pd.Series(phone).dt.tz_localize("UTC") if getattr(phone, "tz", None) is None else pd.Series(phone)
    offset_ms = (phone_utc.reset_index(drop=True) - out["time"]).dt.total_seconds() * 1000
    offset = {
        "median": float(np.nanmedian(offset_ms)),
        "min": float(np.nanmin(offset_ms)),
        "max": float(np.nanmax(offset_ms)),
    }
    if abs(offset["median"]) > 1000:
        warnings.append(
            f"Phone timestamp differs from sensor timestamp by {offset['median'] / 1000:.1f} s (median). "
            "Sensor timestamps are used as the reference clock."
        )

    sampling = estimate_sampling(out["sensor_ns"].to_numpy(), gap_factor=gap_factor)
    if sampling.n_gaps:
        warnings.append(f"{sampling.n_gaps} gap(s) longer than {gap_factor} x median interval.")

    return SensorStream(
        name=stream,
        source_path=path,
        data=out,
        units=units,
        raw_columns=header,
        sampling=sampling,
        phone_sensor_offset_ms=offset,
        warnings=warnings,
    )


def discover_stream_files(directory: str | Path) -> dict[str, Path]:
    """Find Polar stream CSVs in ``directory`` (non-recursive).

    Raises ``SensorFileError`` if the directory has no recognisable files or
    contains more than one file for the same stream type (i.e. more than one
    recording mixed together).
    """
    directory = Path(directory)
    if not directory.is_dir():
        raise SensorFileError(f"{directory}: not a directory.")
    found: dict[str, list[Path]] = {}
    for p in sorted(directory.iterdir()):
        name = parse_stream_name(p) if p.is_file() else None
        if name:
            found.setdefault(name, []).append(p)
    if not found:
        raise SensorFileError(
            f"{directory}: no sensor files found. Expected names like 'acc_20261126_175628.csv'."
        )
    dupes = {k: [p.name for p in v] for k, v in found.items() if len(v) > 1}
    if dupes:
        raise SensorFileError(
            f"{directory}: more than one file per stream {dupes}. Put each recording in its own directory."
        )
    return {k: v[0] for k, v in found.items()}


def load_recording(directory: str | Path, recording_id: str | None = None, gap_factor: float = 1.5) -> Recording:
    """Load every supported stream file in a recording directory.

    Missing streams are reported in ``Recording.missing_streams``; nothing is
    substituted for them.
    """
    directory = Path(directory)
    files = discover_stream_files(directory)
    streams = {name: load_stream(path, name, gap_factor=gap_factor) for name, path in files.items()}
    missing = [s for s in STREAM_SPECS if s not in streams]
    rec = Recording(
        recording_id=recording_id or directory.name,
        directory=directory,
        streams=streams,
        missing_streams=missing,
    )
    ov = compute_overlap(streams)
    if ov["common"] is None and len(streams) > 1:
        rec.warnings.append("Sensor streams do not all overlap in time.")
    return rec


def compute_overlap(streams: dict[str, SensorStream]) -> dict:
    """Temporal overlap between streams.

    Returns
    -------
    dict with
      ``common``: ``{"start", "end", "duration_s"}`` for the interval covered by
      all streams, or ``None`` if they do not all overlap;
      ``pairwise``: ``{"a|b": duration_s}`` (0.0 when disjoint).
    """
    names = sorted(streams)
    pairwise: dict[str, float] = {}
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            lo = max(streams[a].start, streams[b].start)
            hi = min(streams[a].end, streams[b].end)
            pairwise[f"{a}|{b}"] = max(0.0, (hi - lo).total_seconds())
    common = None
    if streams:
        lo = max(s.start for s in streams.values())
        hi = min(s.end for s in streams.values())
        if hi > lo:
            common = {"start": lo.isoformat(), "end": hi.isoformat(), "duration_s": (hi - lo).total_seconds()}
    return {"common": common, "pairwise": pairwise}
