# Lebanon Traffic & Weather Intelligence Monitor

A production-style end-to-end data engineering project that collects real-time
traffic (TomTom API) and weather (OpenWeather API) data for **10 key Lebanese routes**,
stores and transforms it in **SQL Server**, and powers a **Power BI dashboard** with
a **machine-learning prediction layer**.

## Quick Start

```powershell
# 1. Activate the virtual environment
.\traffic_ml_env\Scripts\Activate.ps1

# 2. Install dependencies
pip install -r data_pipeline\requirements.txt

# 3. Copy and fill in your API keys
copy data_pipeline\.env.example data_pipeline\.env
# Edit data_pipeline\.env with your TomTom and OpenWeather API keys

# 4. Verify the environment
python verify_setup.py

# 5. Run the full pipeline (double-click or from terminal)
.\run_pipeline.bat
```

## Architecture

```
run_pipeline.bat (7 steps)
  │
  ├─ Step 1: Python → TomTom + OpenWeather APIs → dbo.staging_table
  ├─ Step 2: SQLCMD → Deploy stored procedures
  ├─ Step 3: EXEC usp_transform_staging_to_star → star schema
  ├─ Step 4: EXEC usp_validate_star_schema
  ├─ Step 5: Python → train_model.py → machine_learning/model.pkl
  ├─ Step 6: Python → generate_predictions.py → dbo.fact_predictions
  └─ Step 7: EXEC usp_record_pipeline_run
```

## Routes Monitored (10 active)

| Route | Category |
|---|---|
| Beirut → Dbayeh | Coastal corridor |
| Beirut → Jounieh | Coastal corridor |
| Beirut → Byblos | Coastal corridor |
| Beirut → Baabda | Inland corridor |
| Beirut → Aley | Inland corridor |
| Beirut → Tripoli | Northern corridor |
| Beirut → Zahle | Inland corridor |
| Beirut → Saida | Southern corridor |
| Saida → Tyre | Regional corridor |
| Zahle → Baalbek | Regional corridor |

## Database Schema (SQL Server — `lebanon_traffic_weather`)

```
dbo.staging_table          Raw API observations (all routes, all weather)
dbo.dim_time               Date/time attributes (Beirut timezone)
dbo.dim_route              Route metadata (origin, destination, category)
dbo.dim_location           Geographic weather observation points
dbo.dim_weather            Weather conditions per observation
dbo.fact_traffic           Historical traffic fact table (star schema)
dbo.fact_predictions       ML-generated 7-day travel time forecasts
dbo.pipeline_run_log       Audit log of every pipeline execution
```

## Project Structure

```
lebanon-traffic-weather-monitor/
├── run_pipeline.bat              ← Double-click to run the full pipeline
├── verify_setup.py               ← Environment health check
├── data_pipeline/
│   ├── multi_route_cached.py     ← Main extraction script (all routes)
│   ├── single_route_extract.py   ← Single-route + data quality validation
│   ├── requirements.txt          ← Python dependencies
│   └── config/
│       ├── lebanon_config.py     ← Routes and weather station definitions
│       └── settings.py           ← Environment loader
├── database/
│   ├── 01_create_database.sql
│   ├── 02_create_staging.sql
│   ├── 03_create_dimensions.sql
│   ├── 04_create_fact.sql
│   ├── 05_transform.sql          ← usp_transform_staging_to_star
│   ├── 06_validation.sql         ← usp_validate_star_schema
│   ├── 07_add_data_quality_column.sql
│   ├── 08_create_and_populate_dim_time.sql
│   ├── 10_create_pipeline_run_log.sql
│   ├── 11_scheduler_setup.sql
│   └── 12_create_fact_predictions.sql  ← ML prediction storage
├── machine_learning/
│   ├── train_model.py            ← RandomForest trainer (time-ordered split)
│   └── generate_predictions.py   ← 7-day forecast generator
├── automation/
│   ├── schedule_pipeline.xml     ← Task Scheduler job (every 15 min)
│   └── install_schedule.bat      ← Register task (run as Administrator)
└── powerbi/
    ├── connection_guide.md        ← Step-by-step Power BI setup
    └── dax_measures.md            ← All DAX measures for 5 dashboard pages
```

## Automation

Run the pipeline automatically every 15 minutes using Windows Task Scheduler:

```batch
:: Right-click and choose "Run as administrator":
automation\install_schedule.bat
```

This registers a task called `LebanonTrafficMonitor` that starts at 07:00 every day
and repeats every 15 minutes. Manage it in **Task Scheduler → Task Scheduler Library**.

## Power BI Dashboard (5 pages)

| Page | Description |
|---|---|
| Executive KPIs | KPI cards, delay trend, route ranking |
| Route Heatmap | Congestion matrix (route × hour), map visual |
| Weather Correlation | Delay vs. temperature/rain scatter plots |
| Time-of-Day Analysis | Hourly travel time patterns, peak analysis |
| 7-Day Predictions | ML forecast vs. historical average |

See [`powerbi/connection_guide.md`](powerbi/connection_guide.md) for setup steps
and [`powerbi/dax_measures.md`](powerbi/dax_measures.md) for all DAX measures.

## ML Model

The RandomForest model is trained on historical `fact_traffic` data using features:
`route_id`, `route_category`, `hour_num`, `weekend_flag`, `time_of_day_category`,
`day_name`, `month_num`, `weather_category`, `temperature`, `humidity`,
`wind_speed`, `cloud_coverage`.

Minimum 50 rows required to train. The `.bat` file skips training gracefully
and tries again on the next run when more data is collected.

Model artefacts: `machine_learning/model.pkl` + `machine_learning/model.json`

## Project Rules

- Python handles extraction and raw ingestion only.
- SQL Server handles all cleaning, transformation, and dimensional loading.
- All timestamps stored as UTC; Beirut time (`Asia/Beirut`) used in reporting only.
- Weather-traffic associations are observational — not presented as causal.
- Mock mode available for testing without API keys: `python data_pipeline\multi_route_cached.py --mock`
