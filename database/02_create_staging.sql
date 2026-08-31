USE [lebanon_traffic_weather];
GO

IF OBJECT_ID(N'dbo.staging_table', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.staging_table (
        staging_record_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ingestion_timestamp DATETIME2 NOT NULL CONSTRAINT DF_staging_ingestion_timestamp DEFAULT SYSUTCDATETIME(),
        pipeline_run_id NVARCHAR(100) NULL,
        route_id NVARCHAR(50) NOT NULL,
        route_name NVARCHAR(255) NULL,
        origin_name NVARCHAR(255) NULL,
        destination_name NVARCHAR(255) NULL,
        origin_latitude DECIMAL(9,6) NULL,
        origin_longitude DECIMAL(9,6) NULL,
        destination_latitude DECIMAL(9,6) NULL,
        destination_longitude DECIMAL(9,6) NULL,
        weather_location_id NVARCHAR(50) NULL,
        weather_location_name NVARCHAR(255) NULL,
        weather_latitude DECIMAL(9,6) NULL,
        weather_longitude DECIMAL(9,6) NULL,
        route_distance_meters BIGINT NULL,
        route_distance_km DECIMAL(10,2) NULL,
        travel_time_seconds INT NULL,
        no_traffic_travel_time_seconds INT NULL,
        traffic_delay_seconds INT NULL,
        departure_timestamp DATETIME2 NULL,
        arrival_timestamp DATETIME2 NULL,
        weather_observation_timestamp DATETIME2 NULL,
        temperature DECIMAL(6,2) NULL,
        feels_like_temperature DECIMAL(6,2) NULL,
        humidity INT NULL,
        pressure INT NULL,
        visibility INT NULL,
        wind_speed DECIMAL(6,2) NULL,
        wind_direction INT NULL,
        cloud_coverage INT NULL,
        rain_1h DECIMAL(8,2) NULL,
        snow_1h DECIMAL(8,2) NULL,
        weather_id INT NULL,
        weather_main NVARCHAR(100) NULL,
        weather_description NVARCHAR(255) NULL,
        raw_tomtom_payload NVARCHAR(MAX) NULL,
        raw_openweather_payload NVARCHAR(MAX) NULL,
        source_system NVARCHAR(100) NOT NULL CONSTRAINT DF_staging_source_system DEFAULT 'TomTom+OpenWeather',
        data_quality_status NVARCHAR(50) NULL CONSTRAINT DF_staging_data_quality_status DEFAULT 'raw'
    );
END;
GO

CREATE INDEX IX_staging_route_id_timestamp
ON dbo.staging_table (route_id, weather_observation_timestamp);
GO
