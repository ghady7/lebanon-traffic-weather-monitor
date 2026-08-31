from __future__ import annotations

import logging
from typing import Any

from config.lebanon_config import ROUTES
from config.settings import load_environment

# Import the single-route runner to avoid duplicating extraction/insert logic
from single_route_extract import run_single_route

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("lebanon_traffic_weather.multi_route")


def run_all(mock: bool = False) -> dict[str, Any]:
    load_environment()
    results: dict[str, Any] = {"success": [], "failed": []}

    active_routes = [r for r in ROUTES if r.get("active", True)]
    logger.info("Starting multi-route extraction for %d active routes (mock=%s)", len(active_routes), mock)

    for route in active_routes:
        route_id = route["route_id"]
        try:
            res = run_single_route(route_id, mock=mock)
            results["success"].append({"route_id": route_id, "staging_record_id": res.get("staging_record_id")})
            logger.info("Route %s succeeded (staging_id=%s)", route_id, res.get("staging_record_id"))
        except Exception as exc:
            logger.exception("Route %s failed: %s", route_id, exc)
            results["failed"].append({"route_id": route_id, "error": str(exc)})

    logger.info("Multi-route extraction completed. Success: %d, Failed: %d", len(results["success"]), len(results["failed"]))
    return results


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run extraction for all configured routes")
    parser.add_argument("--mock", action="store_true", help="Use mock payloads instead of live API calls")
    args = parser.parse_args()

    run_all(mock=args.mock)
