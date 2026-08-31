USE [lebanon_traffic_weather];
GO

IF OBJECT_ID(N'dbo.dim_time', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_time (
        time_key BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        full_datetime DATETIME2 NOT NULL,
        full_date DATE NOT NULL,
        year_num INT NOT NULL,
        quarter_num INT NOT NULL,
        month_num INT NOT NULL,
        month_name NVARCHAR(20) NOT NULL,
        week_of_year INT NOT NULL,
        day_of_month INT NOT NULL,
        day_name NVARCHAR(20) NOT NULL,
        hour_num INT NOT NULL,
        minute_num INT NOT NULL,
        weekend_flag BIT NOT NULL,
        time_of_day_category NVARCHAR(30) NOT NULL,
        CONSTRAINT UQ_dim_time_full_datetime UNIQUE(full_datetime)
    );
END;
GO

IF OBJECT_ID(N'dbo.dim_location', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_location (
        location_key BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        location_id NVARCHAR(50) NOT NULL,
        location_name NVARCHAR(200) NOT NULL,
        city NVARCHAR(200) NULL,
        governorate NVARCHAR(200) NULL,
        region NVARCHAR(200) NULL,
        latitude DECIMAL(9,6) NULL,
        longitude DECIMAL(9,6) NULL,
        CONSTRAINT UQ_dim_location_id UNIQUE(location_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.dim_route', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_route (
        route_key BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        route_id NVARCHAR(50) NOT NULL,
        route_name NVARCHAR(255) NOT NULL,
        origin_name NVARCHAR(255) NOT NULL,
        destination_name NVARCHAR(255) NOT NULL,
        origin_latitude DECIMAL(9,6) NULL,
        origin_longitude DECIMAL(9,6) NULL,
        destination_latitude DECIMAL(9,6) NULL,
        destination_longitude DECIMAL(9,6) NULL,
        region NVARCHAR(200) NULL,
        route_category NVARCHAR(100) NULL,
        is_active BIT NOT NULL CONSTRAINT DF_dim_route_is_active DEFAULT 1,
        CONSTRAINT UQ_dim_route_id UNIQUE(route_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.dim_weather', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_weather (
        weather_key BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        weather_observation_timestamp DATETIME2 NOT NULL,
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
        weather_category NVARCHAR(50) NULL,
        CONSTRAINT UQ_dim_weather_signature UNIQUE(
            weather_observation_timestamp,
            temperature,
            humidity,
            pressure,
            wind_speed,
            weather_main,
            weather_description
        )
    );
END;
GO
