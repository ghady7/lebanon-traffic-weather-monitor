# Power BI model and DAX

## Source

Connect Power BI to SQL Server database `lebanon_traffic_weather` and import:

- `dbo.fact_traffic`
- `dbo.dim_time`
- `dbo.dim_route`
- `dbo.dim_location`
- `dbo.dim_weather`

Create single-direction, one-to-many relationships:

| Dimension key | Fact key |
|---|---|
| dim_time[time_key] | fact_traffic[time_key] |
| dim_route[route_key] | fact_traffic[route_key] |
| dim_location[location_key] | fact_traffic[location_key] |
| dim_weather[weather_key] | fact_traffic[weather_key] |

Hide surrogate keys from report users. Use `dim_time[full_date]` as the date hierarchy.

## Starter measures

```DAX
Observation Count = COUNTROWS(fact_traffic)
Average Travel Time (min) = AVERAGE(fact_traffic[travel_time_minutes])
Average Delay (min) = AVERAGE(fact_traffic[traffic_delay_minutes])
Average Congestion (%) = AVERAGE(fact_traffic[congestion_pct])
Average Speed (km/h) = AVERAGE(fact_traffic[average_speed_kmh])
Maximum Delay (min) = MAX(fact_traffic[traffic_delay_minutes])
Severe Delay Observations =
    CALCULATE([Observation Count], fact_traffic[congestion_pct] >= 50)
```

Recommended pages: executive KPIs, route comparison, time-of-day, geography, and weather observations. Report observations as associations; do not claim weather causes traffic.
