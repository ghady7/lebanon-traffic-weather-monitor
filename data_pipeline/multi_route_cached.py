from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

PROJECT_ROOT = __file__
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, os.path.dirname(__file__))

from config.lebanon_config import ROUTES
from config.settings import load_environment

# Import helpers from single_route_extract to reuse staging insertion and builders
from single_route_extract import (
    build_tomtom_url,
    build_openweather_url,
    get_mock_route_payload,
    get_mock_weather_payload,
    build_staging_row,
    insert_staging_row,
)


LOG_DIR = os.path.join(os.path.dirname(__file__), "logs")
os.makedirs(LOG_DIR, exist_ok=True)

logger = logging.getLogger("lebanon_traffic_weather.multi_route_cached")
logger.setLevel(logging.INFO)

# Console handler
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
ch.setFormatter(formatter)
logger.addHandler(ch)

# File handler
run_ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
log_file = os.path.join(LOG_DIR, f"multi_route_cached_{run_ts}.log")
fh = logging.FileHandler(log_file)
fh.setLevel(logging.INFO)
fh.setFormatter(formatter)
logger.addHandler(fh)


def make_session_with_retries(total: int = 5, backoff_factor: float = 0.5) -> requests.Session:
    session = requests.Session()
    retries = Retry(
        total=total,
        backoff_factor=backoff_factor,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retries)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def fetch_with_session(session: requests.Session, url: str, label: str, timeout: int = 25) -> Dict[str, Any]:
    logger.info("Fetching %s", label)
    try:
        resp = session.get(url, timeout=timeout)
    except Exception as exc:
        logger.exception("HTTP request for %s failed: %s", label, exc)
        raise

    if resp.status_code >= 400:
        # If retry exhausted, show details
        logger.error("%s returned HTTP %s: %s", label, resp.status_code, resp.text[:500])
        resp.raise_for_status()

    payload = resp.json()
    if not isinstance(payload, dict):
        raise ValueError(f"{label} response was not a JSON object")
    return payload


def run_all_cached(mock: bool = False, pause_between_calls: float = 0.2) -> Dict[str, Any]:
    load_environment()
    session = make_session_with_retries()
    results = {"success": [], "failed": []}

    # Build mapping of weather_location_id -> weather payload (cached)
    weather_cache: Dict[str, Dict[str, Any]] = {}

    active_routes = [r for r in ROUTES if r.get("active", True)]
    logger.info("Starting cached multi-route extraction for %d routes (mock=%s)", len(active_routes), mock)

    # First, identify unique weather_location_ids to fetch
    unique_weather_ids = {r["weather_location_id"] for r in active_routes}

    from config.lebanon_config import WEATHER_LOCATIONS

    if mock:
        logger.info("Mock mode: populating weather cache with mock payloads")
        for wid in unique_weather_ids:
            location = next((l for l in WEATHER_LOCATIONS if l["location_id"] == wid), None)
            if location is None:
                logger.error("Weather location %s not found in configuration", wid)
                results["failed"].append({"weather_location_id": wid, "error": "missing_location_config"})
                continue
            weather_cache[wid] = {"location": location, "payload": get_mock_weather_payload()}
    else:
        for wid in unique_weather_ids:
            # find a location dict for this id from config
            location = next((l for l in WEATHER_LOCATIONS if l["location_id"] == wid), None)
            if location is None:
                logger.error("Weather location %s not found in configuration", wid)
                results["failed"].append({"weather_location_id": wid, "error": "missing_location_config"})
                continue

            url = build_openweather_url(location, os.getenv("OPENWEATHER_API_KEY"))
            try:
                payload = fetch_with_session(session, url, f"OpenWeather:{wid}")
                weather_cache[wid] = {"location": location, "payload": payload}
                logger.info("Cached weather for %s", wid)
            except Exception as exc:
                logger.exception("Failed to fetch weather for %s: %s", wid, exc)
                results["failed"].append({"weather_location_id": wid, "error": str(exc)})
            time.sleep(pause_between_calls)

    # Now iterate routes and fetch TomTom per route, reuse weather cache
    for route in active_routes:
        route_id = route["route_id"]
        wid = route["weather_location_id"]
        try:
            if wid not in weather_cache:
                raise RuntimeError(f"Missing weather payload for {wid}")

            cached = weather_cache[wid]
            location_obj = cached["location"] if isinstance(cached, dict) and "location" in cached else None
            weather_payload = cached["payload"] if isinstance(cached, dict) and "payload" in cached else cached

            if mock:
                route_payload = get_mock_route_payload()
            else:
                tomtom_url = build_tomtom_url(route, os.getenv("TOMTOM_API_KEY"))
                route_payload = fetch_with_session(session, tomtom_url, f"TomTom:{route_id}")

            # Build staging row and insert
            row = build_staging_row(route, location_obj, route_payload, weather_payload, mock=mock)
            staging_id = insert_staging_row(row)
            results["success"].append({"route_id": route_id, "staging_record_id": staging_id})
            logger.info("Route %s succeeded (staging_id=%s)", route_id, staging_id)
        except Exception as exc:
            logger.exception("Route %s failed: %s", route_id, exc)
            results["failed"].append({"route_id": route_id, "error": str(exc)})
        time.sleep(pause_between_calls)

    logger.info("Cached multi-route extraction finished. Success: %d, Failed: %d", len(results["success"]), len(results["failed"]))
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Cached multi-route extractor: caches weather and retries HTTP calls")
    parser.add_argument("--mock", action="store_true", help="Use mock payloads instead of live APIs")
    args = parser.parse_args()

    run_result = run_all_cached(mock=args.mock)
    # A scheduled run must fail loudly when any configured route could not be ingested.
    raise SystemExit(1 if run_result["failed"] else 0)
