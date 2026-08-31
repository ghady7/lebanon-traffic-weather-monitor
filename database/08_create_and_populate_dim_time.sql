-- 08_create_and_populate_dim_time.sql
-- Creates a dim_time dimension and a stored procedure to populate it from staging timestamps.
-- Converts UTC observation timestamps to Lebanon local time using SQL Server AT TIME ZONE with the
-- Windows time zone name 'Middle East Standard Time' (covers Beirut/Lebanon DST rules).

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = 'dbo')
BEGIN
    -- assume dbo exists on user DB
END

-- Create dim_time if it does not exist
IF NOT EXISTS (
    SELECT 1 FROM sys.objects o
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE o.name = 'dim_time' AND s.name = 'dbo'
)
BEGIN
    CREATE TABLE dbo.dim_time (
        time_id INT IDENTITY(1,1) PRIMARY KEY,
        datetime_utc DATETIME2 NOT NULL,
        datetime_local DATETIME2 NOT NULL,
        date_local DATE NOT NULL,
        year INT NOT NULL,
        quarter TINYINT NOT NULL,
        month INT NOT NULL,
        month_name NVARCHAR(20) NOT NULL,
        day INT NOT NULL,
        day_of_week INT NOT NULL, -- SQL Server DATEPART(weekday): 1..7 depending on DATEFIRST
        day_name NVARCHAR(20) NOT NULL,
        hour INT NOT NULL,
        minute INT NOT NULL,
        is_weekend BIT NOT NULL,
        is_morning_peak BIT NOT NULL,
        is_evening_peak BIT NOT NULL
    );
END
GO

-- Stored procedure to populate dim_time from distinct timestamps in staging table
-- @start_utc/@end_utc are optional filters (UTC datetimes). If NULL, all timestamps are considered.
-- Uses the Windows time zone 'Middle East Standard Time' to convert to Lebanon local time.

IF OBJECT_ID('dbo.usp_populate_dim_time', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_populate_dim_time;
GO

CREATE PROCEDURE dbo.usp_populate_dim_time
    @start_utc DATETIME2 = NULL,
    @end_utc DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Collect distinct candidate UTC timestamps from staging_table. Use departure_timestamp primarily,
    -- fall back to arrival_timestamp and weather_observation_timestamp as additional time references.
    ;WITH candidates AS (
        SELECT DISTINCT TRY_CAST(departure_timestamp AS DATETIME2) AS ts_utc
        FROM dbo.staging_table
        WHERE departure_timestamp IS NOT NULL
        UNION
        SELECT DISTINCT TRY_CAST(arrival_timestamp AS DATETIME2) AS ts_utc
        FROM dbo.staging_table
        WHERE arrival_timestamp IS NOT NULL
        UNION
        SELECT DISTINCT TRY_CAST(weather_observation_timestamp AS DATETIME2) AS ts_utc
        FROM dbo.staging_table
        WHERE weather_observation_timestamp IS NOT NULL
    ),
    filtered AS (
        SELECT ts_utc FROM candidates
        WHERE ts_utc IS NOT NULL
        AND (@start_utc IS NULL OR ts_utc >= @start_utc)
        AND (@end_utc IS NULL OR ts_utc <= @end_utc)
    ),
    to_insert AS (
        SELECT DISTINCT f.ts_utc
        FROM filtered f
        LEFT JOIN dbo.dim_time d ON d.datetime_utc = f.ts_utc
        WHERE d.time_id IS NULL -- only new timestamps
    )
    INSERT INTO dbo.dim_time (
        datetime_utc,
        datetime_local,
        date_local,
        year,
        quarter,
        month,
        month_name,
        day,
        day_of_week,
        day_name,
        hour,
        minute,
        is_weekend,
        is_morning_peak,
        is_evening_peak
    )
    SELECT
        ti.ts_utc AS datetime_utc,
        -- Convert UTC -> Lebanon local time using Windows TZ 'Middle East Standard Time'
        CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2) AS datetime_local,
        CAST(CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2) AS DATE) AS date_local,
        DATEPART(year, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS year,
        DATEPART(quarter, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS quarter,
        DATEPART(month, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS month,
        DATENAME(month, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS month_name,
        DATEPART(day, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS day,
        DATEPART(weekday, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS day_of_week,
        DATENAME(weekday, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS day_name,
        DATEPART(hour, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS hour,
        DATEPART(minute, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) AS minute,
        -- Weekend heuristic: treat Friday/Saturday/Sunday as weekend if server DATEFIRST defaults otherwise; keep conservative: use day_name
        CASE WHEN DATENAME(weekday, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) IN ('Friday','Saturday') THEN 1 ELSE 0 END AS is_weekend,
        -- Peak windows (local time): morning 07:00-09:59, evening 16:00-18:59
        CASE WHEN DATEPART(hour, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) BETWEEN 7 AND 9 THEN 1 ELSE 0 END AS is_morning_peak,
        CASE WHEN DATEPART(hour, CAST((ti.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Middle East Standard Time' AS DATETIME2)) BETWEEN 16 AND 18 THEN 1 ELSE 0 END AS is_evening_peak
    FROM to_insert ti;

    -- Return basic summary
    SELECT @@ROWCOUNT AS rows_inserted;
END
GO

-- Example usage:
-- EXEC dbo.usp_populate_dim_time; -- populate from all staging timestamps
-- EXEC dbo.usp_populate_dim_time @start_utc = '2026-01-01T00:00:00', @end_utc = '2026-01-31T23:59:59';

-- End of script
