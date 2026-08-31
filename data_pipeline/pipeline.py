from __future__ import annotations

import logging
from datetime import datetime

from config.settings import load_environment, validate_required_settings


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("lebanon_traffic_weather")


def main() -> None:
    """Minimal project entry point for Phase 1 setup validation."""
    load_environment()
    logger.info("Pipeline start - Phase 1 setup validation")
    logger.info("Loading configuration and validating required environment values.")

    settings = validate_required_settings()
    logger.info("Configuration validated successfully for %s", settings["SQL_DATABASE"])
    logger.info("Project ready for Phase 2 API testing and configuration-driven ETL work.")


if __name__ == "__main__":
    main()
