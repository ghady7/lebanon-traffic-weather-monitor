from __future__ import annotations

import sys
from pathlib import Path

DATA_PIPELINE_ROOT = Path(__file__).resolve().parents[1]
if str(DATA_PIPELINE_ROOT) not in sys.path:
    sys.path.insert(0, str(DATA_PIPELINE_ROOT))

from config.lebanon_config import ROUTE_ID_SET, ROUTES, WEATHER_LOCATION_ID_SET, WEATHER_LOCATIONS


def is_valid_coordinate(latitude: float, longitude: float) -> bool:
    return -90 <= latitude <= 90 and -180 <= longitude <= 180


def validate_weather_locations() -> list[str]:
    errors: list[str] = []
    seen_ids: set[str] = set()
    for location in WEATHER_LOCATIONS:
        location_id = location["location_id"]
        if location_id in seen_ids:
            errors.append(f"Duplicate weather location ID: {location_id}")
        seen_ids.add(location_id)

        if not location["name"]:
            errors.append(f"Weather location {location_id} is missing a name.")
        if not is_valid_coordinate(location["latitude"], location["longitude"]):
            errors.append(f"Weather location {location_id} has invalid coordinates.")
    return errors


def validate_routes() -> list[str]:
    errors: list[str] = []
    seen_ids: set[str] = set()
    for route in ROUTES:
        route_id = route["route_id"]
        if route_id in seen_ids:
            errors.append(f"Duplicate route ID: {route_id}")
        seen_ids.add(route_id)

        if not route["route_name"]:
            errors.append(f"Route {route_id} is missing a route name.")
        if not route["origin_name"] or not route["destination_name"]:
            errors.append(f"Route {route_id} is missing an origin or destination name.")
        if not is_valid_coordinate(route["origin_latitude"], route["origin_longitude"]):
            errors.append(f"Route {route_id} has invalid origin coordinates.")
        if not is_valid_coordinate(route["destination_latitude"], route["destination_longitude"]):
            errors.append(f"Route {route_id} has invalid destination coordinates.")
        if route["weather_location_id"] not in WEATHER_LOCATION_ID_SET:
            errors.append(f"Route {route_id} references missing weather location: {route['weather_location_id']}")

    if len(ROUTE_ID_SET) != len(ROUTES):
        errors.append("Route IDs are not unique across the configuration.")
    return errors


def validate_configuration() -> list[str]:
    errors: list[str] = []
    errors.extend(validate_weather_locations())
    errors.extend(validate_routes())
    return errors


if __name__ == "__main__":
    issues = validate_configuration()
    if issues:
        print("Configuration issues found:")
        for issue in issues:
            print(f"- {issue}")
    else:
        print(f"Validated {len(WEATHER_LOCATIONS)} weather locations and {len(ROUTES)} routes successfully.")
