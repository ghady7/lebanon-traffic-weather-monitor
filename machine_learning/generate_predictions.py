"""
generate_predictions.py — Generate and persist 7-day traffic predictions.

Loads the trained model from model.pkl, builds a feature grid covering
all active Lebanese routes for the next N days (hourly), runs inference,
and upserts results into dbo.fact_predictions in SQL Server.

Usage:
    python machine_learning/generate_predictions.py [--days 7] [--model model.pkl]

Exit codes:
    0  — predictions written successfully
    1  — unexpected error
    2  — model file not found (train first)
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import joblib
import pandas as pd
import pyodbc

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "data_pipeline"))

from config.settings import load_environment       # noqa: E402
from config.lebanon_config import ROUTES           # noqa: E402

# Default model location
DEFAULT_MODEL_PATH = Path(__file__).parent / "model.pkl"

# Weather defaults used when forecasting (no live forecast API yet)
# These represent typical Lebanese late-summer conditions.
# Future enhancement: pull from OpenWeather forecast API.
WEATHER_DEFAULTS = {
    "weather_category": "Clear",
    "temperature":      26.0,
    "humidity":         60.0,
    "wind_speed":        3.0,
    "cloud_coverage":   20.0,
}


def time_of_day_category(hour: int) -> str:
    if 7 <= hour <= 9:   return "Morning Peak"
    if 16 <= hour <= 18: return "Evening Peak"
    if 10 <= hour <= 15: return "Midday"
    return "Off-Peak"


def build_feature_grid(days: int = 7) -> pd.DataFrame:
    """
    Create a DataFrame with one row per (active_route × hour) for the
    next `days` days, starting from the next full hour in UTC.
    """
    now_utc = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    rows: list[dict] = []

    for route in ROUTES:
        if not route.get("active", True):
            continue
        for h in range(days * 24):
            dt      = now_utc + timedelta(hours=h + 1)  # start from next hour
            weekday = dt.strftime("%A")
            rows.append({
                # identifiers
                "route_id":                   route["route_id"],
                "route_category":             route.get("route_category", "Unknown"),
                "prediction_for_datetime_utc": dt,
                "prediction_for_date":         dt.date(),
                # time features
                "hour_num":               dt.hour,
                "weekend_flag":           1 if weekday in ("Friday", "Saturday") else 0,
                "time_of_day_category":   time_of_day_category(dt.hour),
                "day_name":               weekday,
                "month_num":              dt.month,
                # weather defaults
                **WEATHER_DEFAULTS,
            })

    return pd.DataFrame(rows)


def get_connection() -> pyodbc.Connection:
    load_environment()
    driver   = os.getenv("SQL_DRIVER",   "{ODBC Driver 18 for SQL Server}")
    server   = os.getenv("SQL_SERVER",   "localhost")
    database = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    return pyodbc.connect(
        f"DRIVER={driver};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;"
    )


def get_route_key_map(conn: pyodbc.Connection) -> dict[str, int]:
    """Return {route_id: route_key} from dbo.dim_route."""
    cur = conn.cursor()
    cur.execute("SELECT route_id, route_key FROM dbo.dim_route;")
    return {row[0]: row[1] for row in cur.fetchall()}


def upsert_predictions(
    grid: pd.DataFrame,
    model_version: str,
    conn: pyodbc.Connection,
) -> int:
    """
    Insert rows that don't already exist for the (route_key, datetime, model_version)
    unique key.  Returns the number of rows inserted.
    """
    route_map = get_route_key_map(conn)
    cur = conn.cursor()

    INSERT_SQL = """
        IF NOT EXISTS (
            SELECT 1 FROM dbo.fact_predictions
            WHERE  route_key                   = ?
              AND  prediction_for_datetime_utc = ?
              AND  model_version               = ?
        )
        INSERT INTO dbo.fact_predictions (
            route_key,
            prediction_for_datetime_utc,
            prediction_for_date,
            prediction_for_hour,
            day_of_week,
            weekend_flag,
            time_of_day_category,
            predicted_travel_time_minutes,
            predicted_congestion_pct,
            model_version
        ) VALUES (?,?,?,?,?,?,?,?,?,?)
    """

    inserted = 0
    for _, row in grid.iterrows():
        rk = route_map.get(row["route_id"])
        if rk is None:
            # Route not yet in dim_route (no data collected yet for it)
            continue

        ptt = round(float(row["predicted_travel_time_minutes"]), 2)
        cur.execute(
            INSERT_SQL,
            # EXISTS check params
            rk,
            row["prediction_for_datetime_utc"],
            model_version,
            # INSERT params
            rk,
            row["prediction_for_datetime_utc"],
            row["prediction_for_date"],
            int(row["hour_num"]),
            row["day_name"],
            int(row["weekend_flag"]),
            row["time_of_day_category"],
            ptt,
            None,           # congestion_pct — derived in a future enhancement
            model_version,
        )
        inserted += 1

    conn.commit()
    return inserted


def generate(days: int = 7, model_path: Path = DEFAULT_MODEL_PATH) -> None:
    """Main generation routine."""
    if not model_path.exists():
        print(
            f"[SKIP] Model not found at {model_path}. "
            "Run train_model.py first."
        )
        sys.exit(2)

    print(f"[INFO] Loading model from {model_path}...")
    bundle        = joblib.load(model_path)
    model         = bundle["model"]
    meta          = bundle["meta"]
    features      = bundle["features"]
    model_version = meta["model_version"]

    print(f"[INFO] Building feature grid ({days} days × {len(ROUTES)} routes)...")
    grid = build_feature_grid(days)

    # Fill any missing feature columns with sensible defaults before inference
    for col in features:
        if col not in grid.columns:
            grid[col] = 0

    print(f"[INFO] Running inference on {len(grid)} rows...")
    grid["predicted_travel_time_minutes"] = model.predict(grid[features])

    print("[INFO] Connecting to SQL Server...")
    conn = get_connection()
    try:
        inserted = upsert_predictions(grid, model_version, conn)
        print(
            f"[OK]   {inserted} prediction rows upserted "
            f"(model={model_version}, days={days})."
        )
    finally:
        conn.close()


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Generate and persist 7-day traffic predictions into dbo.fact_predictions."
    )
    ap.add_argument(
        "--days", type=int, default=7,
        help="Number of days ahead to predict (default: 7).",
    )
    ap.add_argument(
        "--model", type=Path, default=DEFAULT_MODEL_PATH,
        help="Path to the trained model .pkl file (default: machine_learning/model.pkl).",
    )
    args = ap.parse_args()
    generate(days=args.days, model_path=args.model)


if __name__ == "__main__":
    main()
