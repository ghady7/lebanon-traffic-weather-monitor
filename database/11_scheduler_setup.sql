USE [lebanon_traffic_weather];
GO

-- Run this script once after the database has been created.
-- The Windows Task Scheduler action should call:
-- C:\Users\User\Documents\Data analyst\lebanon-traffic-weather-monitor\run_pipeline.bat

IF OBJECT_ID(N'dbo.usp_pipeline_health_check', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_pipeline_health_check;
GO

CREATE PROCEDURE dbo.usp_pipeline_health_check
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (20)
        pipeline_run_log_id, pipeline_run_id, started_at_utc, finished_at_utc,
        status, mock_mode, staging_rows, fact_rows, error_message
    FROM dbo.pipeline_run_log
    ORDER BY pipeline_run_log_id DESC;
END;
GO
