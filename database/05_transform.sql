USE [lebanon_traffic_weather];
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.usp_transform_staging_to_star', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_transform_staging_to_star;
GO

CREATE PROCEDURE dbo.usp_transform_staging_to_star
    @only_valid_rows BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.dim_time (
        full_datetime, full_date, year_num, quarter_num, month_num, month_name,
        week_of_year, day_of_month, day_name, hour_num, minute_num, weekend_flag,
        time_of_day_category
    )
    SELECT DISTINCT
        s.departure_timestamp,
        CAST((s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time' AS DATE),
        DATEPART(year, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(quarter, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(month, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATENAME(month, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(iso_week, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(day, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATENAME(weekday, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(hour, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        DATEPART(minute, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time'),
        CASE WHEN DATENAME(weekday, (s.departure_timestamp AT TIME ZONE 'UTC')
            AT TIME ZONE 'Middle East Standard Time') IN ('Friday', 'Saturday') THEN 1 ELSE 0 END,
        CASE
            WHEN DATEPART(hour, (s.departure_timestamp AT TIME ZONE 'UTC')
                AT TIME ZONE 'Middle East Standard Time') BETWEEN 7 AND 9 THEN 'Morning Peak'
            WHEN DATEPART(hour, (s.departure_timestamp AT TIME ZONE 'UTC')
                AT TIME ZONE 'Middle East Standard Time') BETWEEN 16 AND 18 THEN 'Evening Peak'
            WHEN DATEPART(hour, (s.departure_timestamp AT TIME ZONE 'UTC')
                AT TIME ZONE 'Middle East Standard Time') BETWEEN 10 AND 15 THEN 'Midday'
            ELSE 'Off-Peak'
        END
    FROM dbo.staging_table AS s
    WHERE s.departure_timestamp IS NOT NULL
      AND (@only_valid_rows = 0 OR s.data_quality_status = 'valid')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.dim_time AS d
          WHERE d.full_datetime = s.departure_timestamp
      );

    INSERT INTO dbo.dim_location (
        location_id, location_name, latitude, longitude, region, city, governorate
    )
    SELECT DISTINCT
        s.weather_location_id,
        s.weather_location_name,
        s.weather_latitude,
        s.weather_longitude,
        NULL, NULL, NULL
    FROM dbo.staging_table AS s
    WHERE s.weather_location_id IS NOT NULL
      AND (@only_valid_rows = 0 OR s.data_quality_status = 'valid')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.dim_location AS d
          WHERE d.location_id = s.weather_location_id
      );

    INSERT INTO dbo.dim_route (
        route_id, route_name, origin_name, destination_name,
        origin_latitude, origin_longitude, destination_latitude, destination_longitude,
        region, route_category
    )
    SELECT DISTINCT
        s.route_id, s.route_name, s.origin_name, s.destination_name,
        s.origin_latitude, s.origin_longitude, s.destination_latitude, s.destination_longitude,
        NULL, NULL
    FROM dbo.staging_table AS s
    WHERE s.route_id IS NOT NULL
      AND (@only_valid_rows = 0 OR s.data_quality_status = 'valid')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.dim_route AS d
          WHERE d.route_id = s.route_id
      );

    INSERT INTO dbo.dim_weather (
        weather_observation_timestamp, temperature, feels_like_temperature, humidity,
        pressure, visibility, wind_speed, wind_direction, cloud_coverage, rain_1h,
        snow_1h, weather_id, weather_main, weather_description, weather_category
    )
    SELECT DISTINCT
        s.weather_observation_timestamp, s.temperature, s.feels_like_temperature, s.humidity,
        s.pressure, s.visibility, s.wind_speed, s.wind_direction, s.cloud_coverage, s.rain_1h,
        s.snow_1h, s.weather_id, s.weather_main, s.weather_description,
        CASE
            WHEN LOWER(ISNULL(s.weather_main, '')) IN ('rain', 'drizzle', 'thunderstorm') THEN 'Rain'
            WHEN LOWER(ISNULL(s.weather_main, '')) IN ('clear') THEN 'Clear'
            WHEN LOWER(ISNULL(s.weather_main, '')) IN ('clouds') THEN 'Cloudy'
            WHEN LOWER(ISNULL(s.weather_main, '')) IN ('snow') THEN 'Snow'
            ELSE 'Other'
        END
    FROM dbo.staging_table AS s
    WHERE s.weather_observation_timestamp IS NOT NULL
      AND (@only_valid_rows = 0 OR s.data_quality_status = 'valid')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.dim_weather AS d
          WHERE d.weather_observation_timestamp = s.weather_observation_timestamp
            AND ISNULL(d.weather_id, -1) = ISNULL(s.weather_id, -1)
            AND ISNULL(d.weather_main, '') = ISNULL(s.weather_main, '')
            AND ISNULL(d.weather_description, '') = ISNULL(s.weather_description, '')
      );

    INSERT INTO dbo.fact_traffic (
        time_key, location_key, route_key, weather_key, traffic_observation_timestamp,
        route_distance_km, travel_time_minutes, no_traffic_travel_time_minutes,
        traffic_delay_minutes, congestion_pct, average_speed_kmh, source_staging_record_id
    )
    SELECT
        dt.time_key,
        dl.location_key,
        dr.route_key,
        dw.weather_key,
        s.departure_timestamp,
        s.route_distance_km,
        s.travel_time_seconds / 60.0,
        s.no_traffic_travel_time_seconds / 60.0,
        s.traffic_delay_seconds / 60.0,
        CASE WHEN s.no_traffic_travel_time_seconds > 0
             THEN 100.0 * s.traffic_delay_seconds / s.no_traffic_travel_time_seconds END,
        CASE WHEN s.travel_time_seconds > 0
             THEN s.route_distance_km * 3600.0 / (s.travel_time_seconds / 60.0) END,
        s.staging_record_id
    FROM dbo.staging_table AS s
    INNER JOIN dbo.dim_time AS dt ON dt.full_datetime = s.departure_timestamp
    INNER JOIN dbo.dim_location AS dl ON dl.location_id = s.weather_location_id
    INNER JOIN dbo.dim_route AS dr ON dr.route_id = s.route_id
    LEFT JOIN dbo.dim_weather AS dw
        ON dw.weather_observation_timestamp = s.weather_observation_timestamp
       AND ISNULL(dw.weather_id, -1) = ISNULL(s.weather_id, -1)
       AND ISNULL(dw.weather_main, '') = ISNULL(s.weather_main, '')
       AND ISNULL(dw.weather_description, '') = ISNULL(s.weather_description, '')
    WHERE s.departure_timestamp IS NOT NULL
      AND (@only_valid_rows = 0 OR s.data_quality_status = 'valid')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.fact_traffic AS f
          WHERE f.source_staging_record_id = s.staging_record_id
      );

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT(*) FROM dbo.dim_time) AS dim_time_rows,
        (SELECT COUNT(*) FROM dbo.dim_location) AS dim_location_rows,
        (SELECT COUNT(*) FROM dbo.dim_route) AS dim_route_rows,
        (SELECT COUNT(*) FROM dbo.dim_weather) AS dim_weather_rows,
        (SELECT COUNT(*) FROM dbo.fact_traffic) AS fact_traffic_rows;
END;
GO

PRINT 'Created dbo.usp_transform_staging_to_star.';
GO
