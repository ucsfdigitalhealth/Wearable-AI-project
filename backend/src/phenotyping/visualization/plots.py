"""Diagnostic plots for one processed recording.

All time axes are elapsed seconds since the recording start (earliest sample
of any stream); the UTC start time is shown in each title.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from phenotyping.features.inertial import EARTH_FIELD_RANGE_G  # noqa: E402
from phenotyping.processing.accelerometer import vector_magnitude  # noqa: E402

INTENSITY_COLOURS = {"sedentary": "#9aa5b1", "light": "#5fa8d3", "moderate": "#f4a259", "vigorous": "#d1495b",
                     "unknown": "#dddddd"}


def _elapsed(times: pd.Series, t0: pd.Timestamp) -> np.ndarray:
    return (times - t0).dt.total_seconds().to_numpy()


def _shade(ax, t: np.ndarray, mask: np.ndarray, label: str, colour: str = "0.85") -> None:
    """Shade contiguous True regions of ``mask`` (aligned with ``t``)."""
    if mask is None or not np.any(mask):
        return
    m = np.asarray(mask, bool)
    edges = np.diff(np.concatenate(([0], m.astype(int), [0])))
    first = True
    for a, b in zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1) - 1):
        ax.axvspan(t[a], t[b], color=colour, alpha=0.6, lw=0, label=label if first else None, zorder=0)
        first = False


def _title(base: str, t0: pd.Timestamp) -> str:
    return f"{base}\nrecording start {t0.strftime('%Y-%m-%d %H:%M:%S')} UTC"


def _save(fig, path: Path) -> str:
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path.name


def plot_ppg_peaks(rec, ppg_res, ppg_motion_or_unrel: np.ndarray, out: Path, zoom_s: float = 10.0) -> str:
    """Raw selected PPG channel and filtered pulse wave with accepted/rejected peaks."""
    t0 = rec.start
    ppg = rec.streams["ppg"]
    t = _elapsed(ppg.data["time"], t0)
    beats = ppg_res.beats
    tb = t[beats["sample"].to_numpy(int)] + (beats["t_s"].to_numpy() - ppg.data["t_s"].to_numpy()[beats["sample"].to_numpy(int)])
    ok = np.zeros(len(beats), bool)
    ok[1:] = ppg_res.intervals["valid"].to_numpy(bool)
    ok[:-1] |= ppg_res.intervals["valid"].to_numpy(bool)  # beat opens or closes a valid interval
    yb = ppg_res.filtered[beats["sample"].to_numpy(int)]

    # Zoom on the 10-s stretch with the most accepted beats.
    best, best_n = t[0], -1
    for s in np.arange(t[0], max(t[0] + 1e-9, t[-1] - zoom_s), 1.0):
        n = int(np.sum(ok & (tb >= s) & (tb < s + zoom_s)))
        if n > best_n:
            best, best_n = s, n

    fig, axes = plt.subplots(3, 1, figsize=(13, 9), gridspec_kw={"height_ratios": [1, 1.3, 1.3]})
    ax = axes[0]
    ax.plot(t, ppg_res.raw, lw=0.7, color="tab:purple", label=f"raw {ppg_res.channel}")
    ax.set_ylabel("raw PPG [ADC counts]")
    ax.set_xlim(t[0], t[-1])
    ax.set_title(_title(f"PPG waveform ({ppg_res.channel}) and detected pulse peaks", t0))
    ax.legend(loc="upper right", fontsize=8)
    for ax, (lo, hi), sub in ((axes[1], (t[0], t[-1]), "full recording"), (axes[2], (best, best + zoom_s), f"zoom {zoom_s:.0f} s")):
        sel = (t >= lo) & (t <= hi)
        _shade(ax, t[sel], ppg_motion_or_unrel[sel], "unreliable (motion / discontinuity)")
        ax.plot(t[sel], ppg_res.filtered[sel], lw=0.8, color="tab:blue",
                label="band-passed" + (", inverted" if ppg_res.inverted else ""))
        bs = (tb >= lo) & (tb <= hi)
        ax.plot(tb[bs & ok], yb[bs & ok], "o", ms=4, color="tab:green", label="peak (accepted)")
        ax.plot(tb[bs & ~ok], yb[bs & ~ok], "x", ms=6, color="tab:red", label="peak (rejected interval)")
        ax.set_ylabel("filtered PPG [a.u.]")
        ax.set_title(sub, fontsize=9)
        ax.set_xlim(lo, hi)
        ax.legend(loc="upper right", fontsize=8, ncol=2)
    axes[-1].set_xlabel("elapsed time [s]")
    return _save(fig, out / "01_ppg_peaks.png")


def plot_heart_rate(rec, intervals: pd.DataFrame, ppg_unrel_t: tuple[np.ndarray, np.ndarray] | None, out: Path) -> str:
    """Beat-to-beat pulse rate (valid / rejected) and device-reported HR."""
    t0 = rec.start
    fig, ax = plt.subplots(figsize=(13, 4.5))
    if ppg_unrel_t is not None:
        _shade(ax, ppg_unrel_t[0], ppg_unrel_t[1], "unreliable PPG (motion / discontinuity)")
    te = _elapsed(intervals["time_utc"], t0)
    v = intervals["valid"].to_numpy(bool)
    hr = intervals["instantaneous_hr_bpm"].to_numpy()
    # Connect only consecutive accepted intervals; break the line across rejected ones.
    hr_line = np.where(v, hr, np.nan)
    ax.plot(te, hr_line, "-", lw=1, color="tab:red")
    ax.plot(te[v], hr[v], "o", ms=4, color="tab:red", label="PPG pulse rate, accepted intervals")
    ax.plot(te[~v], hr[~v], "x", ms=5, color="0.5", label="PPG pulse rate, rejected intervals")
    if v.any():
        mean_hr = 60000.0 / intervals.loc[v, "ibi_ms"].mean()
        ax.axhline(mean_hr, ls=":", color="tab:red", lw=1, label=f"mean of accepted = {mean_hr:.1f} bpm")
    if "hr" in rec.streams:
        d = rec.streams["hr"].data
        d = d[d["hr_bpm"] > 0]
        ax.step(_elapsed(d["time"], t0), d["hr_bpm"], where="post", color="k", lw=1.2,
                label="Polar device HR (1 Hz, unvalidated)")
    ax.set_ylim(30, 160)
    ax.set_xlabel("elapsed time [s]")
    ax.set_ylabel("rate [beats/min]")
    ax.set_title(_title("Heart / pulse rate over time", t0))
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(alpha=0.3)
    return _save(fig, out / "02_heart_rate.png")


def plot_acc_xyz(rec, acc: pd.DataFrame, out: Path) -> str:
    t0 = rec.start
    t = _elapsed(acc["time"], t0)
    fig, ax = plt.subplots(figsize=(13, 4.5))
    for c, col in zip(("x_mg", "y_mg", "z_mg"), ("tab:red", "tab:green", "tab:blue")):
        ax.plot(t, acc[c], lw=0.7, color=col, label=c[0].upper())
    ax.set_xlabel("elapsed time [s]")
    ax.set_ylabel("acceleration [mg]")
    ax.set_title(_title("Raw accelerometer X / Y / Z (sensor axes; orientation depends on placement)", t0))
    ax.legend(loc="upper right")
    ax.grid(alpha=0.3)
    return _save(fig, out / "03_acc_xyz.png")


def plot_acc_activity(rec, acc: pd.DataFrame, motion: np.ndarray, epochs: pd.DataFrame | None, out: Path) -> str:
    t0 = rec.start
    t = _elapsed(acc["time"], t0)
    fig, axes = plt.subplots(2, 1, figsize=(13, 7), sharex=True)
    ax = axes[0]
    _shade(ax, t, motion, "movement (1-s total X/Y/Z SD above threshold)")
    ax.plot(t, acc["magnitude_mg"], lw=0.7, color="k", label="|a|")
    ax.axhline(1000, ls="--", lw=0.8, color="tab:blue", label="1 g")
    ax.set_ylabel("vector magnitude [mg]")
    ax.set_title(_title("Accelerometer magnitude and activity intensity", t0))
    ax.legend(loc="upper right", fontsize=8)
    ax = axes[1]
    ax.plot(t, acc["enmo_mg"], lw=0.6, color="0.4", label="ENMO (per sample)")
    if epochs is not None and len(epochs):
        es = _elapsed(epochs["epoch_start_utc"], t0)
        width = (epochs["epoch_end_utc"] - epochs["epoch_start_utc"]).dt.total_seconds().to_numpy()
        for lvl in INTENSITY_COLOURS:
            m = (epochs["activity_level"] == lvl).to_numpy()
            if m.any():
                ax.bar(es[m], epochs.loc[m, "acc_enmo_mean_mg"], width=width[m], align="edge", alpha=0.6,
                       color=INTENSITY_COLOURS[lvl], edgecolor="k", lw=0.5, label=f"epoch mean ENMO: {lvl}")
    ax.set_yscale("symlog", linthresh=10)
    ax.set_ylabel("ENMO [mg] (symlog)")
    ax.set_xlabel("elapsed time [s]")
    ax.legend(loc="upper right", fontsize=8)
    ax.text(0.01, 0.95, "intensity cut-points: wrist-derived, provisional", transform=ax.transAxes, fontsize=8, va="top")
    return _save(fig, out / "04_acc_activity.png")


def plot_gyro_mag(rec, out: Path) -> str | None:
    t0 = rec.start
    have = [s for s in ("gyro", "mag") if s in rec.streams]
    if not have:
        return None
    fig, axes = plt.subplots(len(have), 1, figsize=(13, 3.8 * len(have)), squeeze=False)
    for ax, name in zip(axes[:, 0], have):
        d = rec.streams[name].data
        t = _elapsed(d["time"], t0)
        cols = [c for c in d.columns if c.startswith(("x_", "y_", "z_"))]
        unit = cols[0].split("_", 1)[1]
        for c, col in zip(cols, ("tab:red", "tab:green", "tab:blue")):
            ax.plot(t, d[c], lw=0.6, color=col, label=c[0].upper())
        mag = vector_magnitude(*(d[c] for c in cols))
        ax.plot(t, mag, lw=1.0, color="k", label="magnitude")
        if name == "gyro":
            ax.set_ylabel("angular velocity [deg/s]")
            ax.set_title(_title("Gyroscope", t0) if ax is axes[0, 0] else "Gyroscope")
        else:
            ax.axhspan(*EARTH_FIELD_RANGE_G, color="tab:green", alpha=0.1, label="typical Earth field")
            ax.set_ylabel("magnetic field [gauss]")
            ax.set_title((_title("", t0) + "\n") * (ax is axes[0, 0]) + "Magnetometer (uncalibrated)")
        ax.legend(loc="upper right", fontsize=8, ncol=5)
        ax.grid(alpha=0.3)
        ax.set_xlabel("elapsed time [s]")
    return _save(fig, out / "05_gyro_mag.png")


def make_all_plots(rec, ppg_res, acc, acc_motion, intervals, epochs, out_dir: str | Path) -> list[str]:
    """Generate every plot the available data supports. Returns file names."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    made: list[str] = []
    unrel_t = None
    if ppg_res is not None:
        made.append(plot_ppg_peaks(rec, ppg_res, ppg_res.unreliable, out))
        unrel_t = (_elapsed(rec.streams["ppg"].data["time"], rec.start), ppg_res.unreliable)
        if intervals is not None and len(intervals):
            made.append(plot_heart_rate(rec, intervals, unrel_t, out))
    if acc is not None:
        made.append(plot_acc_xyz(rec, acc, out))
        made.append(plot_acc_activity(rec, acc, acc_motion, epochs, out))
    g = plot_gyro_mag(rec, out)
    if g:
        made.append(g)
    return made
