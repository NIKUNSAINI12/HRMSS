-- =============================================================================
-- Migration Script 48: Fix Schema Mappings in dbo.usp_REC_AssignBenchCandidatesToJob
-- Date: 2026-10-03
-- Objective: Remove non-existent RejectionDate, PreviousReqId, NewReqId columns
--            Ensure 100% exact schema alignment with REC_Candidate_Applications
--            and REC_Candidate_Lifecycle_Audit tables.
-- =============================================================================

USE HRBook_22;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Deploying updated dbo.usp_REC_AssignBenchCandidatesToJob...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_AssignBenchCandidatesToJob
    @ReqId          BIGINT,
    @VendorId       NVARCHAR(50)  = NULL,
    @AppIdList      NVARCHAR(MAX),  -- Comma-separated list of candidate AppIds
    @AssignedBy     NVARCHAR(100) = 'HR Pipeline',
    @CompanyId      NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Clean inputs
    SET @VendorId = NULLIF(LTRIM(RTRIM(ISNULL(@VendorId, ''))), '');
    IF @VendorId = 'ALL' OR @VendorId = 'HR'
    BEGIN
        SET @VendorId = NULL;
    END

    SET @AppIdList = LTRIM(RTRIM(ISNULL(@AppIdList, '')));

    IF @ReqId IS NULL OR @ReqId = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Target Job Requisition ID is required.' AS Message, 0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    IF LEN(@AppIdList) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'No candidate IDs provided for assignment.' AS Message, 0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 1. Resolve Target Requisition Metadata
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @TargetMrfCode  NVARCHAR(50);
    DECLARE @TargetJobTitle NVARCHAR(150);
    DECLARE @TargetLocName  NVARCHAR(100);
    DECLARE @TargetDeptName NVARCHAR(100);
    DECLARE @ReqCompanyId   NVARCHAR(50);

    SELECT 
        @TargetMrfCode  = ISNULL(jm.Mrfcode, CONCAT('MRF/', jm.pk_reqid)),
        @TargetJobTitle = ISNULL(jm.jobtitle, 'Logistics Executive'),
        @TargetLocName  = ISNULL(loc.locname, 'Hub Operations'),
        @TargetDeptName = ISNULL(dept.description, 'Operations'),
        @ReqCompanyId   = COALESCE(jm.CompanyId, jm.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst jm WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = jm.fk_deptid
    WHERE jm.pk_reqid = @ReqId;

    IF @TargetMrfCode IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Target Job Requisition not found.' AS Message, 0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 2. Parse @AppIdList into temporary table
    -- ─────────────────────────────────────────────────────────────────────────
    CREATE TABLE #TargetAppIds (
        AppId BIGINT PRIMARY KEY
    );

    INSERT INTO #TargetAppIds (AppId)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT)
    FROM STRING_SPLIT(@AppIdList, ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL;

    -- ─────────────────────────────────────────────────────────────────────────
    -- 3. Filter eligible candidates (Vendor owned if passed, Bench or Rejected, not active)
    -- ─────────────────────────────────────────────────────────────────────────
    CREATE TABLE #EligibleCandidates (
        AppId           BIGINT,
        ApplicationNo   NVARCHAR(50),
        CandidateName   NVARCHAR(150),
        WasRejected     BIT,
        PreviousStage   NVARCHAR(50)
    );

    INSERT INTO #EligibleCandidates (AppId, ApplicationNo, CandidateName, WasRejected, PreviousStage)
    SELECT 
        ca.pk_appId,
        ca.ApplicationNo,
        ca.CandidateName,
        ISNULL(ca.IsRejected, 0),
        ISNULL(ca.Stage, 'Bench')
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    INNER JOIN #TargetAppIds t ON t.AppId = ca.pk_appId
    WHERE (@VendorId IS NULL OR ca.fk_vendorId = @VendorId)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      -- Must be on Bench or Rejected
      AND (
          (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench')
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected')
      );

    DECLARE @EligibleCount INT = (SELECT COUNT(1) FROM #EligibleCandidates);
    DECLARE @RequestedCount INT = (SELECT COUNT(1) FROM #TargetAppIds);

    IF @EligibleCount = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'None of the selected candidates are currently eligible for allocation (must be on Bench or Previously Rejected).' AS Message,
               0 AS SucceededCount, 
               @RequestedCount AS FailedCount;
        DROP TABLE #TargetAppIds;
        DROP TABLE #EligibleCandidates;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. Execute Transactional Re-allocation to Target Requisition
    -- ─────────────────────────────────────────────────────────────────────────
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update candidate applications to link to target job, reset rejection flags, set stage to Applied
        UPDATE ca
        SET 
            ca.fk_reqid          = @ReqId,
            ca.MrfCode           = @TargetMrfCode,
            ca.Designation       = @TargetJobTitle,
            ca.Department        = @TargetDeptName,
            ca.OperatingHub      = @TargetLocName,
            ca.Stage             = 'Applied',
            ca.IsRejected        = 0,
            ca.RejectionReason   = NULL,
            ca.RejectionStage    = NULL,
            ca.RejectionRemarks  = NULL,
            ca.LastUpdatedDate   = GETDATE(),
            ca.LastUpdatedBy     = @AssignedBy
        FROM dbo.REC_Candidate_Applications ca
        INNER JOIN #EligibleCandidates ec ON ec.AppId = ca.pk_appId;

        -- Audit Logging in REC_Candidate_Lifecycle_Audit
        IF OBJECT_ID('dbo.REC_Candidate_Lifecycle_Audit', 'U') IS NOT NULL
        BEGIN
            INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
                fk_appId,
                ApplicationNo,
                ActionType,
                PreviousStage,
                NewStage,
                ActionByUserId,
                ActionByName,
                Remarks,
                ActionDate,
                CompanyId,
                fk_companyId
            )
            SELECT 
                ec.AppId,
                ec.ApplicationNo,
                'POOL_ALLOCATION_TO_JOB',
                ec.PreviousStage,
                'Applied',
                @AssignedBy,
                @AssignedBy,
                CONCAT('Allocated from candidate pool (', CASE WHEN ec.WasRejected = 1 THEN 'Previously Rejected' ELSE 'Talent Bench' END, ') to job ', @TargetMrfCode, ' by ', @AssignedBy),
                GETDATE(),
                @CompanyId,
                @CompanyId
            FROM #EligibleCandidates ec;
        END

        COMMIT TRANSACTION;

        SELECT 
            CAST(1 AS BIT) AS Success,
            CONCAT('Successfully allocated ', @EligibleCount, ' candidate(s) to ', @TargetMrfCode, '.') AS Message,
            @EligibleCount AS SucceededCount,
            (@RequestedCount - @EligibleCount) AS FailedCount;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT 
            CAST(0 AS BIT) AS Success,
            CONCAT('Transaction failed: ', ERROR_MESSAGE()) AS Message,
            0 AS SucceededCount,
            @RequestedCount AS FailedCount;
    END CATCH;

    DROP TABLE #TargetAppIds;
    DROP TABLE #EligibleCandidates;
END;
GO

PRINT 'Migration Script 48 completed successfully.';
GO
