from __future__ import annotations

import os
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = PROJECT_ROOT / ".env"


def load_dotenv(dotenv_path: str | Path) -> bool:
    """Load key/value pairs from a .env file without requiring python-dotenv."""
    path = Path(dotenv_path)
    if not path.exists():
        return False

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue

        key, value = stripped.split("=", 1)
        os.environ[key.strip()] = value.strip().strip('"').strip("'")
    return True


def load_environment() -> None:
    """Load environment variables from the local .env file when present."""
    if ENV_FILE.exists():
        load_dotenv(ENV_FILE)
    else:
        load_dotenv(PROJECT_ROOT / ".env.example")


def get_required_setting(name: str, *, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def validate_required_settings() -> dict[str, str]:
    settings = {
        "TOMTOM_API_KEY": get_required_setting("TOMTOM_API_KEY"),
        "OPENWEATHER_API_KEY": get_required_setting("OPENWEATHER_API_KEY"),
        "SQL_SERVER": get_required_setting("SQL_SERVER"),
        "SQL_DATABASE": get_required_setting("SQL_DATABASE"),
        "SQL_DRIVER": get_required_setting("SQL_DRIVER"),
    }
    return settings
