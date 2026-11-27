"""Gyroscope and magnetometer window features (basic, orientation-independent).

Gyroscope (deg/s): angular speed |w| = sqrt(wx^2 + wy^2 + wz^2). Zero-rate
bias is not removed; in the audited recording |w| at rest is ~4 dps, so small
values are dominated by bias/noise.

Magnetometer (gauss): field magnitude |B| only. Earth's field is ~0.25-0.65 G.
The audited recording shows |B| of 0.46-1.10 G varying with orientation,
which indicates uncalibrated hard/soft-iron offsets. Heading / orientation is
therefore NOT computed; it needs a calibration procedure first.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from phenotyping.processing.accelerometer import vector_magnitude

NAN = float("nan")
EARTH_FIELD_RANGE_G = (0.25, 0.65)


def gyro_features(gyro: pd.DataFrame, fs: float, min_coverage_s: float = 5.0) -> dict:
    """Angular speed summary: mean/p95/max |w| (deg/s), total rotation (deg = integral of |w| dt)."""
    keys = ["gyro_speed_mean_dps", "gyro_speed_p95_dps", "gyro_speed_max_dps", "gyro_total_rotation_deg"]
    cov = len(gyro) / fs
    if cov < min_coverage_s:
        return {**{k: NAN for k in keys}, "gyro_status": f"insufficient_data({cov:.1f}s<{min_coverage_s}s)"}
    w = vector_magnitude(gyro["x_dps"], gyro["y_dps"], gyro["z_dps"])
    return {
        "gyro_speed_mean_dps": float(np.nanmean(w)),
        "gyro_speed_p95_dps": float(np.nanpercentile(w, 95)),
        "gyro_speed_max_dps": float(np.nanmax(w)),
        "gyro_total_rotation_deg": float(np.nansum(w) / fs),
        "gyro_status": "ok_bias_not_removed",
    }


def mag_features(mag: pd.DataFrame, fs: float, min_coverage_s: float = 5.0) -> dict:
    """Magnetic field magnitude mean/SD (gauss) with a calibration plausibility flag."""
    cov = len(mag) / fs
    if cov < min_coverage_s:
        return {"mag_field_mean_gauss": NAN, "mag_field_sd_gauss": NAN,
                "mag_status": f"insufficient_data({cov:.1f}s<{min_coverage_s}s)"}
    b = vector_magnitude(mag["x_gauss"], mag["y_gauss"], mag["z_gauss"])
    mean = float(np.nanmean(b))
    lo, hi = EARTH_FIELD_RANGE_G
    status = "ok" if lo <= mean <= hi else "uncalibrated_magnitude_outside_earth_field_range"
    return {"mag_field_mean_gauss": mean, "mag_field_sd_gauss": float(np.nanstd(b, ddof=1)), "mag_status": status}
