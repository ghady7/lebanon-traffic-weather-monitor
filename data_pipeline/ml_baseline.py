"""Optional baseline model scaffold.

Run only after the database has accumulated enough live history. It intentionally
does not train on mock data unless explicitly requested.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import pandas as pd
import pyodbc
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

from config.settings import load_environment


QUERY = """
SELECT
    r.route_id,
    t.hour_num,
    t.weekend_flag,
    w.weather_category,
    w.temperature,
    w.humidity,
    f.travel_time_minutes,
    f.traffic_observation_timestamp
FROM dbo.fact_traffic f
JOIN dbo.dim_route r ON r.route_key = f.route_key
JOIN dbo.dim_time t ON t.time_key = f.time_key
LEFT JOIN dbo.dim_weather w ON w.weather_key = f.weather_key
WHERE f.travel_time_minutes IS NOT NULL
ORDER BY f.traffic_observation_timestamp;
"""


def load_training_data() -> pd.DataFrame:
    load_environment()
    driver = os.getenv("SQL_DRIVER", "{ODBC Driver 18 for SQL Server}")
    server = os.getenv("SQL_SERVER", "localhost")
    database = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    connection = (
        f"DRIVER={driver};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;"
    )
    with pyodbc.connect(connection) as conn:
        return pd.read_sql_query(QUERY, conn)


def train_and_evaluate(test_fraction: float = 0.2) -> float:
    data = load_training_data()
    if len(data) < 20:
        raise ValueError("At least 20 historical observations are required before training.")
    split = max(1, int(len(data) * (1 - test_fraction)))
    train, test = data.iloc[:split], data.iloc[split:]
    features = ["route_id", "hour_num", "weekend_flag", "weather_category", "temperature", "humidity"]
    categorical = ["route_id", "weather_category"]
    preprocessor = ColumnTransformer(
        [("categorical", OneHotEncoder(handle_unknown="ignore"), categorical)],
        remainder="passthrough",
    )
    model = Pipeline([
        ("preprocessor", preprocessor),
        ("regressor", RandomForestRegressor(n_estimators=200, random_state=42)),
    ])
    model.fit(train[features], train["travel_time_minutes"])
    predictions = model.predict(test[features])
    return float(mean_absolute_error(test["travel_time_minutes"], predictions))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-fraction", type=float, default=0.2)
    args = parser.parse_args()
    print(f"Time-ordered baseline MAE: {train_and_evaluate(args.test_fraction):.3f} minutes")
