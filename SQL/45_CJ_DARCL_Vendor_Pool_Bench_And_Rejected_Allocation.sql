-- ============================================================================
-- SCRIPT: 45_CJ_DARCL_Vendor_Pool_Bench_And_Rejected_Allocation.sql
-- DESCRIPTION:
--   1. Create dbo.usp_REC_GetVendorPoolCandidates:
--      Fetches candidates eligible for re-pooling from a vendor's talent pool:
--      STRICTLY Bench candidates (unassigned) and Previously Rejected candidates.
--      Excludes active in-process candidates. Supports search by Aadhaar, Mobile, Name.
--   2. Create dbo.usp_REC_AssignBenchCandidatesToJob:
--      Assigns / re-pools selected candidates from Bench / Rejected pool to
--      an active Job Requisition, resetting rejection flags and logging audit trail.
-- DATABASE   : HRBook_22
-- STANDARD   : 100% Company-Specific, Zero Hardcoding, Mandatory SQL Tracking
-- ============================================================================

USE [HRBook_22]
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Create dbo.usp_REC_GetVendorPoolCandidates
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPoolCandidates
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL,
    @TargetReqId BIGINT       = NULL,
    @SearchQuery NVARCHAR(150) = NULL,
    @PoolFilter  NVARCHAR(50) = 'ALL'   -- 'ALL' | 'BENCH' | 'REJECTED'
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @VendorId = LTRIM(RTRIM(ISNULL(@VendorId, '')));
    SET @SearchQuery = NULLIF(LTRIM(RTRIM(@SearchQuery)), '');
    SET @PoolFilter = UPPER(LTRIM(RTRIM(ISNULL(@PoolFilter, 'ALL'))));

    -- Dynamic company resolution from Job Requisition if not explicitly supplied
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0') AND @TargetReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @TargetReqId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ISNULL(ca.SkillClassification, 'Semi-Skilled')                   AS skillClassification,
        ca.CurrentLocation                                               AS location,
        ISNULL(ca.IsRejected, 0)                                         AS isRejected,
        ca.RejectionReason                                               AS rejectionReason,
        ca.RejectionStage                                                AS rejectionStage,
        ca.CreatedDate                                                   AS registeredDate,
        ca.LastUpdatedDate                                               AS lastUpdatedDate,
        ca.fk_reqid                                                      AS currentReqId,
        ISNULL(ca.MrfCode, 'BENCH')                                      AS mrfCode,
        ISNULL(ca.Designation, 'Talent Pool Candidate')                  AS jobTitle,
        ISNULL(ca.Department, 'General')                                 AS department,
        ISNULL(ca.OperatingHub, 'General')                               AS hub,
        CASE 
            WHEN ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected' THEN 'REJECTED'
            ELSE 'BENCH'
        END AS poolType
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      -- 100% STRICT POOL RULE: Only Bench candidates OR Previously Rejected candidates
      AND (
          (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench')
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected')
      )
      -- Exclude if candidate is already actively assigned to this target requisition
      AND (
          @TargetReqId IS NULL 
          OR ca.fk_reqid IS NULL 
          OR ca.fk_reqid <> @TargetReqId 
          OR (ca.fk_reqid = @TargetReqId AND (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected'))
      )
      -- Filter by sub-pool tab if requested
      AND (
          @PoolFilter = 'ALL'
          OR (@PoolFilter = 'BENCH' AND (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench') AND ISNULL(ca.IsRejected, 0) = 0 AND ca.Stage <> 'Rejected')
          OR (@PoolFilter = 'REJECTED' AND (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected'))
      )
      -- Multi-field Search: Aadhaar, Phone / Mobile, Candidate Name, Application Number
      AND (
          @SearchQuery IS NULL 
          OR ca.CandidateName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Mobile LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.AadhaarNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.ApplicationNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Designation LIKE CONCAT('%', @SearchQuery, '%')
      )
    ORDER BY ca.LastUpdatedDate DESC, ca.CreatedDate DESC;
END;
GO

PRINT 'dbo.usp_REC_GetVendorPoolCandidates created/updated successfully.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Create dbo.usp_REC_AssignBenchCandidatesToJob
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_AssignBenchCandidatesToJob
    @ReqId          BIGINT,
    @VendorId       NVARCHAR(50),
    @AppIdList      NVARCHAR(MAX),  -- Comma-separated list of candidate AppIds
    @AssignedBy     NVARCHAR(100) = 'Vendor Portal',
    @CompanyId      NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @VendorId = LTRIM(RTRIM(ISNULL(@VendorId, '')));
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
    -- 3. Filter eligible candidates (Vendor owned, Bench or Rejected, not active)
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
    WHERE ca.fk_vendorId = @VendorId
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      -- Must be on Bench or Rejected
      AND (
          (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench')
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected')
      );

    DECLARE @TotalRequested INT = (SELECT COUNT(1) FROM #TargetAppIds);
    DECLARE @EligibleCount  INT = (SELECT COUNT(1) FROM #EligibleCandidates);

    IF @EligibleCount = 0
    BEGIN
        DROP TABLE #TargetAppIds;
        DROP TABLE #EligibleCandidates;
        SELECT CAST(0 AS BIT) AS Success, 
               'None of the selected candidates are eligible for assignment (they may already be in an active job pipeline or belong to another vendor).' AS Message, 
               0 AS SucceededCount, @TotalRequested AS FailedCount;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. Update Candidate Applications: Link to Job, Reset Rejection Flags
    -- ─────────────────────────────────────────────────────────────────────────
    UPDATE ca
    SET 
        ca.fk_reqid         = @ReqId,
        ca.MrfCode          = @TargetMrfCode,
        ca.Designation      = @TargetJobTitle,
        ca.Department       = @TargetDeptName,
        ca.CurrentLocation  = @TargetLocName,
        ca.OperatingHub     = @TargetLocName,
        ca.Stage            = 'Applied',
        ca.InterviewStatus  = 'Pending',
        ca.IsRejected       = 0,                -- Clear rejection state
        ca.RejectionReason  = NULL,             -- Clear rejection reason
        ca.RejectionStage   = NULL,
        ca.LastUpdatedBy    = @AssignedBy,
        ca.LastUpdatedDate  = GETDATE()
    FROM dbo.REC_Candidate_Applications ca
    INNER JOIN #EligibleCandidates e ON e.AppId = ca.pk_appId;

    -- ─────────────────────────────────────────────────────────────────────────
    -- 5. Audit Logging for each assigned candidate
    -- ─────────────────────────────────────────────────────────────────────────
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    )
    SELECT 
        e.AppId,
        e.ApplicationNo,
        'VENDOR_POOL_ALLOCATION',
        CASE WHEN e.WasRejected = 1 THEN 'Rejected' ELSE 'Bench' END,
        'Applied',
        @AssignedBy,
        'Vendor Partner',
        CONCAT('Assigned from vendor talent pool (', CASE WHEN e.WasRejected = 1 THEN 'Previously Rejected' ELSE 'Talent Bench' END, ') to job ', @TargetMrfCode, ' - ', @TargetJobTitle),
        GETDATE(),
        @CompanyId
    FROM #EligibleCandidates e;

    DECLARE @FailedCount INT = @TotalRequested - @EligibleCount;

    SELECT 
        CAST(1 AS BIT) AS Success,
        CONCAT('Successfully assigned ', @EligibleCount, ' candidate(s) to requisition ', @TargetMrfCode, '.') AS Message,
        @EligibleCount AS SucceededCount,
        @FailedCount AS FailedCount;

    DROP TABLE #TargetAppIds;
    DROP TABLE #EligibleCandidates;
END;
GO

PRINT 'dbo.usp_REC_AssignBenchCandidatesToJob created/updated successfully.';
GO
