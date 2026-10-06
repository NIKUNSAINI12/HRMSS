-- ============================================================================
-- CJ DARCL Recruitment Architecture: Company-Specific Master Data & Employees
-- Stored Procedure: dbo.usp_REC_GetRequisitionMasterData
-- Strictly Filters Department, Location, Designation, and Employees by CompanyId
-- ============================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetRequisitionMasterData
    @UserId    NVARCHAR(50)  = NULL,
    @LoginName NVARCHAR(100) = NULL,
    @CompanyId NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Dynamically resolve @CompanyId from user session if not passed explicitly
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId 
        FROM dbo.UM_Users_Mst WITH (NOLOCK) 
        WHERE (@UserId IS NOT NULL AND (pk_userId = @UserId OR loginName = @UserId))
           OR (@LoginName IS NOT NULL AND (loginName = @LoginName OR email = @LoginName));
    END;

    -- 2. Normalize numeric CompanyId if needed (e.g., '1' -> 'GU-1')
    IF (@CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.SAL_Employee_Mst WHERE fk_companyId = @CompanyId)
           AND EXISTS (SELECT 1 FROM dbo.SAL_Employee_Mst WHERE fk_companyId = 'GU-' + @CompanyId)
        BEGIN
            SET @CompanyId = 'GU-' + @CompanyId;
        END;
    END;

    -- 3. Fallback to active system company if still unresolved
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId FROM dbo.UM_Users_Mst WITH (NOLOCK) WHERE pk_userId = 'GU-1';
    END;

    -- ── 1. Departments (Strictly Company-Specific) ───────────────────────────
    SELECT 
        pk_deptid   AS id, 
        description AS name 
    FROM dbo.Department_Mst 
    WHERE dep_active = 1 
      AND (fk_companyId = @CompanyId OR fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY description;

    -- ── 2. Locations with Capacity & Buffer Metrics (Strictly Company-Specific)
    SELECT 
        l.pk_locid AS id, 
        l.locname  AS name, 
        ISNULL(l.locationCode, l.code) AS code, 
        ISNULL(z.zoneDescription, 'General Zone') AS zone, 
        ISNULL(l.BaseDemand, 100) AS baseDemand, 
        ISNULL(l.BufferPercent, 10.00) AS bufferPercent, 
        ISNULL(l.BufferHeads, 10) AS bufferHeads, 
        ISNULL(l.TargetCapacity, 110) AS targetCapacity,
        ISNULL((SELECT COUNT(1) FROM dbo.SAL_Employee_Mst e WHERE e.fk_locid = l.pk_locid), 0) AS currentOccupied
    FROM dbo.Location_Mst l
    LEFT JOIN dbo.SAL_Zone_Mst z ON z.pk_zoneId = l.fk_zoneId
    WHERE (l.fk_companyId = @CompanyId OR l.fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY l.locname;

    -- ── 3. Designations (Strictly Company-Specific) ──────────────────────────
    SELECT 
        pk_desgid   AS id, 
        designation AS name 
    FROM dbo.SAL_Designation_Mst 
    WHERE isActive = 1 
      AND (fk_companyId = @CompanyId OR fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY designation;

    -- ── 4. Employees for Hiring Panel & Approvers (Strictly Company-Specific) 
    SELECT 
        e.pk_empid AS id, 
        e.empname  AS name, 
        e.empcode  AS code,
        ISNULL((SELECT TOP 1 des.designation FROM dbo.SAL_Designation_Mst des WHERE des.pk_desgid = e.fk_desgid), 'Reviewer') AS extra
    FROM dbo.SAL_Employee_Mst e
    WHERE (e.fk_companyId = @CompanyId OR e.fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
      AND ISNULL(e.employeeleftstatus, 'N') = 'N'
    ORDER BY e.empname;

    -- ── 5. User Default Location (Tier 1 -> Tier 2 -> Empty) ─────────────────
    DECLARE @DefaultLocId   NVARCHAR(50)  = NULL;
    DECLARE @DefaultLocName NVARCHAR(200) = NULL;

    IF (@UserId IS NOT NULL AND RTRIM(LTRIM(@UserId)) <> '') OR (@LoginName IS NOT NULL AND RTRIM(LTRIM(@LoginName)) <> '')
    BEGIN
        SELECT TOP 1 
            @DefaultLocId   = l.pk_locid, 
            @DefaultLocName = l.locname
        FROM dbo.UM_Users_Mst u
        INNER JOIN dbo.SAL_Employee_Mst e ON e.pk_empid = u.fk_empId
        INNER JOIN dbo.Location_Mst l     ON l.pk_locid = e.fk_locid
        WHERE 
            (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId OR e.empcode = @UserId OR CAST(e.pk_empid AS NVARCHAR(50)) = @UserId))
            OR
            (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR e.empcode = @LoginName OR u.email = @LoginName));

        IF @DefaultLocId IS NULL
        BEGIN
            SELECT TOP 1 
                @DefaultLocId   = l.pk_locid, 
                @DefaultLocName = l.locname
            FROM dbo.UM_Users_Mst u
            INNER JOIN dbo.Location_Mst l ON (l.fk_companyId = u.fk_companyId OR l.fk_companyId = @CompanyId)
            WHERE 
                (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId))
                OR
                (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR u.email = @LoginName))
            ORDER BY l.pk_locid;
        END
    END

    SELECT 
        @DefaultLocId   AS defaultLocationId, 
        @DefaultLocName AS defaultLocationName;
END;
GO
