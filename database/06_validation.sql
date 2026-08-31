USE [lebanon_traffic_weather];
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.usp_validate_star_schema', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_validate_star_schema;
GO

CREATE PROCEDURE dbo.usp_validate_star_schema
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 'staging_rows' AS check_name, COUNT_BIG(*) AS issue_count
    FROM dbo.staging_table
    WHERE data_quality_status = 'invalid'
    UNION ALL
    SELECT 'orphan_fact_time_keys', COUNT_BIG(*)
    FROM dbo.fact_traffic AS f
    LEFT JOIN dbo.dim_time AS d ON d.time_key = f.time_key
    WHERE d.time_key IS NULL
    UNION ALL
    SELECT 'orphan_fact_location_keys', COUNT_BIG(*)
    FROM dbo.fact_traffic AS f
    LEFT JOIN dbo.dim_location AS d ON d.location_key = f.location_key
    WHERE d.location_key IS NULL
    UNION ALL
    SELECT 'orphan_fact_route_keys', COUNT_BIG(*)
    FROM dbo.fact_traffic AS f
    LEFT JOIN dbo.dim_route AS d ON d.route_key = f.route_key
    WHERE d.route_key IS NULL
    UNION ALL
    SELECT 'negative_fact_measures', COUNT_BIG(*)
    FROM dbo.fact_traffic
    WHERE route_distance_km < 0
       OR travel_time_minutes < 0
       OR no_traffic_travel_time_minutes < 0
       OR traffic_delay_minutes < 0
    UNION ALL
    SELECT 'duplicate_source_staging_rows', COUNT_BIG(*)
    FROM (
        SELECT source_staging_record_id
        FROM dbo.fact_traffic
        GROUP BY source_staging_record_id
        HAVING COUNT(*) > 1
    ) AS duplicates;
END;
GO

PRINT 'Created dbo.usp_validate_star_schema.';
GO
