from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pyodbc
import requests
from dateutil import parser as date_parser

PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.lebanon_config import ROUTES, WEATHER_LOCATIONS
from config.settings import load_environment

logger = logging.getLogger("lebanon_traffic_weather.single_route")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")


def get_route_by_id(route_id: str) -> dict[str, Any]:
    for route in ROUTES:
        if route["route_id"] == route_id:
            return route
    raise ValueError(f"Route {route_id} not found in configuration.")


def get_weather_location_by_id(location_id: str) -> dict[str, Any]:
    for location in WEATHER_LOCATIONS:
        if location["location_id"] == location_id:
            return location
    raise ValueError(f"Weather location {location_id} not found in configuration.")


def is_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    return value.strip().lower() in {"", "your_tomtom_api_key_here", "your_openweather_api_key_here", "changeme", "example"}


def build_tomtom_url(route: dict[str, Any], api_key: str) -> str:
    return (
        "https://api.tomtom.com/routing/1/calculateRoute/"
        f"{route['origin_latitude']},{route['origin_longitude']}:{route['destination_latitude']},{route['destination_longitude']}/json"
        f"?key={api_key}&travelMode=car&traffic=true&computeTravelTimeFor=all"
    )


def build_openweather_url(location: dict[str, Any], api_key: str) -> str:
    return (
        "https://api.openweathermap.org/data/2.5/weather"
        f"?lat={location['latitude']}&lon={location['longitude']}&appid={api_key}&units=metric"
    )


def fetch_json(url: str, *, label: str, timeout: int = 25) -> dict[str, Any]:
    response = requests.get(url, timeout=timeout)
    if response.status_code >= 400:
        raise RuntimeError(f"{label} API returned HTTP {response.status_code}: {response.text[:300]}")
    payload = response.json()
    if not isinstance(payload, dict):
        raise ValueError(f"{label} response was not a JSON object.")
    return payload


def parse_datetime(raw_value: Any) -> datetime | None:
    """Parse a datetime from a variety of formats.

    Handles:
    - datetime objects (pass-through)
    - Unix epoch int/float (e.g. OpenWeather 'dt': 1756634400)
    - ISO 8601 strings (e.g. TomTom departure/arrival times)
    Returns UTC-aware datetime or None on failure.
    """
    if raw_value in (None, ""):
        return None
    try:
        if isinstance(raw_value, datetime):
            dt = raw_value
        elif isinstance(raw_value, (int, float)):
            # Unix epoch integer — used by OpenWeather for the 'dt' field
            dt = datetime.fromtimestamp(float(raw_value), tz=timezone.utc)
            return dt
        else:
            # Try numeric string first (e.g. "1756634400")
            try:
                epoch = float(str(raw_value))
                dt = datetime.fromtimestamp(epoch, tz=timezone.utc)
                return dt
            except ValueError:
                pass
            # Fall back to ISO 8601 string parsing
            dt = date_parser.isoparse(str(raw_value))
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except (TypeError, ValueError, OSError):
        return None


def extract_route_metrics(route: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    route_data = (payload.get("routes") or [{}])[0]
    summary = route_data.get("summary") or route_data.get("routeSummary") or {}
    legs = route_data.get("legs") or []
    first_leg = legs[0] if legs else {}

    length_meters = float(summary.get("lengthInMeters") or summary.get("lengthInMeters") or 0)
    travel_time_seconds = float(summary.get("travelTimeInSeconds") or 0)
    delay_seconds = float(summary.get("trafficDelayInSeconds") or 0)
    no_traffic_seconds = float(summary.get("noTrafficTravelTimeInSeconds") or 0)

    departure_dt = parse_datetime(first_leg.get("departureTime"))
    arrival_dt = parse_datetime(first_leg.get("arrivalTime"))

    return {
        "route_id": route["route_id"],
        "route_name": route["route_name"],
        "origin_name": route["origin_name"],
        "destination_name": route["destination_name"],
        "origin_latitude": route["origin_latitude"],
        "origin_longitude": route["origin_longitude"],
        "destination_latitude": route["destination_latitude"],
        "destination_longitude": route["destination_longitude"],
        "weather_location_id": route["weather_location_id"],
        "route_distance_meters": int(length_meters),
        "route_distance_km": round(length_meters / 1000, 2),
        "travel_time_seconds": int(travel_time_seconds),
        "no_traffic_travel_time_seconds": int(no_traffic_seconds),
        "traffic_delay_seconds": int(delay_seconds),
        "departure_timestamp": departure_dt,
        "arrival_timestamp": arrival_dt,
    }


def extract_weather_metrics(location: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    weather_block = (payload.get("weather") or [{}])[0]
    main_block = payload.get("main") or {}
    wind_block = payload.get("wind") or {}
    clouds_block = payload.get("clouds") or {}
    rain_block = payload.get("rain") or {}
    snow_block = payload.get("snow") or {}
    weather_timestamp = parse_datetime(payload.get("dt"))

    return {
        "weather_location_id": location["location_id"],
        "weather_location_name": location["name"],
        "weather_latitude": location["latitude"],
        "weather_longitude": location["longitude"],
        "weather_observation_timestamp": weather_timestamp,
        "temperature": main_block.get("temp"),
        "feels_like_temperature": main_block.get("feels_like"),
        "humidity": main_block.get("humidity"),
        "pressure": main_block.get("pressure"),
        "visibility": payload.get("visibility"),
        "wind_speed": wind_block.get("speed"),
        "wind_direction": wind_block.get("deg"),
        "cloud_coverage": clouds_block.get("all"),
        "rain_1h": rain_block.get("1h"),
        "snow_1h": snow_block.get("1h"),
        "weather_id": weather_block.get("id"),
        "weather_main": weather_block.get("main"),
        "weather_description": weather_block.get("description"),
    }


def get_sql_connection() -> pyodbc.Connection:
    driver = os.getenv("SQL_DRIVER", "{ODBC Driver 18 for SQL Server}")
    server = os.getenv("SQL_SERVER", "localhost")
    database = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    username = os.getenv("SQL_USERNAME")
    password = os.getenv("SQL_PASSWORD")

    candidates = []
    if username and password:
        candidates.append(
            (
                f"DRIVER={driver};SERVER={server};DATABASE={database};UID={username};PWD={password};"
                "Encrypt=no;TrustServerCertificate=yes;",
                "sql_auth",
            )
        )
    candidates.append(
        (
            f"DRIVER={driver};SERVER={server};DATABASE={database};Trusted_Connection=yes;"
            "Encrypt=no;TrustServerCertificate=yes;",
            "windows_auth",
        )
    )

    last_error: Exception | None = None
    for connection_string, auth_mode in candidates:
        try:
            connection = pyodbc.connect(connection_string)
            logger.info("Connected to SQL Server using %s authentication.", auth_mode)
            return connection
        except Exception as exc:  # pragma: no cover - fallback path
            last_error = exc
            logger.warning("SQL Server connection attempt using %s failed: %s", auth_mode, exc)

    if last_error is not None:
        raise last_error
    raise RuntimeError("No SQL Server connection options were available.")


def build_staging_row(route: dict[str, Any], weather: dict[str, Any], route_payload: dict[str, Any], weather_payload: dict[str, Any], *, mock: bool = False) -> dict[str, Any]:
    route_metrics = extract_route_metrics(route, route_payload)
    weather_metrics = extract_weather_metrics(weather, weather_payload)

    return {
        "pipeline_run_id": f"single_route_{'mock' if mock else 'live'}_{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}",
        "route_id": route_metrics["route_id"],
        "route_name": route_metrics["route_name"],
        "origin_name": route_metrics["origin_name"],
        "destination_name": route_metrics["destination_name"],
        "origin_latitude": route_metrics["origin_latitude"],
        "origin_longitude": route_metrics["origin_longitude"],
        "destination_latitude": route_metrics["destination_latitude"],
        "destination_longitude": route_metrics["destination_longitude"],
        "weather_location_id": weather_metrics["weather_location_id"],
        "weather_location_name": weather_metrics["weather_location_name"],
        "weather_latitude": weather_metrics["weather_latitude"],
        "weather_longitude": weather_metrics["weather_longitude"],
        "route_distance_meters": route_metrics["route_distance_meters"],
        "route_distance_km": route_metrics["route_distance_km"],
        "travel_time_seconds": route_metrics["travel_time_seconds"],
        "no_traffic_travel_time_seconds": route_metrics["no_traffic_travel_time_seconds"],
        "traffic_delay_seconds": route_metrics["traffic_delay_seconds"],
        "departure_timestamp": route_metrics["departure_timestamp"],
        "arrival_timestamp": route_metrics["arrival_timestamp"],
        "weather_observation_timestamp": weather_metrics["weather_observation_timestamp"],
        "temperature": weather_metrics["temperature"],
        "feels_like_temperature": weather_metrics["feels_like_temperature"],
        "humidity": weather_metrics["humidity"],
        "pressure": weather_metrics["pressure"],
        "visibility": weather_metrics["visibility"],
        "wind_speed": weather_metrics["wind_speed"],
        "wind_direction": weather_metrics["wind_direction"],
        "cloud_coverage": weather_metrics["cloud_coverage"],
        "rain_1h": weather_metrics["rain_1h"],
        "snow_1h": weather_metrics["snow_1h"],
        "weather_id": weather_metrics["weather_id"],
        "weather_main": weather_metrics["weather_main"],
        "weather_description": weather_metrics["weather_description"],
        "raw_tomtom_payload": json.dumps(route_payload, ensure_ascii=False),
        "raw_openweather_payload": json.dumps(weather_payload, ensure_ascii=False),
        "data_quality_status": "ready" if not mock else "mock_ready",
        "data_quality_issues": None,
    }


def validate_staging_row(row: dict[str, Any]) -> tuple[str, list[str]]:
    """Run ingestion-time data-quality checks and return (status, list_of_issues).

    Rules (not exhaustive):
    - route_id, origin_name, destination_name must be present
    - latitude must be between -90 and 90; longitude between -180 and 180
    - travel_time_seconds, route_distance_meters, no_traffic_travel_time_seconds must be non-negative
    - no_traffic_travel_time_seconds should be > 0 when present
    - humidity 0..100
    - wind_speed >= 0
    - rain_1h, snow_1h, visibility >= 0 when present
    """
    issues: list[str] = []

    def coord_ok(lat, lon):
        try:
            if lat is None or lon is None:
                return False
            return -90 <= float(lat) <= 90 and -180 <= float(lon) <= 180
        except Exception:
            return False

    # Route checks
    if not row.get("route_id"):
        issues.append("route_id_missing")
    if not row.get("origin_name") or not row.get("destination_name"):
        issues.append("origin_or_destination_missing")
    if not coord_ok(row.get("origin_latitude"), row.get("origin_longitude")):
        issues.append("invalid_origin_coordinates")
    if not coord_ok(row.get("destination_latitude"), row.get("destination_longitude")):
        issues.append("invalid_destination_coordinates")

    # Traffic checks
    try:
        if row.get("travel_time_seconds") is not None and int(row.get("travel_time_seconds")) < 0:
            issues.append("negative_travel_time")
    except Exception:
        issues.append("invalid_travel_time")
    try:
        if row.get("route_distance_meters") is not None and int(row.get("route_distance_meters")) < 0:
            issues.append("negative_route_distance")
    except Exception:
        issues.append("invalid_route_distance")
    if row.get("no_traffic_travel_time_seconds") is not None:
        try:
            if int(row.get("no_traffic_travel_time_seconds")) <= 0:
                issues.append("nonpositive_no_traffic_travel_time")
        except Exception:
            issues.append("invalid_no_traffic_travel_time")

    # Weather checks
    try:
        hum = row.get("humidity")
        if hum is not None:
            if not (0 <= int(hum) <= 100):
                issues.append("humidity_out_of_range")
    except Exception:
        issues.append("invalid_humidity")
    try:
        ws = row.get("wind_speed")
        if ws is not None and float(ws) < 0:
            issues.append("negative_wind_speed")
    except Exception:
        issues.append("invalid_wind_speed")
    try:
        if row.get("rain_1h") is not None and float(row.get("rain_1h")) < 0:
            issues.append("negative_rain_1h")
    except Exception:
        issues.append("invalid_rain_1h")
    try:
        if row.get("visibility") is not None and float(row.get("visibility")) < 0:
            issues.append("negative_visibility")
    except Exception:
        issues.append("invalid_visibility")

    status = "valid" if not issues else "invalid"
    return status, issues


def insert_staging_row(row: dict[str, Any]) -> int:
    # Ensure DQ is run if not already set
    if row.get("data_quality_issues") is None:
        status, issues = validate_staging_row(row)
        row["data_quality_status"] = status
        row["data_quality_issues"] = json.dumps(issues, ensure_ascii=False) if issues else None

    sql = """
        INSERT INTO dbo.staging_table (
            pipeline_run_id,
            route_id,
            route_name,
            origin_name,
            destination_name,
            origin_latitude,
            origin_longitude,
            destination_latitude,
            destination_longitude,
            weather_location_id,
            weather_location_name,
            weather_latitude,
            weather_longitude,
            route_distance_meters,
            route_distance_km,
            travel_time_seconds,
            no_traffic_travel_time_seconds,
            traffic_delay_seconds,
            departure_timestamp,
            arrival_timestamp,
            weather_observation_timestamp,
            temperature,
            feels_like_temperature,
            humidity,
            pressure,
            visibility,
            wind_speed,
            wind_direction,
            cloud_coverage,
            rain_1h,
            snow_1h,
            weather_id,
            weather_main,
            weather_description,
            raw_tomtom_payload,
            raw_openweather_payload,
            data_quality_status,
            data_quality_issues
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        );
    """
    params = (
        row["pipeline_run_id"],
        row["route_id"],
        row["route_name"],
        row["origin_name"],
        row["destination_name"],
        row["origin_latitude"],
        row["origin_longitude"],
        row["destination_latitude"],
        row["destination_longitude"],
        row["weather_location_id"],
        row["weather_location_name"],
        row["weather_latitude"],
        row["weather_longitude"],
        row["route_distance_meters"],
        row["route_distance_km"],
        row["travel_time_seconds"],
        row["no_traffic_travel_time_seconds"],
        row["traffic_delay_seconds"],
        row["departure_timestamp"],
        row["arrival_timestamp"],
        row["weather_observation_timestamp"],
        row["temperature"],
        row["feels_like_temperature"],
        row["humidity"],
        row["pressure"],
        row["visibility"],
        row["wind_speed"],
        row["wind_direction"],
        row["cloud_coverage"],
        row["rain_1h"],
        row["snow_1h"],
        row["weather_id"],
        row["weather_main"],
        row["weather_description"],
        row["raw_tomtom_payload"],
        row["raw_openweather_payload"],
        row["data_quality_status"],
        row["data_quality_issues"],
    )

    conn = get_sql_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        conn.commit()
        return cursor.execute("SELECT CAST(SCOPE_IDENTITY() AS INT)").fetchone()[0]
    finally:
        conn.close()


def get_mock_route_payload() -> dict[str, Any]:
    return {
        "routes": [
            {
                "summary": {
                    "lengthInMeters": 29500,
                    "travelTimeInSeconds": 1680,
                    "trafficDelayInSeconds": 240,
                    "noTrafficTravelTimeInSeconds": 1440,
                },
                "legs": [
                    {
                        "departureTime": "2026-08-26T08:00:00+03:00",
                        "arrivalTime": "2026-08-26T08:28:00+03:00",
                    }
                ],
            }
        ]
    }


def get_mock_weather_payload() -> dict[str, Any]:
    return {
        "coord": {"lon": 35.6177, "lat": 33.9806},
        "weather": [{"id": 801, "main": "Clouds", "description": "few clouds"}],
        "main": {"temp": 29.2, "feels_like": 31.0, "humidity": 62, "pressure": 1016},
        "visibility": 9000,
        "wind": {"speed": 4.4, "deg": 150},
        "clouds": {"all": 25},
        "rain": {"1h": 0.0},
        "snow": {"1h": 0.0},
        "dt": 1756634400,
    }


def run_single_route(route_id: str, *, mock: bool = False) -> dict[str, Any]:
    route = get_route_by_id(route_id)
    weather = get_weather_location_by_id(route["weather_location_id"])

    if mock:
        route_payload = get_mock_route_payload()
        weather_payload = get_mock_weather_payload()
        logger.info("Using mock payloads for route %s and weather %s.", route_id, weather["location_id"])
    else:
        tomtom_key = os.getenv("TOMTOM_API_KEY")
        openweather_key = os.getenv("OPENWEATHER_API_KEY")

        if is_placeholder(tomtom_key) or is_placeholder(openweather_key):
            raise RuntimeError("Missing or placeholder API keys. Use --mock to test the ingestion pathway without live API access.")

        route_payload = fetch_json(build_tomtom_url(route, tomtom_key), label="TomTom")
        weather_payload = fetch_json(build_openweather_url(weather, openweather_key), label="OpenWeather")

    row = build_staging_row(route, weather, route_payload, weather_payload, mock=mock)
    inserted_id = insert_staging_row(row)
    logger.info("Inserted staging row %s for route %s", inserted_id, route_id)
    return {"route_id": route_id, "staging_record_id": inserted_id, "row": row}


def main() -> None:
    load_environment()
    parser = argparse.ArgumentParser(description="Extract one route and one weather point into dbo.staging_table")
    parser.add_argument("--route-id", default="R002", help="Configured route ID to ingest")
    parser.add_argument("--mock", action="store_true", help="Use built-in sample payloads instead of calling external APIs")
    args = parser.parse_args()

    try:
        result = run_single_route(args.route_id, mock=args.mock)
        logger.info("Single-route extraction successful: %s", result["staging_record_id"])
    except Exception as exc:  # pragma: no cover - runtime path for failure logging
        logger.exception("Single-route extraction failed: %s", exc)
        raise


if __name__ == "__main__":
    main()
