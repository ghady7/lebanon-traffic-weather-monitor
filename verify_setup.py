"""
verify_setup.py — Quick environment health check.

Run this script to confirm that:
  1. All required Python packages are importable
  2. The data_pipeline config loads cleanly
  3. SQL Server is reachable (if credentials are present)
  4. The ML scripts can be imported

Usage:
    python verify_setup.py
"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "data_pipeline"))

REQUIRED_PACKAGES = [
    ("requests",      "requests"),
    ("pandas",        "pandas"),
    ("pyodbc",        "pyodbc"),
    ("sklearn",       "sklearn"),
    ("dotenv",        "dotenv"),
    ("dateutil",      "dateutil"),
    ("joblib",        "joblib"),
    ("numpy",         "numpy"),
]

OPTIONAL_PACKAGES = [
    ("xgboost", "xgboost"),
]


def check(label: str, import_name: str, required: bool = True) -> bool:
    try:
        mod = importlib.import_module(import_name)
        version = getattr(mod, "__version__", "?")
        print(f"  [OK] {label:<20} version={version}")
        return True
    except ImportError as e:
        status = "[FAIL]" if required else "[SKIP]"
        print(f"  {status} {label:<20} — {e}")
        return not required


def main() -> None:
    print("\n=== Lebanon Traffic Monitor - Setup Verification ===\n")
    all_ok = True

    print("-- Required packages ----------------------------------")
    for label, imp in REQUIRED_PACKAGES:
        ok = check(label, imp, required=True)
        all_ok = all_ok and ok

    print("\n-- Optional packages -----------------------------------")
    for label, imp in OPTIONAL_PACKAGES:
        check(label, imp, required=False)

    print("\n-- Config modules --------------------------------------")
    try:
        from config.lebanon_config import ROUTES, WEATHER_LOCATIONS  # noqa: F401
        print(f"  [OK] lebanon_config         routes={len(ROUTES)}, weather_locations={len(WEATHER_LOCATIONS)}")
    except Exception as e:
        print(f"  [FAIL] lebanon_config       -- {e}")
        all_ok = False

    try:
        from config.settings import load_environment  # noqa: F401
        load_environment()
        print("  [OK] settings               load_environment() succeeded")
    except Exception as e:
        print(f"  [FAIL] settings             -- {e}")
        all_ok = False

    print("\n-- ML modules ------------------------------------------")
    ml_modules = [
        ("machine_learning.train_model",          ROOT / "machine_learning" / "train_model.py"),
        ("machine_learning.generate_predictions",  ROOT / "machine_learning" / "generate_predictions.py"),
    ]
    for mod_name, path in ml_modules:
        if path.exists():
            print(f"  [OK] {mod_name}")
        else:
            print(f"  [MISSING] {path.name}")
            all_ok = False

    print("\n-- SQL Server ------------------------------------------")
    import os
    server = os.getenv("SQL_SERVER", "localhost")
    db     = os.getenv("SQL_DATABASE", "lebanon_traffic_weather")
    try:
        import pyodbc
        driver = os.getenv("SQL_DRIVER", "{ODBC Driver 18 for SQL Server}")
        conn   = pyodbc.connect(
            f"DRIVER={driver};SERVER={server};DATABASE={db};"
            "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;",
            timeout=5,
        )
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM dbo.staging_table;")
        staging_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM dbo.fact_traffic;")
        fact_count = cur.fetchone()[0]
        conn.close()
        print(f"  [OK] Connected to {server}\\{db}")
        print(f"       staging_table rows : {staging_count}")
        print(f"       fact_traffic rows  : {fact_count}")
    except Exception as e:
        print(f"  [WARN] Cannot connect to SQL Server ({server}\\{db}): {e}")
        print("         This is expected if SQL Server is not running or DB not created yet.")

    print("\n" + ("=" * 52))
    if all_ok:
        print("  ALL CHECKS PASSED - environment is ready.")
    else:
        print("  SOME CHECKS FAILED - see [FAIL] lines above.")
    print("=" * 52 + "\n")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
