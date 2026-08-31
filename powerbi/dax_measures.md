# DAX Measures — Lebanon Traffic & Weather Monitor

Copy-paste these measures into Power BI Desktop:
**Home → New measure** (or right-click a table → New measure).
Keep all measures in a dedicated `_Measures` table for organisation.

---

## Core KPI Measures

```dax
Observation Count =
    COUNTROWS(fact_traffic)

Avg Travel Time (min) =
    AVERAGE(fact_traffic[travel_time_minutes])

Avg Delay (min) =
    AVERAGE(fact_traffic[traffic_delay_minutes])

Avg Congestion (%) =
    AVERAGE(fact_traffic[congestion_pct])

Avg Speed (km/h) =
    AVERAGE(fact_traffic[average_speed_kmh])

Max Delay (min) =
    MAX(fact_traffic[traffic_delay_minutes])

Severe Delay Observations =
    CALCULATE(
        [Observation Count],
        fact_traffic[congestion_pct] >= 50
    )

Severe Delay % =
    DIVIDE([Severe Delay Observations], [Observation Count], 0) * 100
```

---

## Time Intelligence

```dax
-- Week-over-week change in average delay
Delay WoW Change (%) =
    VAR thisWeek =
        [Avg Delay (min)]
    VAR lastWeek =
        CALCULATE(
            [Avg Delay (min)],
            DATEADD(dim_time[full_date], -7, DAY)
        )
    RETURN
        DIVIDE(thisWeek - lastWeek, lastWeek, BLANK()) * 100

-- Rolling 7-day average delay
Rolling 7-Day Avg Delay (min) =
    CALCULATE(
        [Avg Delay (min)],
        DATESINPERIOD(
            dim_time[full_date],
            LASTDATE(dim_time[full_date]),
            -7,
            DAY
        )
    )

-- Peak-hour observations (Morning 7–9 or Evening 16–18)
Peak Hour Observations =
    CALCULATE(
        [Observation Count],
        dim_time[time_of_day_category] IN {"Morning Peak", "Evening Peak"}
    )
```

---

## Route & Congestion Analysis

```dax
-- Congestion index: ratio of actual travel time to free-flow baseline
Congestion Index =
    DIVIDE(
        [Avg Travel Time (min)],
        AVERAGE(fact_traffic[no_traffic_travel_time_minutes]),
        1
    )

-- Worst route by average delay (returns route name as text)
Worst Route by Delay =
    FIRSTNONBLANK(
        TOPN(1,
            VALUES(dim_route[route_name]),
            CALCULATE([Avg Delay (min)]),
            DESC
        ),
        1
    )

-- Route ranking (use in a table visual with route_name)
Route Delay Rank =
    RANKX(
        ALL(dim_route[route_name]),
        [Avg Delay (min)],
        ,
        DESC,
        DENSE
    )
```

---

## Weather Correlation Measures

```dax
-- Average delay when it rains vs. overall average
Rain Delay Premium (min) =
    VAR rainDelay =
        CALCULATE([Avg Delay (min)], dim_weather[weather_category] = "Rain")
    VAR allDelay  = [Avg Delay (min)]
    RETURN rainDelay - allDelay

-- Percentage of observations under each weather category
Weather Category % =
    DIVIDE(
        [Observation Count],
        CALCULATE([Observation Count], ALL(dim_weather[weather_category])),
        0
    ) * 100
```

---

## Prediction Measures (Page 5 — 7-Day Forecast)

```dax
Predicted Travel Time (min) =
    AVERAGE(fact_predictions[predicted_travel_time_minutes])

-- Gap between prediction and actual (positive = prediction was too high)
Prediction vs Actual Delta (min) =
    [Predicted Travel Time (min)] - [Avg Travel Time (min)]

-- Latest model version currently in the predictions table
Active Model Version =
    LASTNONBLANKVALUE(
        fact_predictions[model_version],
        [Predicted Travel Time (min)]
    )

-- Count of future prediction rows (for card visual on predictions page)
Prediction Rows =
    COUNTROWS(fact_predictions)
```

---

## Page Filter Suggestions

| Page | Recommended Slicers |
|---|---|
| Executive KPIs | Date range (`dim_time[full_date]`), Route (`dim_route[route_name]`) |
| Route Heatmap | Day type (`dim_time[weekend_flag]`), Time category (`dim_time[time_of_day_category]`) |
| Weather Correlation | Weather category (`dim_weather[weather_category]`), Route |
| Time-of-Day | Route, Month (`dim_time[month_name]`) |
| 7-Day Predictions | Route, Day of week (`fact_predictions[day_of_week]`) |

---

> [!NOTE]
> Do not label weather-traffic associations as causal in dashboard titles or tooltips.
> Use language like "Avg delay during rain conditions" rather than "Rain causes delays."
