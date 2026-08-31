# Power BI Connection Guide — Lebanon Traffic & Weather Monitor

## Step 1 — Connect to SQL Server

Open **Power BI Desktop** → **Home** → **Get Data** → **SQL Server**.

| Field | Value |
|---|---|
| Server | `localhost` |
| Database | `lebanon_traffic_weather` |
| Data Connectivity mode | **Import** (recommended for < 1 M rows) |

Click **OK** → authenticate with **Windows credentials** (Trusted Connection).

---

## Step 2 — Select Tables to Load

In the Navigator, tick all six tables:

| Table | Description |
|---|---|
| `dbo.fact_traffic` | Historical traffic observations (core fact) |
| `dbo.fact_predictions` | ML-generated 7-day travel time predictions |
| `dbo.dim_time` | Date/time dimension with Beirut time attributes |
| `dbo.dim_route` | Route metadata (name, category, origin, destination) |
| `dbo.dim_location` | Geographic locations (weather stations) |
| `dbo.dim_weather` | Weather conditions per observation |

Click **Load** (or **Transform Data** if you want to preview first).

---

## Step 3 — Set Up Relationships

Go to **Model view** (the icon on the left rail that looks like a relationship diagram).

Create the following **single-direction, one-to-many** relationships:

| From (one side) | To (many side) | Join column |
|---|---|---|
| `dim_time[time_key]` | `fact_traffic[time_key]` | time_key |
| `dim_route[route_key]` | `fact_traffic[route_key]` | route_key |
| `dim_location[location_key]` | `fact_traffic[location_key]` | location_key |
| `dim_weather[weather_key]` | `fact_traffic[weather_key]` | weather_key |
| `dim_route[route_key]` | `fact_predictions[route_key]` | route_key |

> [!TIP]
> Power BI may auto-detect these relationships. Check **Manage relationships** to confirm they are set to **Single** direction (not Both).

---

## Step 4 — Hide Surrogate Keys from Report View

In the **Data** or **Model** pane, right-click each key column below and choose **Hide in report view**:

- `dim_time[time_key]`
- `dim_route[route_key]`
- `dim_location[location_key]`
- `dim_weather[weather_key]`
- `fact_traffic[time_key]`, `fact_traffic[route_key]`, `fact_traffic[location_key]`, `fact_traffic[weather_key]`
- `fact_predictions[route_key]`, `fact_predictions[prediction_id]`

---

## Step 5 — Date Hierarchy

Use `dim_time[full_date]` as the **date hierarchy** for all time-based visuals. Power BI will auto-create Year → Quarter → Month → Day drill-down.

---

## Step 6 — Dashboard Pages (Recommended)

| Page | Title | Key Visuals |
|---|---|---|
| 1 | **Executive KPIs** | KPI cards, delay trend line, route ranking bar |
| 2 | **Route Heatmap** | Matrix (route × hour), map visual (Lebanon coords) |
| 3 | **Weather Correlation** | Scatter (temp vs delay), bar by weather category |
| 4 | **Time-of-Day Analysis** | Hourly line chart, day-of-week bar |
| 5 | **7-Day Predictions** | Forecast line chart vs. historical average |

---

## Step 7 — Scheduled Refresh (Optional — Power BI Service)

1. **Publish** the `.pbix` file to Power BI Service (Home → Publish).
2. In the Service, install the **On-Premises Data Gateway** on this PC.
3. In the dataset settings, configure **Scheduled refresh** → every 30 minutes (or 15 minutes on premium).

> [!NOTE]
> The free Power BI Service tier allows up to 8 refreshes per day. Power BI Pro / Premium allows up to 48 (every 30 min) or 48× per hour on Premium.
