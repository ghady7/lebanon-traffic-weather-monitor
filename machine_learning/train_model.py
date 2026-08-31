"""
train_model.py — Train and save the best traffic prediction model.

Reads from dbo.fact_traffic (joined with dim_time, dim_route, dim_weather),
trains a RandomForestRegressor on historical observations, evaluates on a
time-ordered hold-out set, and saves the model + metadata to disk.

Usage:
    python machine_learning/train_model.py [--min-rows 50] [--output model.pkl]

Exit codes:
    0  — model trained and saved successfully
    1  — unexpected error
    2  — not enough data (pipeline skips this step gracefully)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import pyodbc
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

# Resolve project root so we can import data_pipeline config
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "data_pipeline"))

from config.settings import load_environment  # noqa: E402

# ---------------------------------------------------------------------------
# Query — pulls every valid fact row with its dimensional context
# ---------------------------------------------------------------------------
QUERY = """
SELECT
    dr.route_id,
    dr.route_name,
    dr.route_category,
    dt.hour_num,
    dt.weekend_flag,
    dt.time_of_day_category,
    dt.day_name,
    dt.month_num,
    dw.weather_category,
    dw.temperature,
    dw.humidity,
    dw.wind_speed,
    dw.cloud_coverage,
    f.travel_time_minutes,
    f.congestion_pct,
    f.traffic_observation_timestamp
FROM dbo.fact_traffic f
JOIN  dbo.dim_route   dr ON dr.route_key   = f.route_key
JOIN  dbo.dim_time    dt ON dt.time_key    = f.time_key
LEFT JOIN dbo.dim_weather dw ON dw.weather_key = f.weather_key
WHERE f.travel_time_minutes IS NOT NULL
  AND f.travel_time_minutes > 0
ORDER BY f.traffic_observation_timestamp;
"""

# ---------------------------------------------------------------------------
# Feature configuration
# ---------------------------------------------------------------------------
FEATURES = [
    "route_id",
    "route_category",
    "hour_num",
    "weekend_flag",
    "time_of_day_category",
    "day_name",
    "month_num",
    "weather_category",
    "temperature",
    "humidity",
    "wind_speed",
    "cloud_coverage",
]
CATEGORICAL_FEATURES = [
    "route_id",
    "route_category",
    "time_of_day_category",
    "day_name",
    "weather_category",
]
NUMERIC_FEATURES = [f for f in FEATURES if f not in CATEGORICAL_FEATURES]
TARGET = "travel_time_minutes"

NUMERIC_DEFAULTS = {
    "temperature":   26.0,
    "humidity":      60.0,
    "wind_speed":     3.0,
    "cloud_coverage": 20.0,
}


def get_sqlalchemy_engine():
    """Return a SQLAlchemy engine for pandas integration (no UserWarning)."""
    from sqlalchemy import create_engine
    load_environment()
    driver   = os.getenv("SQL_DRIVER",   "ODBC Driver 18 for SQL Server").strip("{}")
    server   = os.getenv("SQL_SERVER",   "localhost")
    database = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    conn_url = (
        f"mssql+pyodbc://@{server}/{database}"
        f"?driver={driver.replace(' ', '+')}"
        "&trusted_connection=yes&encrypt=no&TrustServerCertificate=yes"
    )
    return create_engine(conn_url)


def get_connection() -> pyodbc.Connection:
    """Open a raw pyodbc connection (used for non-pandas queries)."""
    load_environment()
    driver   = os.getenv("SQL_DRIVER",   "{ODBC Driver 18 for SQL Server}")
    server   = os.getenv("SQL_SERVER",   "localhost")
    database = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    conn_str = (
        f"DRIVER={driver};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)


def load_data() -> pd.DataFrame:
    """Fetch training data from SQL Server via SQLAlchemy engine."""
    engine = get_sqlalchemy_engine()
    with engine.connect() as conn:
        df = pd.read_sql_query(QUERY, conn)
    return df


def preprocess(df: pd.DataFrame) -> pd.DataFrame:
    """Fill nulls and ensure correct dtypes."""
    for col, default in NUMERIC_DEFAULTS.items():
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(default)
    for col in CATEGORICAL_FEATURES:
        if col in df.columns:
            df[col] = df[col].fillna("Unknown").astype(str)
    df["weekend_flag"] = df["weekend_flag"].fillna(0).astype(int)
    df["month_num"]    = df["month_num"].fillna(0).astype(int)
    df["hour_num"]     = df["hour_num"].fillna(0).astype(int)
    return df


def build_sklearn_pipeline(n_estimators: int = 300) -> Pipeline:
    """Build the sklearn Pipeline (preprocessor + RandomForest)."""
    preprocessor = ColumnTransformer(
        transformers=[
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), CATEGORICAL_FEATURES),
        ],
        remainder="passthrough",   # pass numeric features through unchanged
    )
    regressor = RandomForestRegressor(
        n_estimators=n_estimators,
        max_features="sqrt",
        min_samples_leaf=3,
        random_state=42,
        n_jobs=-1,
    )
    return Pipeline([("preprocessor", preprocessor), ("regressor", regressor)])


def train(min_rows: int = 50, output_path: Path | None = None) -> dict:
    """
    Main training routine.

    Returns a metadata dict.  Exits with code 2 if there is not enough data.
    """
    print("[INFO] Loading training data from SQL Server...")
    data = load_data()

    if len(data) < min_rows:
        print(
            f"[SKIP] Only {len(data)} rows available — need at least {min_rows}. "
            "Collect more data then re-run."
        )
        sys.exit(2)

    print(f"[INFO] {len(data)} rows loaded. Preprocessing...")
    data = preprocess(data)

    # Time-ordered split — never shuffle when working with time series
    split_idx = max(1, int(len(data) * 0.80))
    train_df  = data.iloc[:split_idx]
    test_df   = data.iloc[split_idx:]

    print(f"[INFO] Training on {len(train_df)} rows, evaluating on {len(test_df)} rows...")
    model = build_sklearn_pipeline()
    model.fit(train_df[FEATURES], train_df[TARGET])

    preds   = model.predict(test_df[FEATURES])
    mae_min = float(mean_absolute_error(test_df[TARGET], preds))
    r2_val  = float(r2_score(test_df[TARGET], preds))

    model_version = datetime.now(timezone.utc).strftime("v%Y%m%d")
    meta = {
        "model_version":    model_version,
        "trained_at_utc":   datetime.now(timezone.utc).isoformat(),
        "train_rows":       int(len(train_df)),
        "test_rows":        int(len(test_df)),
        "mae_minutes":      round(mae_min, 3),
        "r2":               round(r2_val, 4),
        "features":         FEATURES,
        "categorical":      CATEGORICAL_FEATURES,
        "target":           TARGET,
        "min_rows_required": min_rows,
    }

    # --- Save artefacts ---
    output_path = output_path or Path(__file__).parent / "model.pkl"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    bundle = {
        "model":       model,
        "meta":        meta,
        "features":    FEATURES,
        "categorical": CATEGORICAL_FEATURES,
    }
    joblib.dump(bundle, output_path)

    meta_path = output_path.with_suffix(".json")
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    print(f"[OK]   Model saved -> {output_path}")
    print(f"       MAE = {mae_min:.3f} min | R2 = {r2_val:.4f} | version = {model_version}")
    return meta


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Train the Lebanon traffic prediction model and save to disk."
    )
    ap.add_argument(
        "--min-rows", type=int, default=50,
        help="Minimum rows in fact_traffic before training is attempted (default: 50).",
    )
    ap.add_argument(
        "--output", type=Path, default=None,
        help="Path to save the model .pkl file (default: machine_learning/model.pkl).",
    )
    args = ap.parse_args()
    train(min_rows=args.min_rows, output_path=args.output)


if __name__ == "__main__":
    main()
