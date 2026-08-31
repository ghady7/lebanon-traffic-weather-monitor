USE [lebanon_traffic_weather];
GO

IF OBJECT_ID(N'dbo.pipeline_run_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pipeline_run_log (
        pipeline_run_log_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        pipeline_run_id NVARCHAR(100) NULL,
        started_at_utc DATETIME2 NOT NULL CONSTRAINT DF_pipeline_run_started DEFAULT SYSUTCDATETIME(),
        finished_at_utc DATETIME2 NULL,
        status NVARCHAR(30) NOT NULL,
        mock_mode BIT NOT NULL CONSTRAINT DF_pipeline_run_mock DEFAULT 0,
        staging_rows BIGINT NULL,
        fact_rows BIGINT NULL,
        error_message NVARCHAR(MAX) NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.usp_record_pipeline_run', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_record_pipeline_run;
GO

CREATE PROCEDURE dbo.usp_record_pipeline_run
    @pipeline_run_id NVARCHAR(100),
    @status NVARCHAR(30),
    @mock_mode BIT = 0,
    @error_message NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.pipeline_run_log (
        pipeline_run_id, finished_at_utc, status, mock_mode,
        staging_rows, fact_rows, error_message
    )
    SELECT
        @pipeline_run_id, SYSUTCDATETIME(), @status, @mock_mode,
        (SELECT COUNT_BIG(*) FROM dbo.staging_table WHERE pipeline_run_id = @pipeline_run_id),
        (SELECT COUNT_BIG(*) FROM dbo.fact_traffic f
         WHERE EXISTS (
             SELECT 1 FROM dbo.staging_table s
             WHERE s.staging_record_id = f.source_staging_record_id
               AND s.pipeline_run_id = @pipeline_run_id
         )),
        @error_message;
END;
GO
