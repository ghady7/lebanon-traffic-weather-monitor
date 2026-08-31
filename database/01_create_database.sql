USE master;
GO

IF DB_ID('lebanon_traffic_weather') IS NULL
BEGIN
    CREATE DATABASE [lebanon_traffic_weather];
END;
GO

ALTER DATABASE [lebanon_traffic_weather] SET RECOVERY SIMPLE;
GO
