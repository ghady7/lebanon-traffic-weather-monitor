USE [lebanon_traffic_weather];
GO

-- 13_backfill_dim_route_metadata.sql
-- Backfills dim_route.route_category and dim_route.region from the canonical
-- Lebanon route configuration (values that the ETL transform does not carry
-- from staging because staging_table does not store route_category/region).
-- Safe to re-run (idempotent UPDATE).

SET NOCOUNT ON;

UPDATE dbo.dim_route SET route_category = 'Coastal corridor',  region = 'Beirut to Mount Lebanon' WHERE route_id = 'R001';
UPDATE dbo.dim_route SET route_category = 'Coastal corridor',  region = 'Beirut to Mount Lebanon' WHERE route_id = 'R002';
UPDATE dbo.dim_route SET route_category = 'Coastal corridor',  region = 'Beirut to Mount Lebanon' WHERE route_id = 'R003';
UPDATE dbo.dim_route SET route_category = 'Inland corridor',   region = 'Beirut to Mount Lebanon' WHERE route_id = 'R004';
UPDATE dbo.dim_route SET route_category = 'Inland corridor',   region = 'Beirut to Mount Lebanon' WHERE route_id = 'R005';
UPDATE dbo.dim_route SET route_category = 'Northern corridor', region = 'Beirut to North Lebanon' WHERE route_id = 'R006';
UPDATE dbo.dim_route SET route_category = 'Inland corridor',   region = 'Beirut to Bekaa'         WHERE route_id = 'R007';
UPDATE dbo.dim_route SET route_category = 'Southern corridor', region = 'Beirut to South Lebanon' WHERE route_id = 'R008';
UPDATE dbo.dim_route SET route_category = 'Regional corridor', region = 'South Lebanon'           WHERE route_id = 'R009';
UPDATE dbo.dim_route SET route_category = 'Regional corridor', region = 'Bekaa'                   WHERE route_id = 'R010';

SELECT route_id, route_name, route_category, region
FROM dbo.dim_route
ORDER BY route_id;
GO

PRINT 'dim_route metadata backfill complete.';
GO
