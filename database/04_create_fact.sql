USE [lebanon_traffic_weather];
GO

IF OBJECT_ID(N'dbo.fact_traffic', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_traffic (
        fact_traffic_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        time_key BIGINT NOT NULL,
        location_key BIGINT NOT NULL,
        route_key BIGINT NOT NULL,
        weather_key BIGINT NULL,
        traffic_observation_timestamp DATETIME2 NOT NULL,
        route_distance_km DECIMAL(10,2) NOT NULL,
        travel_time_minutes DECIMAL(10,2) NOT NULL,
        no_traffic_travel_time_minutes DECIMAL(10,2) NOT NULL,
        traffic_delay_minutes DECIMAL(10,2) NOT NULL,
        congestion_pct DECIMAL(10,4) NOT NULL,
        average_speed_kmh DECIMAL(10,2) NOT NULL,
        source_staging_record_id BIGINT NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_fact_traffic_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_fact_traffic_time FOREIGN KEY (time_key) REFERENCES dbo.dim_time(time_key),
        CONSTRAINT FK_fact_traffic_location FOREIGN KEY (location_key) REFERENCES dbo.dim_location(location_key),
        CONSTRAINT FK_fact_traffic_route FOREIGN KEY (route_key) REFERENCES dbo.dim_route(route_key),
        CONSTRAINT FK_fact_traffic_weather FOREIGN KEY (weather_key) REFERENCES dbo.dim_weather(weather_key),
        CONSTRAINT UQ_fact_traffic_source UNIQUE(route_key, traffic_observation_timestamp, source_staging_record_id)
    );
END;
GO
