-- =============================================================================
-- Migration 49: Reset Candidate State to Fresh / New When Reallocated from Pool
-- Standard: CJ DARCL 16-Step Flow, 100% Company-Specific, Zero Hardcoding
-- Issue:
--   When allocating previously rejected candidates from candidate pool (bench/rejected)
--   to a target job requisition, ca.InterviewStatus was retained as 'Rejected',
--   causing candidate to be tagged and locked as 'Rejected' instead of starting fresh as 'New'.
-- Fix:
--   1. Reset ca.InterviewStatus = 'Pending', ca.Stage = 'Applied', ca.IsRejected = 0,
--      and wipe out all prior interview, doc review, and rejection residue.
--   2. Update registration duplicate check to allow re-registering previously rejected
--      profiles into a new requisition as fresh candidates (preventing false auto-rejection).
--   3. Clean existing affected records in REC_Candidate_Applications.
-- =============================================================================

USE HRBook_22;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. usp_REC_AssignBenchCandidatesToJob
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_AssignBenchCandidatesToJob
    @ReqId          BIGINT,
    @VendorId       NVARCHAR(50)  = NULL,
    @AppIdList      NVARCHAR(MAX),
    @CompanyId      NVARCHAR(50),
    @AssignedBy     NVARCHAR(100) = 'Recruiter'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Clean & normalize inputs
    SET @CompanyId = NULLIF(LTRIM(RTRIM(@CompanyId)), '');
    SET @VendorId  = NULLIF(LTRIM(RTRIM(@VendorId)), '');
    SET @AppIdList = LTRIM(RTRIM(ISNULL(@AppIdList, '')));

    IF @ReqId IS NULL OR @ReqId = 0 OR @AppIdList = ''
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'Target Requisition ID and at least one Candidate Application ID are required.' AS Message,
               0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    -- Retrieve target requisition metadata
    DECLARE @TargetMrfCode   NVARCHAR(100);
    DECLARE @TargetJobTitle  NVARCHAR(200);
    DECLARE @TargetDeptName  NVARCHAR(150);
    DECLARE @TargetLocName   NVARCHAR(150);
    DECLARE @ReqWorkflowStat NVARCHAR(50);
    DECLARE @TargetCompanyId NVARCHAR(50);

    SELECT 
        @TargetMrfCode   = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @TargetJobTitle  = r.jobtitle,
        @TargetDeptName  = ISNULL(dept.description, 'General'),
        @TargetLocName   = ISNULL(loc.locname, 'Hub Operations'),
        @ReqWorkflowStat = r.WorkflowStatus,
        @TargetCompanyId = COALESCE(r.CompanyId, r.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    WHERE r.pk_reqid = @ReqId
      AND (@CompanyId IS NULL OR r.CompanyId = @CompanyId OR r.fk_companyId = @CompanyId);

    IF @TargetMrfCode IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'Target job requisition not found or does not belong to authorized company.' AS Message,
               0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    -- Parse @AppIdList into temporary table
    CREATE TABLE #TargetAppIds (
        AppId BIGINT PRIMARY KEY
    );

    INSERT INTO #TargetAppIds (AppId)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT)
    FROM STRING_SPLIT(@AppIdList, ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL;

    -- Filter eligible candidates (Vendor owned if passed, Bench or Rejected, not active)
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
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected' OR ca.InterviewStatus = 'Rejected')
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

    -- Execute Transactional Re-allocation to Target Requisition as FRESH / NEW candidate
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update candidate applications to link to target job, reset rejection flags, set stage to Applied & InterviewStatus to Pending
        UPDATE ca
        SET 
            ca.fk_reqid                 = @ReqId,
            ca.MrfCode                  = @TargetMrfCode,
            ca.Designation              = @TargetJobTitle,
            ca.Department               = @TargetDeptName,
            ca.OperatingHub             = @TargetLocName,
            ca.Stage                    = 'Applied',
            ca.IsRejected               = 0,
            ca.RejectionReason          = NULL,
            ca.RejectionStage           = NULL,
            ca.RejectionRemarks         = NULL,
            ca.InterviewStatus          = 'Pending',
            ca.InterviewRound           = NULL,
            ca.InterviewDate            = NULL,
            ca.InterviewerId            = NULL,
            ca.InterviewerName          = NULL,
            ca.InterviewRemarks         = NULL,
            ca.InterviewScore           = NULL,
            ca.DocVerificationStatus    = 'Pending',
            ca.DocVerifiedBy            = NULL,
            ca.DocVerificationRemarks   = NULL,
            ca.OfferedCTC               = NULL,
            ca.OfferLetterSentDate      = NULL,
            ca.ExpectedJoiningDate      = NULL,
            ca.EmployeeCode             = NULL,
            ca.HiredDate                = NULL,
            ca.CandidateTags            = NULL,
            ca.LastUpdatedDate          = GETDATE(),
            ca.LastUpdatedBy            = @AssignedBy
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
                CONCAT('Allocated from candidate pool (', CASE WHEN ec.WasRejected = 1 THEN 'Previously Rejected' ELSE 'Talent Bench' END, ') to job ', @TargetMrfCode, ' as New Applicant by ', @AssignedBy),
                GETDATE(),
                @CompanyId,
                @CompanyId
            FROM #EligibleCandidates ec;
        END

        COMMIT TRANSACTION;

        SELECT 
            CAST(1 AS BIT) AS Success,
            CONCAT('Successfully allocated ', @EligibleCount, ' candidate(s) to ', @TargetMrfCode, ' as New Applied applicants.') AS Message,
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Clean Existing Inconsistent Records in REC_Candidate_Applications
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE dbo.REC_Candidate_Applications
SET InterviewStatus       = 'Pending',
    InterviewRound        = NULL,
    InterviewDate         = NULL,
    InterviewerId         = NULL,
    InterviewerName       = NULL,
    InterviewRemarks      = NULL,
    InterviewScore        = NULL,
    RejectionReason       = NULL,
    RejectionStage        = NULL,
    RejectionRemarks      = NULL,
    DocVerificationStatus = 'Pending',
    CandidateTags         = NULL
WHERE IsRejected = 0 
  AND Stage = 'Applied' 
  AND (InterviewStatus = 'Rejected' OR InterviewStatus IS NULL);
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. usp_REC_RegisterCandidateApplication (Allow Rejected Profiles to Re-apply as New)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidateApplication
    @ReqId           BIGINT,
    @CandidateName   NVARCHAR(150),
    @Mobile          NVARCHAR(20),
    @Email           NVARCHAR(100)  = NULL,
    @Gender          NVARCHAR(20)   = 'Male',
    @DateOfBirth     DATE           = NULL,
    @FatherName      NVARCHAR(150)  = NULL,
    @CurrentLocation NVARCHAR(150)  = NULL,
    @SourceType      NVARCHAR(50)   = 'Vendor', -- Vendor / QR_Direct
    @VendorId        NVARCHAR(50)   = NULL,
    @VendorName      NVARCHAR(150)  = NULL,
    @AadhaarNo       NVARCHAR(20)   = NULL,     -- Optional Aadhaar Card No
    @CreatedBy       NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean & normalize inputs
    SET @Mobile = LTRIM(RTRIM(ISNULL(@Mobile, '')));
    SET @AadhaarNo = NULLIF(LTRIM(RTRIM(ISNULL(@AadhaarNo, ''))), '');

    -- Verify requisition exists
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @ReqStatus NVARCHAR(50);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);

    SELECT 
        @MrfCode   = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @ReqStatus = r.WorkflowStatus,
        @Hub       = loc.locname,
        @Dept      = dept.description,
        @Desg      = des.designation
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
    BEGIN
        SELECT 0 AS Success, 0 AS IsRejected, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Generate unique Application No: APP/YEAR/XXXX
    DECLARE @NextAppNo NVARCHAR(50);
    DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
    DECLARE @MaxSeq INT = 0;

    SELECT @MaxSeq = ISNULL(MAX(CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');

    SET @NextAppNo = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Check for duplicate: Only active (non-rejected) applications in this same requisition
    -- or active hired employees in SAL_Employee_Mst are duplicates.
    -- Previously rejected profiles are permitted to re-apply as fresh applicants.
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupAadhaar BIT = 0;
    DECLARE @DupDetail NVARCHAR(250) = '';

    -- Check 1: Active application duplicate in REC_Candidate_Applications for this job
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile 
          AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId)
          AND fk_reqid = @ReqId
          AND ISNULL(IsRejected, 0) = 0
          AND Stage NOT IN ('Rejected')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already has an active application in this requisition.');
    END

    -- Check 2: Aadhaar duplicate in REC_Candidate_Applications for this job
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE AadhaarNo = @AadhaarNo 
              AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId)
              AND fk_reqid = @ReqId
              AND ISNULL(IsRejected, 0) = 0
              AND Stage NOT IN ('Rejected')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already has an active application in this requisition.');
        END
    END

    -- Check 3: Active employee in SAL_Employee_Mst (already an active hired employee)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE adhaarNo = @AadhaarNo 
              AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId = @CompanyId)
              AND ISNULL(active, 'Y') IN ('Y', '1', 'True')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists as an active employee in Employee Master.');
        END
    END

    -- IF DUPLICATE: THAT CANDIDATE SHOULD BE REJECTED
    IF @IsDuplicate = 1
    BEGIN
        DECLARE @RejectionReason NVARCHAR(150) = CASE 
            WHEN @DupAadhaar = 1 THEN 'Duplicate Aadhaar Number in Database' 
            ELSE 'Duplicate Mobile Number in Database' 
        END;

        DECLARE @RejectionRemarks NVARCHAR(MAX) = CONCAT('Auto-rejected upon registration: ', @DupDetail);

        -- Insert candidate directly into Rejected stage
        INSERT INTO dbo.REC_Candidate_Applications (
            ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
            Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
            Department, Designation, SourceType, fk_vendorId, VendorName,
            AadhaarNo, Stage, SkillClassification, InterviewStatus,
            RejectionReason, RejectionRemarks, CooloffPolicy,
            fk_companyId, CompanyId, CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
        ) VALUES (
            @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
            @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
            @Dept, @Desg, @SourceType, @VendorId, @VendorName,
            @AadhaarNo, 'Rejected', 'Unskilled', 'Rejected',
            @RejectionReason, @RejectionRemarks, '90_Days',
            @CompanyId, @CompanyId, GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
        );

        DECLARE @RejectedAppId BIGINT = SCOPE_IDENTITY();

        -- Insert audit log for auto-rejection
        INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
            fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
            ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
            CompanyId, fk_companyId
        ) VALUES (
            @RejectedAppId, @NextAppNo, 'REJECT', 'None', 'Rejected',
            @VendorId, @CreatedBy, @SourceType, 
            CONCAT('Auto-rejected upon registration: ', @DupDetail), 
            GETDATE(), @CompanyId, @CompanyId
        );

        SELECT 
            0 AS Success,
            1 AS IsRejected,
            CONCAT('Candidate Rejected: ', @DupDetail, ' Application created under Rejected status.') AS Message,
            @RejectedAppId AS appId,
            @NextAppNo AS applicationNo,
            @MrfCode AS mrfCode;

        RETURN;
    END

    -- IF NOT DUPLICATE: NORMAL SUCCESSFUL REGISTRATION AS NEW APPLIED CANDIDATE
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus, 
        IsRejected, fk_companyId, CompanyId,
        CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending',
        0, @CompanyId, @CompanyId,
        GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @VendorId, @CreatedBy, @SourceType, 
        CONCAT('Candidate registered against MRF ', @MrfCode), 
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success,
        0 AS IsRejected,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;

END;
GO
