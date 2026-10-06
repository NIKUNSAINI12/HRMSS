-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture (Step 1 Master)
-- File: 09_USP_REC_GetLocationManpowerList.sql
-- Purpose: Get Company-Specific Locations with actual Manpower Base Demand,
--          Buffer %, Buffer Heads, Target Capacity, and Active Employee Count
-- Created: 2026-09-28
-- ============================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetLocationManpowerList
(
    @CompanyId VARCHAR(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        l.pk_locid AS locationId,
        l.locname  AS locationName,
        ISNULL(l.locationCode, ISNULL(l.code, 'HUB')) AS locationCode,
        ISNULL(c.cityname, ISNULL(s.description, 'Operational Hub')) AS state,
        ISNULL(z.zoneDescription, 'General Zone') AS zone,
        ISNULL(l.BaseDemand, 0) AS baseRequired,
        ISNULL(l.BufferPercent, 0.00) AS bufferPercentage,
        ISNULL(l.BufferHeads, 0) AS bufferHeadcount,
        ISNULL(l.TargetCapacity, 0) AS totalTargetCapacity,
        ISNULL((SELECT COUNT(1) FROM dbo.SAL_Employee_Mst e WITH (NOLOCK) WHERE e.fk_locid = l.pk_locid), 0) AS currentOccupied,
        l.fk_companyId AS companyId
    FROM dbo.Location_Mst l WITH (NOLOCK)
    LEFT JOIN dbo.SAL_City_Mst c WITH (NOLOCK) ON c.pk_cityid = l.fk_cityid
    LEFT JOIN dbo.SAL_State_Mst s WITH (NOLOCK) ON s.pk_stateid = l.fk_stateid
    LEFT JOIN dbo.SAL_Zone_Mst z WITH (NOLOCK) ON z.pk_zoneId = l.fk_zoneId
    WHERE (@CompanyId IS NULL OR l.fk_companyId = @CompanyId)
    ORDER BY l.locname;
END
GO
