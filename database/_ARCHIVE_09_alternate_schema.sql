-- 09_create_dim_location_route_and_fact.sql
-- Creates dim_location and dim_route, and a stored procedure to load a basic fact_traffic
-- from dbo.staging_table by resolving surrogate keys. Idempotent and safe to re-run.

SET NOCOUNT ON;

-- 1) dim_location: canonical table for origins/destinations and weather observation points
IF OBJECT_ID('dbo.dim_location','U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_location (
        location_id INT IDENTITY(1,1) PRIMARY KEY,
        natural_id NVARCHAR(100) NULL, -- optional natural key (e.g., weather_location_id or configured id)
        location_name NVARCHAR(200) NULL,
        latitude FLOAT NULL,
        longitude FLOAT NULL,
        region NVARCHAR(100) NULL,
        country NVARCHAR(100) NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME()
    );
    CREATE UNIQUE INDEX ux_dim_location_natural_or_coords ON dbo.dim_location (natural_id) WHERE natural_id IS NOT NULL;
END
GO

-- 2) dim_route: canonical table for routes between locations
IF OBJECT_ID('dbo.dim_route','U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_route (
        route_sk INT IDENTITY(1,1) PRIMARY KEY,
        natural_route_id NVARCHAR(100) NULL, -- route id from config (e.g., 'R001')
        route_name NVARCHAR(200) NULL,
        origin_location_id INT NULL,
        destination_location_id INT NULL,
        typical_distance_meters FLOAT NULL,
        created_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_dim_route_origin FOREIGN KEY (origin_location_id) REFERENCES dbo.dim_location(location_id),
        CONSTRAINT fk_dim_route_destination FOREIGN KEY (destination_location_id) REFERENCES dbo.dim_location(location_id)
    );
    CREATE UNIQUE INDEX ux_dim_route_natural ON dbo.dim_route (natural_route_id) WHERE natural_route_id IS NOT NULL;
END
GO

-- 3) fact_traffic: simple fact table if not present (add columns as needed)
IF OBJECT_ID('dbo.fact_traffic','U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_traffic (
        fact_id INT IDENTITY(1,1) PRIMARY KEY,
        pipeline_run_id NVARCHAR(100) NULL,
        staging_row_unique_key NVARCHAR(200) NULL, -- business dedup key
        time_id INT NULL,
        route_sk INT NULL,
        origin_location_id INT NULL,
        destination_location_id INT NULL,
        weather_location_id INT NULL,
        travel_time_seconds FLOAT NULL,
        no_traffic_travel_time_seconds FLOAT NULL,
        traffic_delay_seconds FLOAT NULL,
        route_distance_meters FLOAT NULL,
        average_speed_kmh FLOAT NULL,
        congestion_pct FLOAT NULL,
        data_quality_status NVARCHAR(20) NULL,
        inserted_at DATETIME2 DEFAULT SYSUTCDATETIME(),
        CONSTRAINT fk_fact_time FOREIGN KEY (time_id) REFERENCES dbo.dim_time(time_id),
        CONSTRAINT fk_fact_route FOREIGN KEY (route_sk) REFERENCES dbo.dim_route(route_sk),
        CONSTRAINT fk_fact_origin FOREIGN KEY (origin_location_id) REFERENCES dbo.dim_location(location_id),
        CONSTRAINT fk_fact_destination FOREIGN KEY (destination_location_id) REFERENCES dbo.dim_location(location_id)
    );
    CREATE UNIQUE INDEX ux_fact_business_key ON dbo.fact_traffic (staging_row_unique_key) WHERE staging_row_unique_key IS NOT NULL;
END
GO

-- 4) Procedure: populate dim_location from staging_table (weather points, origins, destinations)
IF OBJECT_ID('dbo.usp_populate_dim_location','P') IS NOT NULL
    DROP PROCEDURE dbo.usp_populate_dim_location;
GO
CREATE PROCEDURE dbo.usp_populate_dim_location
AS
BEGIN
    SET NOCOUNT ON;

    -- Insert distinct weather locations present in staging_table, using weather_location_id as natural_id when available
    INSERT INTO dbo.dim_location (natural_id, location_name, latitude, longitude, region, country)
    SELECT DISTINCT
        CAST(s.weather_location_id AS NVARCHAR(100)) AS natural_id,
        s.weather_location_name AS location_name,
        TRY_CAST(s.weather_latitude AS FLOAT) AS latitude,
        TRY_CAST(s.weather_longitude AS FLOAT) AS longitude,
        NULL AS region,
        'Lebanon' AS country
    FROM dbo.staging_table s
    WHERE s.weather_location_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM dbo.dim_location d WHERE d.natural_id = CAST(s.weather_location_id AS NVARCHAR(100))
    );

    -- Insert distinct origin points (by name + coords) if not already present
    INSERT INTO dbo.dim_location (natural_id, location_name, latitude, longitude, region, country)
    SELECT DISTINCT
        NULL AS natural_id,
        s.origin_name AS location_name,
        TRY_CAST(s.origin_latitude AS FLOAT) AS latitude,
        TRY_CAST(s.origin_longitude AS FLOAT) AS longitude,
        NULL AS region,
        'Lebanon' AS country
    FROM dbo.staging_table s
    WHERE s.origin_name IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM dbo.dim_location d
        WHERE d.location_name = s.origin_name
          AND (d.latitude = TRY_CAST(s.origin_latitude AS FLOAT) OR (d.latitude IS NULL AND TRY_CAST(s.origin_latitude AS FLOAT) IS NULL))
          AND (d.longitude = TRY_CAST(s.origin_longitude AS FLOAT) OR (d.longitude IS NULL AND TRY_CAST(s.origin_longitude AS FLOAT) IS NULL))
    );

    -- Insert distinct destination points
    INSERT INTO dbo.dim_location (natural_id, location_name, latitude, longitude, region, country)
    SELECT DISTINCT
        NULL AS natural_id,
        s.destination_name AS location_name,
        TRY_CAST(s.destination_latitude AS FLOAT) AS latitude,
        TRY_CAST(s.destination_longitude AS FLOAT) AS longitude,
        NULL AS region,
        'Lebanon' AS country
    FROM dbo.staging_table s
    WHERE s.destination_name IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM dbo.dim_location d
        WHERE d.location_name = s.destination_name
          AND (d.latitude = TRY_CAST(s.destination_latitude AS FLOAT) OR (d.latitude IS NULL AND TRY_CAST(s.destination_latitude AS FLOAT) IS NULL))
          AND (d.longitude = TRY_CAST(s.destination_longitude AS FLOAT) OR (d.longitude IS NULL AND TRY_CAST(s.destination_longitude AS FLOAT) IS NULL))
    );

    -- Return number of locations
    SELECT COUNT(*) AS locations_total FROM dbo.dim_location;
END
GO

-- 5) Procedure: populate dim_route from staging_table using natural route_id and link to dim_location
IF OBJECT_ID('dbo.usp_populate_dim_route','P') IS NOT NULL
    DROP PROCEDURE dbo.usp_populate_dim_route;
GO
CREATE PROCEDURE dbo.usp_populate_dim_route
AS
BEGIN
    SET NOCOUNT ON;

    -- Ensure locations exist first
    EXEC dbo.usp_populate_dim_location;

    -- Insert routes discovered in staging
    INSERT INTO dbo.dim_route (natural_route_id, route_name, origin_location_id, destination_location_id, typical_distance_meters)
    SELECT DISTINCT
        s.route_id AS natural_route_id,
        s.route_name AS route_name,
        ol.location_id AS origin_location_id,
        dl.location_id AS destination_location_id,
        TRY_CAST(s.route_distance_meters AS FLOAT) AS typical_distance_meters
    FROM dbo.staging_table s
    LEFT JOIN dbo.dim_route r ON r.natural_route_id = s.route_id
    LEFT JOIN dbo.dim_location ol ON ol.location_name = s.origin_name AND (ol.latitude = TRY_CAST(s.origin_latitude AS FLOAT) OR (ol.latitude IS NULL AND TRY_CAST(s.origin_latitude AS FLOAT) IS NULL)) AND (ol.longitude = TRY_CAST(s.origin_longitude AS FLOAT) OR (ol.longitude IS NULL AND TRY_CAST(s.origin_longitude AS FLOAT) IS NULL))
    LEFT JOIN dbo.dim_location dl ON dl.location_name = s.destination_name AND (dl.latitude = TRY_CAST(s.destination_latitude AS FLOAT) OR (dl.latitude IS NULL AND TRY_CAST(s.destination_latitude AS FLOAT) IS NULL)) AND (dl.longitude = TRY_CAST(s.destination_longitude AS FLOAT) OR (dl.longitude IS NULL AND TRY_CAST(s.destination_longitude AS FLOAT) IS NULL))
    WHERE s.route_id IS NOT NULL
      AND r.route_sk IS NULL; -- insert only if natural_id not present

    -- Return count of routes
    SELECT COUNT(*) AS routes_total FROM dbo.dim_route;
END
GO

-- 6) Procedure: load fact_traffic from staging_table
-- This procedure resolves time and surrogate keys and inserts only new business keys.
IF OBJECT_ID('dbo.usp_load_fact_traffic','P') IS NOT NULL
    DROP PROCEDURE dbo.usp_load_fact_traffic;
GO
CREATE PROCEDURE dbo.usp_load_fact_traffic
    @only_valid_rows BIT = 1 -- when 1, load only rows with data_quality_status = 'valid'
AS
BEGIN
    SET NOCOUNT ON;

    -- Precondition: dim_time, dim_location, dim_route should be populated. Call them defensively.
    EXEC dbo.usp_populate_dim_time; -- may be no-op if already populated
    EXEC dbo.usp_populate_dim_location;
    EXEC dbo.usp_populate_dim_route;

    ;WITH src AS (
        SELECT
            s.pipeline_run_id,
            s.route_id,
            s.route_name,
            TRY_CAST(s.departure_timestamp AS DATETIME2) AS departure_ts_utc,
            s.route_distance_meters,
            s.travel_time_seconds,
            s.no_traffic_travel_time_seconds,
            s.traffic_delay_seconds,
            s.weather_location_id,
            s.data_quality_status,
            s.origin_name,
            s.origin_latitude,
            s.origin_longitude,
            s.destination_name,
            s.destination_latitude,
            s.destination_longitude,
            CAST(CONCAT(s.pipeline_run_id, '|', s.route_id, '|', s.departure_timestamp) AS NVARCHAR(200)) AS staging_row_unique_key
        FROM dbo.staging_table s
        WHERE TRY_CAST(s.departure_timestamp AS DATETIME2) IS NOT NULL
          AND (@only_valid_rows = 0 OR (@only_valid_rows = 1 AND s.data_quality_status = 'valid'))
    ),
    -- resolve time_id by matching datetime_utc exactly (populated earlier)
    resolved AS (
        SELECT
            src.*,
            dt.time_id,
            r.route_sk,
            ol.location_id AS origin_location_id,
            dl.location_id AS destination_location_id
        FROM src
        LEFT JOIN dbo.dim_time dt ON dt.datetime_utc = src.departure_ts_utc
        LEFT JOIN dbo.dim_route r ON r.natural_route_id = src.route_id
        LEFT JOIN dbo.dim_location ol ON ol.location_name = src.origin_name AND (ol.latitude = TRY_CAST(src.origin_latitude AS FLOAT) OR (ol.latitude IS NULL AND src.origin_latitude IS NULL)) AND (ol.longitude = TRY_CAST(src.origin_longitude AS FLOAT) OR (ol.longitude IS NULL AND src.origin_longitude IS NULL))
        LEFT JOIN dbo.dim_location dl ON dl.location_name = src.destination_name AND (dl.latitude = TRY_CAST(src.destination_latitude AS FLOAT) OR (dl.latitude IS NULL AND src.destination_latitude IS NULL)) AND (dl.longitude = TRY_CAST(src.destination_longitude AS FLOAT) OR (dl.longitude IS NULL AND src.destination_longitude IS NULL))
    ),
    to_insert AS (
        SELECT
            r.pipeline_run_id,
            r.staging_row_unique_key,
            r.time_id,
            r.route_sk,
            r.origin_location_id,
            r.destination_location_id,
            TRY_CAST(r.route_distance_meters AS FLOAT) AS route_distance_meters,
            TRY_CAST(r.travel_time_seconds AS FLOAT) AS travel_time_seconds,
            TRY_CAST(r.no_traffic_travel_time_seconds AS FLOAT) AS no_traffic_travel_time_seconds,
            TRY_CAST(r.traffic_delay_seconds AS FLOAT) AS traffic_delay_seconds,
            r.data_quality_status
        FROM resolved r
        WHERE r.staging_row_unique_key IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM dbo.fact_traffic f WHERE f.staging_row_unique_key = r.staging_row_unique_key
          )
    )
    INSERT INTO dbo.fact_traffic (
        pipeline_run_id,
        staging_row_unique_key,
        time_id,
        route_sk,
        origin_location_id,
        destination_location_id,
        route_distance_meters,
        travel_time_seconds,
        no_traffic_travel_time_seconds,
        traffic_delay_seconds,
        average_speed_kmh,
        congestion_pct,
        data_quality_status
    )
    SELECT
        ti.pipeline_run_id,
        ti.staging_row_unique_key,
        ti.time_id,
        ti.route_sk,
        ti.origin_location_id,
        ti.destination_location_id,
        ti.route_distance_meters,
        ti.travel_time_seconds,
        ti.no_traffic_travel_time_seconds,
        ti.traffic_delay_seconds,
        -- average speed (km/h) = (distance_meters / 1000) / (travel_time_seconds / 3600) => (distance_meters * 3.6) / travel_time_seconds
        CASE WHEN ti.travel_time_seconds IS NOT NULL AND ti.travel_time_seconds > 0 THEN (ti.route_distance_meters * 3.6) / ti.travel_time_seconds ELSE NULL END AS average_speed_kmh,
        -- congestion % = 100 * (travel_time - no_traffic_time) / no_traffic_time when no_traffic_time > 0
        CASE WHEN ti.no_traffic_travel_time_seconds IS NOT NULL AND ti.no_traffic_travel_time_seconds > 0 THEN 100.0 * (ti.travel_time_seconds - ti.no_traffic_travel_time_seconds) / ti.no_traffic_travel_time_seconds ELSE NULL END AS congestion_pct,
        ti.data_quality_status
    FROM to_insert ti;

    -- Return inserted count
    SELECT @@ROWCOUNT AS rows_inserted;
END
GO

-- Usage order recommendation:
-- 1) EXEC dbo.usp_populate_dim_time; -- ensure dim_time exists (created earlier)
-- 2) EXEC dbo.usp_populate_dim_location;
-- 3) EXEC dbo.usp_populate_dim_route;
-- 4) EXEC dbo.usp_load_fact_traffic; -- defaults to only_valid_rows = 1

-- End of script
