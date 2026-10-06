-- =============================================================================
-- Script  : 43_CJ_DARCL_L1L2L3_USPs.sql
-- Purpose : 
--   USP A: ALTER UM_SP_InsertUserPageRights   - handle 5 new BIT columns
--   USP B: ALTER UM_SP_GetWebPagesOnUserModId - return 5 new columns
--   USP C: CREATE UM_SP_GetUserAccessRights   - new read USP for UI gating
-- DB      : HRBook_22
-- Date    : 2026-10-01
-- =============================================================================

USE HRBook_22;
GO

-- =============================================================================
-- USP A: ALTER UM_SP_InsertUserPageRights
-- Change: OPENXML WITH clause now includes 5 new columns
-- Unchanged: LocationList -> UM_UserModuleDetails block stays identical
-- =============================================================================
ALTER PROCEDURE [dbo].[UM_SP_InsertUserPageRights]
(
    @doc      varchar(Max),
    @userid   varchar(15),
    @moduleid tinyint
)
AS
DECLARE @idoc int
BEGIN
    EXEC sp_xml_preparedocument @idoc OUTPUT, @doc
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
    BEGIN TRAN
    BEGIN TRY

    -- [UNCHANGED] Delete + re-insert locations into UM_UserModuleDetails
    Delete From UM_UserModuleDetails
    Where fk_userId = @userid and fk_moduleId = @moduleid

    Insert Into UM_UserModuleDetails(fk_userId, fk_locid, fk_moduleId)
    Select @userid, fk_locid, @moduleid
    From OPENXML (@idoc, '/NewDataSet/LocationList', 2)
    WITH(fk_locid varchar(15))

    -- [UNCHANGED] Delete old page rights for this user+module
    Delete From UM_UserPageRights
    Where fk_userId = @userid
    And fk_webpageId in (Select pk_webpageId From UM_WebPage_Mst Where fk_moduleid = @moduleid)

    -- [UPDATED] Insert page rights with 5 new BIT columns
    Insert Into UM_UserPageRights(
        fk_userId,
        fk_webpageId,
        AllowAdd,
        AllowUpdate,
        AllowDelete,
        AllowView,
        L1_Access,
        L2_Access,
        L3_Access,
        CanRaiseRequisition,
        CanEditManpower
    )
    Select
        @userid,
        fk_webpageId,
        AllowAdd,
        AllowUpdate,
        AllowDelete,
        AllowView,
        ISNULL(L1_Access,           0),
        ISNULL(L2_Access,           0),
        ISNULL(L3_Access,           0),
        ISNULL(CanRaiseRequisition, 0),
        ISNULL(CanEditManpower,     0)
    From OPENXML (@idoc, '/NewDataSet/UM_UserPageRights', 2)
    WITH (
        fk_webpageId        int,
        AllowAdd            bit,
        AllowUpdate         bit,
        AllowDelete         bit,
        AllowView           bit,
        L1_Access           bit,
        L2_Access           bit,
        L3_Access           bit,
        CanRaiseRequisition bit,
        CanEditManpower     bit
    )

    COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK
        DECLARE @ErrMsg nvarchar(4000), @ErrSeverity int
        SELECT @ErrMsg = ERROR_MESSAGE(), @ErrSeverity = ERROR_SEVERITY()
        RAISERROR(@ErrMsg, @ErrSeverity, 1)
    END CATCH
    EXEC sp_xml_removedocument @idoc
END
GO

-- =============================================================================
-- USP B: ALTER UM_SP_GetWebPagesOnUserModId
-- Change: SELECT now returns 5 new BIT columns so PageRights UI pre-populates them
-- Unchanged: all existing columns, JOIN logic, IsAssigned logic
-- =============================================================================
ALTER PROCEDURE [dbo].[UM_SP_GetWebPagesOnUserModId]
(
    @fk_userId   varchar(15),
    @fk_moduleId tinyint
)
AS
BEGIN
    DECLARE @mappedalias varchar(3)
    EXEC Comm_UserRole_Alias @fk_userId, @mappedalias OUTPUT

    SELECT
        U.pk_webpageId,
        U.menucaption,
        U.webpagename,
        U.pagepath,
        U.tooltip,
        U.parentId,
        U.displayorder,
        U.activestatus,
        U.fk_moduleId,
        U.fk_pagetypeId,
        U.pagedescription,
        U.selectable,
        V.menucaption AS ParentMenu,
        CASE
            WHEN @mappedalias = 'S' THEN 1
            WHEN UR.fk_webpageId IS NOT NULL THEN 1
            ELSE 0
        END AS IsAssigned,
        -- Existing right columns
        ISNULL(UR.AllowAdd,            0) AS AllowAdd,
        ISNULL(UR.AllowUpdate,         0) AS AllowUpdate,
        ISNULL(UR.AllowDelete,         0) AS AllowDelete,
        ISNULL(UR.AllowView,           0) AS AllowView,
        -- NEW: 5 access flag columns
        ISNULL(UR.L1_Access,           0) AS L1_Access,
        ISNULL(UR.L2_Access,           0) AS L2_Access,
        ISNULL(UR.L3_Access,           0) AS L3_Access,
        ISNULL(UR.CanRaiseRequisition, 0) AS CanRaiseRequisition,
        ISNULL(UR.CanEditManpower,     0) AS CanEditManpower
    FROM UM_WebPage_Mst U
    INNER JOIN UM_WebPage_Mst V ON U.parentId = V.pk_webpageId
    LEFT JOIN UM_UserPageRights UR
           ON U.pk_webpageId = UR.fk_webpageId
          AND UR.fk_userId   = @fk_userId
    WHERE U.fk_moduleId  = @fk_moduleId
      AND U.activestatus = 1
    ORDER BY U.displayorder
END
GO

-- =============================================================================
-- USP C: CREATE UM_SP_GetUserAccessRights  (NEW)
-- Returns 2 result sets:
--   RS1: Aggregated L1/L2/L3/CanRaiseRequisition/CanEditManpower flags
--   RS2: fk_locid list from UM_UserModuleDetails (existing table, no new table)
-- Called by: Job Management, Location Manpower Headcount, Candidate Pipeline
-- =============================================================================
CREATE PROCEDURE [dbo].[UM_SP_GetUserAccessRights]
(
    @userId    varchar(15),
    @moduleId  tinyint
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Result Set 1: Aggregated access flags for the module
    -- MAX across all assigned pages: if user has the right on ANY page they get it
    SELECT
        ISNULL(MAX(CAST(UPR.L1_Access           AS INT)), 0) AS L1_Access,
        ISNULL(MAX(CAST(UPR.L2_Access           AS INT)), 0) AS L2_Access,
        ISNULL(MAX(CAST(UPR.L3_Access           AS INT)), 0) AS L3_Access,
        ISNULL(MAX(CAST(UPR.CanRaiseRequisition AS INT)), 0) AS CanRaiseRequisition,
        ISNULL(MAX(CAST(UPR.CanEditManpower     AS INT)), 0) AS CanEditManpower
    FROM dbo.UM_UserPageRights UPR
    INNER JOIN dbo.UM_WebPage_Mst WP
           ON WP.pk_webpageId = UPR.fk_webpageId
    WHERE UPR.fk_userId  = @userId
      AND WP.fk_moduleId = @moduleId;

    -- Result Set 2: User assigned location IDs for this module
    -- Reading from EXISTING UM_UserModuleDetails — no new table
    SELECT fk_locid
    FROM dbo.UM_UserModuleDetails
    WHERE fk_userId   = @userId
      AND fk_moduleId = @moduleId;
END
GO
