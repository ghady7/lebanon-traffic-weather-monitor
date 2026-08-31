USE [lebanon_traffic_weather];
GO

IF COL_LENGTH('dbo.staging_table', 'data_quality_issues') IS NULL
BEGIN
    ALTER TABLE dbo.staging_table
    ADD data_quality_issues NVARCHAR(MAX) NULL;
END;
GO

-- Update existing NULL statuses to 'raw' where empty
UPDATE dbo.staging_table
SET data_quality_status = ISNULL(data_quality_status, 'raw')
WHERE data_quality_status IS NULL;
GO
