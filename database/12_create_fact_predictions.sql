USE [lebanon_traffic_weather];
GO

-- 12_create_fact_predictions.sql
-- Stores ML-generated travel time predictions per route per hour.
-- Safe to re-run (idempotent).

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.fact_predictions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_predictions (
        prediction_id                   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        route_key                       BIGINT NOT NULL,
        prediction_for_datetime_utc     DATETIME2 NOT NULL,
        prediction_for_date             DATE NOT NULL,
        prediction_for_hour             INT NOT NULL,
        day_of_week                     NVARCHAR(20) NOT NULL,
        weekend_flag                    BIT NOT NULL,
        time_of_day_category            NVARCHAR(30) NOT NULL,
        predicted_travel_time_minutes   DECIMAL(10,2) NULL,
        predicted_congestion_pct        DECIMAL(10,2) NULL,
        model_version                   NVARCHAR(50) NOT NULL,
        generated_at_utc                DATETIME2 NOT NULL CONSTRAINT DF_pred_generated DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_pred_route FOREIGN KEY (route_key) REFERENCES dbo.dim_route(route_key)
    );

    -- Unique index prevents duplicate predictions for the same route/time/model version
    CREATE UNIQUE INDEX UX_fact_predictions_route_datetime
        ON dbo.fact_predictions (route_key, prediction_for_datetime_utc, model_version);

    PRINT 'Created dbo.fact_predictions.';
END
ELSE
BEGIN
    PRINT 'dbo.fact_predictions already exists — skipped.';
END
GO
