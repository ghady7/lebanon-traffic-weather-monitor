from __future__ import annotations

import json
import logging
from typing import Any

import requests

from config.settings import load_environment

logger = logging.getLogger("lebanon_traffic_weather.api_test")
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")


BEIRUT = {"lat": 33.8938, "lon": 35.5018}
JOUNIEH = {"lat": 33.9806, "lon": 35.6177}


def is_placeholder(value: str | None) -> bool:
    if value is None:
        return True
    normalized = value.strip().lower()
    return normalized in {"", "your_tomtom_api_key_here", "your_openweather_api_key_here", "changeme", "example"}


def build_tomtom_route_url(api_key: str, origin: dict[str, float], destination: dict[str, float]) -> str:
    return (
        "https://api.tomtom.com/routing/1/calculateRoute/"
        f"{origin['lat']},{origin['lon']}:{destination['lat']},{destination['lon']}/json"
        f"?key={api_key}&travelMode=car&traffic=true&computeTravelTimeFor=all"
    )


def build_openweather_url(api_key: str, lat: float, lon: float) -> str:
    return (
        "https://api.openweathermap.org/data/2.5/weather"
        f"?lat={lat}&lon={lon}&appid={api_key}&units=metric"
    )


def safe_get(url: str, timeout: int = 20) -> dict[str, Any]:
    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, dict):
        raise ValueError("API response was not a JSON object.")
    return payload


def test_tomtom_api() -> dict[str, Any]:
    api_key = __import__("os").getenv("TOMTOM_API_KEY")
    if is_placeholder(api_key):
        logger.warning("TomTom API key is missing or still a placeholder. Skipping live route request.")
        return {"status": "skipped", "reason": "missing_key"}

    url = build_tomtom_route_url(api_key, BEIRUT, JOUNIEH)
    logger.info("Testing TomTom route endpoint: %s", url)
    payload = safe_get(url)
    logger.info("TomTom payload keys: %s", sorted(payload.keys())[:10])
    return {"status": "ok", "payload": payload}


def test_openweather_api() -> dict[str, Any]:
    api_key = __import__("os").getenv("OPENWEATHER_API_KEY")
    if is_placeholder(api_key):
        logger.warning("OpenWeather API key is missing or still a placeholder. Skipping live weather request.")
        return {"status": "skipped", "reason": "missing_key"}

    url = build_openweather_url(api_key, JOUNIEH["lat"], JOUNIEH["lon"])
    logger.info("Testing OpenWeather endpoint: %s", url)
    payload = safe_get(url)
    logger.info("OpenWeather payload keys: %s", sorted(payload.keys())[:10])
    return {"status": "ok", "payload": payload}


def main() -> None:
    load_environment()
    logger.info("Phase 2: API testing for TomTom and OpenWeather")
    logger.info("Route test target: Beirut -> Jounieh")
    logger.info("Weather test target: Jounieh weather point")

    tomtom_result = test_tomtom_api()
    openweather_result = test_openweather_api()

    logger.info("TomTom result: %s", tomtom_result.get("status"))
    logger.info("OpenWeather result: %s", openweather_result.get("status"))

    if tomtom_result.get("status") == "ok" and openweather_result.get("status") == "ok":
        logger.info("Live API test completed successfully.")
    else:
        logger.info("API calls skipped because required credentials are not configured in the local .env file.")


if __name__ == "__main__":
    main()
