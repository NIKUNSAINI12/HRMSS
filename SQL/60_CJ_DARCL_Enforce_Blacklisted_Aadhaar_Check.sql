-- =============================================================================
-- Migration Script 60: CJ DARCL Enforce Blacklisted Aadhaar Validation
-- Description:
--   Enforces mandatory blacklisted Aadhaar check across all candidate touchpoints:
--   1. dbo.usp_REC_AssignBenchCandidatesToJob (Allocating candidate from vendor pool to pipeline page)
--   2. dbo.usp_REC_SubmitVendorCandidate (Vendor adding candidate to job / bench)
--   3. dbo.usp_REC_RegisterCandidateApplication (Pipeline Add Candidate modal)
--   4. dbo.usp_REC_SaveCandidateOnboardingDossier (Vendor / HR updating candidate details & dossier)
--   5. dbo.usp_REC_UploadCandidateDocumentItem (Docs upload for Aadhaar)
--   6. dbo.usp_REC_VerifyCandidateDocumentItem (Docs review / approval for Aadhaar)
--
-- Logic:
--   Checks against dbo.SAL_Employee_Mst where isBlacklisted = 1 and normalized Aadhaar matches.
--   If match found, abort transaction and throw descriptive error stating candidate is blacklisted.
-- =============================================================================

USE [HRBook_22];
GO

PRINT 'Deploying Migration 60: Enforce Blacklisted Aadhaar Validation across ATS Lifecycle...';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Update dbo.usp_REC_AssignBenchCandidatesToJob
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
        ApplicationNo   NVARCHAR(50) COLLATE DATABASE_DEFAULT,
        CandidateName   NVARCHAR(150) COLLATE DATABASE_DEFAULT,
        AadhaarNo       NVARCHAR(50) COLLATE DATABASE_DEFAULT,
        WasRejected     BIT,
        PreviousStage   NVARCHAR(50) COLLATE DATABASE_DEFAULT
    );

    INSERT INTO #EligibleCandidates (AppId, ApplicationNo, CandidateName, AadhaarNo, WasRejected, PreviousStage)
    SELECT 
        ca.pk_appId,
        ca.ApplicationNo,
        ca.CandidateName,
        ca.AadhaarNo,
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

    -- ─────────────────────────────────────────────────────────────────────────
    -- MANDATORY SECURITY CHECK: Blacklisted Candidate Aadhaar Verification
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @BlacklistedName NVARCHAR(150);
    DECLARE @BlacklistedAadhaar NVARCHAR(50);

    SELECT TOP 1 
        @BlacklistedName = ec.CandidateName,
        @BlacklistedAadhaar = ec.AadhaarNo
    FROM #EligibleCandidates ec
    INNER JOIN dbo.SAL_Employee_Mst e WITH (NOLOCK) ON 
        REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(e.adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ec.AadhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT
        AND (@CompanyId IS NULL OR @CompanyId = '' OR e.fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
    WHERE ISNULL(ec.AadhaarNo, '') <> ''
      AND e.isBlacklisted = 1;

    IF @BlacklistedName IS NOT NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Security Restriction: Candidate [', @BlacklistedName, '] with Aadhaar card [', @BlacklistedAadhaar, '] is blacklisted in company records and cannot be added to pipeline.') AS Message,
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
PRINT 'dbo.usp_REC_AssignBenchCandidatesToJob updated with blacklisted Aadhaar check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Update dbo.usp_REC_SubmitVendorCandidate
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitVendorCandidate
    @ReqId          BIGINT        = NULL,
    @VendorId       NVARCHAR(50),
    @VendorName     NVARCHAR(150),
    @CandidateName  NVARCHAR(150),
    @Mobile         NVARCHAR(20),
    @Email          NVARCHAR(150) = NULL,
    @Gender         NVARCHAR(20)  = 'Male',
    @DateOfBirth    DATE          = NULL,
    @FatherName     NVARCHAR(150) = NULL,
    @AadhaarNo      NVARCHAR(30)  = NULL,
    @ResumeDocPath  NVARCHAR(500) = NULL,
    @SubmittedBy    NVARCHAR(100) = 'Vendor Portal',
    @CompanyId      NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Treat 0 as NULL for ReqId (bench/unassigned)
    IF @ReqId = 0 SET @ReqId = NULL;

    -- Dynamic Company resolution from Job Requisition if not supplied
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0') AND @ReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    -- Clean inputs
    SET @CandidateName = LTRIM(RTRIM(ISNULL(@CandidateName, '')));
    SET @Mobile = REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@Mobile, ''))), ' ', ''), '-', '');
    SET @Email  = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @FatherName = NULLIF(LTRIM(RTRIM(@FatherName)), '');
    IF @AadhaarNo IS NOT NULL
        SET @AadhaarNo = REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), ' ', ''), '-', '');
    SET @AadhaarNo = NULLIF(@AadhaarNo, '');

    -- ─────────────────────────────────────────────────────────────────────────
    -- 1. Format Validations (Phone & Aadhaar)
    -- ─────────────────────────────────────────────────────────────────────────
    IF LEN(@CandidateName) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Candidate full name is mandatory.' AS Message, 0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    IF LEN(@Mobile) <> 10 OR @Mobile LIKE '%[^0-9]%' OR LEFT(@Mobile, 1) NOT IN ('6', '7', '8', '9')
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Invalid Mobile Number [', @Mobile, ']. Must be a valid 10-digit number starting with 6-9.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    IF @AadhaarNo IS NULL OR LEN(@AadhaarNo) <> 12 OR @AadhaarNo LIKE '%[^0-9]%'
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Invalid Aadhaar Number [', ISNULL(@AadhaarNo, 'EMPTY'), ']. Must be a valid 12-digit numeric Aadhaar number.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 2. MANDATORY BLACKLIST CHECK: SAL_Employee_Mst isBlacklisted = 1
    -- ─────────────────────────────────────────────────────────────────────────
    IF EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT
          AND isBlacklisted = 1
          AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Security Restriction: Candidate with Aadhaar card [', @AadhaarNo, '] is blacklisted in company employee records and cannot be added or registered.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 3. Duplicate Validations (Matching Candidate Pipeline Page Standard)
    -- ─────────────────────────────────────────────────────────────────────────
    -- Check 3a: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 3b: Mobile duplicate in REC_Candidate_Details
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE (mobile COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT OR phone COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT)
          AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Database.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 3c: Aadhaar duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE AadhaarNo COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Aadhaar card ', @AadhaarNo, ' already registered in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 3d: Aadhaar duplicate in SAL_Employee_Mst (Active Employee)
    IF EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE (adhaarNo COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT OR adhaarNo COLLATE DATABASE_DEFAULT = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
          AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
          AND ISNULL(active, 1) = 1
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Candidate with Aadhaar ', @AadhaarNo, ' is already an active employee in Company Master.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. Job Metadata Resolution & Global Unique Sequence Generation
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @MrfCode  NVARCHAR(50)  = 'BENCH';
    DECLARE @JobTitle NVARCHAR(150) = 'Talent Pool Candidate';
    DECLARE @LocName  NVARCHAR(100) = 'Talent Pool';
    DECLARE @DeptName NVARCHAR(100) = 'General';

    IF @ReqId IS NOT NULL
    BEGIN
        SELECT 
            @MrfCode  = ISNULL(jm.Mrfcode, CONCAT('MRF/', jm.pk_reqid)),
            @JobTitle = ISNULL(jm.jobtitle, 'Logistics Executive'),
            @LocName  = ISNULL(loc.locname, 'Hub Operations'),
            @DeptName = ISNULL(dept.description, 'Operations')
        FROM dbo.REC_JobRequisition_Mst jm WITH (NOLOCK)
        LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = jm.fk_locid
        LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = jm.fk_deptid
        WHERE jm.pk_reqid = @ReqId;
    END

    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    -- Global across REC_Candidate_Applications to satisfy table UNIQUE constraint on ApplicationNo
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- ─────────────────────────────────────────────────────────────────────────
    -- 5. Insert Candidate Application
    -- ─────────────────────────────────────────────────────────────────────────
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, ResumeDocPath, Stage, SkillClassification, InterviewStatus,
        fk_companyId, CompanyId, CreatedBy, CreatedDate, LastUpdatedBy, LastUpdatedDate
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @LocName, @LocName,
        @DeptName, @JobTitle, 'Vendor', @VendorId, @VendorName,
        @AadhaarNo, @ResumeDocPath, 'Applied', 'Semi-Skilled', 'Pending',
        @CompanyId, @CompanyId, @SubmittedBy, GETDATE(), @SubmittedBy, GETDATE()
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Seed 13 Standard Onboarding Document placeholders
    IF OBJECT_ID('dbo.usp_REC_SeedCandidateDocuments', 'P') IS NOT NULL
    BEGIN
        EXEC dbo.usp_REC_SeedCandidateDocuments @AppId = @NewAppId, @CompanyId = @CompanyId;
    END

    -- Log Audit Trail
    DECLARE @AuditRemarks NVARCHAR(MAX) = CASE 
        WHEN @ReqId IS NOT NULL THEN CONCAT('Candidate profile verified and submitted by vendor [', @VendorName, '] for MRF ', @MrfCode, ' (', @JobTitle, ')')
        ELSE CONCAT('Candidate profile pre-registered beforehand into Talent Bench by vendor [', @VendorName, ']')
    END;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, CASE WHEN @ReqId IS NOT NULL THEN 'VENDOR_SUBMISSION' ELSE 'VENDOR_BENCH_REGISTRATION' END, 
        'None', 'Applied',
        @SubmittedBy, 'Vendor Partner',
        @AuditRemarks,
        GETDATE(), @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success, 
        CASE 
            WHEN @ReqId IS NOT NULL THEN CONCAT('Candidate registered successfully for ', @MrfCode, '.')
            ELSE 'Candidate pre-registered into Talent Bench successfully.'
        END AS Message, 
        @NewAppId AS AppId, 
        @NextAppNo AS ApplicationNo;
END;
GO
PRINT 'dbo.usp_REC_SubmitVendorCandidate updated with blacklisted Aadhaar check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Update dbo.usp_REC_RegisterCandidateApplication
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
    @SourceType      NVARCHAR(50)   = 'Vendor', -- Vendor / QR_Direct / Career_Portal
    @VendorId        NVARCHAR(50)   = NULL,
    @VendorName      NVARCHAR(150)  = NULL,
    @AadhaarNo       NVARCHAR(20)   = NULL,     -- Optional Aadhaar Card No
    @CreatedBy       NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Clean & normalize inputs
    SET @Mobile = LTRIM(RTRIM(ISNULL(@Mobile, '')));
    SET @Mobile = REPLACE(REPLACE(REPLACE(REPLACE(@Mobile, '+91', ''), '-', ''), ' ', ''), '+', '');
    IF LEN(@Mobile) > 10
        SET @Mobile = RIGHT(@Mobile, 10);

    IF @AadhaarNo IS NOT NULL
    BEGIN
        SET @AadhaarNo = REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', '');
        IF LEN(@AadhaarNo) = 0 SET @AadhaarNo = NULL;
    END

    -- 2. Verify requisition exists
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @ReqStatus NVARCHAR(50);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);
    DECLARE @ReqCompanyId NVARCHAR(50);

    SELECT 
        @MrfCode      = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @ReqStatus    = r.WorkflowStatus,
        @Hub          = ISNULL(loc.locname, 'Hub Operations'),
        @Dept         = ISNULL(dept.description, 'Operations'),
        @Desg         = ISNULL(des.designation, r.jobtitle),
        @ReqCompanyId = r.fk_companyId
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
    BEGIN
        SELECT 
            CAST(0 AS BIT) AS Success, 
            CAST(0 AS BIT) AS IsRejected, 
            'Requisition not found.' AS Message,
            CAST(0 AS BIGINT) AS appId,
            CAST('' AS NVARCHAR(50)) AS applicationNo,
            '' AS mrfCode;
        RETURN;
    END

    IF (@CompanyId IS NULL OR @CompanyId = '')
        SET @CompanyId = @ReqCompanyId;

    -- ─────────────────────────────────────────────────────────────────────────
    -- MANDATORY SECURITY CHECK: Blacklisted Candidate Aadhaar Verification
    -- ─────────────────────────────────────────────────────────────────────────
    IF @AadhaarNo IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT
          AND isBlacklisted = 1
          AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
    )
    BEGIN
        SELECT 
            CAST(0 AS BIT) AS Success,
            CAST(1 AS BIT) AS IsRejected,
            CONCAT('Security Restriction: Candidate with Aadhaar card [', @AadhaarNo, '] is blacklisted in company employee records and cannot be processed.') AS Message,
            CAST(0 AS BIGINT) AS appId,
            CAST('' AS NVARCHAR(50)) AS applicationNo,
            '' AS mrfCode;
        RETURN;
    END

    -- 3. Duplicate Validations: Check active applications and database records
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupAadhaar BIT = 0;
    DECLARE @DupDetail NVARCHAR(500) = '';

    -- Check 1: Active application duplicate in REC_Candidate_Applications (Company-Scoped)
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT
          AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
          AND ISNULL(IsRejected, 0) = 0
          AND Stage NOT IN ('Rejected')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already has an active application in Candidate Applications.');
    END

    -- Check 2: Mobile duplicate in REC_Candidate_Details (Candidate Master)
    IF @IsDuplicate = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (
                RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT
                OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT
            )
            AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
            AND ISNULL(status, '') NOT IN ('Rejected')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in Candidate Master database.');
        END
    END

    -- Check 3: Aadhaar duplicate in REC_Candidate_Applications
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', '') COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT
              AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
              AND ISNULL(IsRejected, 0) = 0
              AND Stage NOT IN ('Rejected')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already has an active application in Candidate Applications.');
        END
    END

    -- Check 4: Active employee in SAL_Employee_Mst (already an active hired employee)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE (REPLACE(REPLACE(adhaarNo, '-', ''), ' ', '') COLLATE DATABASE_DEFAULT = @AadhaarNo COLLATE DATABASE_DEFAULT
                   OR adhaarNo COLLATE DATABASE_DEFAULT = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
              AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
              AND ISNULL(active, 'Y') IN ('Y', '1', 'True')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists as an active employee in Employee Master.');
        END
    END

    -- IF DUPLICATE IS FOUND, DO NOT CREATE THE CANDIDATE
    IF @IsDuplicate = 1
    BEGIN
        SELECT 
            CAST(0 AS BIT) AS Success,
            CAST(1 AS BIT) AS IsRejected,
            CONCAT('Duplicate Profile: ', @DupDetail, ' Candidate application will NOT be created.') AS Message,
            CAST(0 AS BIGINT) AS appId,
            CAST('' AS NVARCHAR(50)) AS applicationNo,
            @MrfCode AS mrfCode;
        RETURN;
    END

    -- 4. Re-activation check for previously REJECTED candidate
    DECLARE @ExistingRejectedAppId BIGINT = NULL;
    DECLARE @ExistingAppNo NVARCHAR(50) = NULL;

    SELECT TOP 1 
        @ExistingRejectedAppId = pk_appId,
        @ExistingAppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) COLLATE DATABASE_DEFAULT = @Mobile COLLATE DATABASE_DEFAULT
      AND (fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '')
      AND (IsRejected = 1 OR Stage = 'Rejected')
    ORDER BY pk_appId DESC;

    IF @ExistingRejectedAppId IS NOT NULL
    BEGIN
        UPDATE dbo.REC_Candidate_Applications
        SET 
            fk_reqid                 = @ReqId,
            MrfCode                  = @MrfCode,
            CandidateName            = @CandidateName,
            Email                    = ISNULL(@Email, Email),
            Gender                   = ISNULL(@Gender, Gender),
            DateOfBirth              = COALESCE(@DateOfBirth, DateOfBirth),
            FatherName               = ISNULL(@FatherName, FatherName),
            CurrentLocation          = ISNULL(@CurrentLocation, CurrentLocation),
            OperatingHub             = @Hub,
            Department               = @Dept,
            Designation              = @Desg,
            SourceType               = @SourceType,
            fk_vendorId              = @VendorId,
            VendorName               = @VendorName,
            AadhaarNo                = ISNULL(@AadhaarNo, AadhaarNo),
            Stage                    = 'Applied',
            IsRejected               = 0,
            RejectionReason          = NULL,
            RejectionStage           = NULL,
            RejectionRemarks         = NULL,
            InterviewStatus          = 'Pending',
            InterviewRound           = NULL,
            InterviewDate            = NULL,
            InterviewerId            = NULL,
            InterviewerName          = NULL,
            InterviewRemarks         = NULL,
            InterviewScore           = NULL,
            DocVerificationStatus    = 'Pending',
            DocVerifiedBy            = NULL,
            DocVerificationRemarks   = NULL,
            OfferedCTC               = NULL,
            OfferLetterSentDate      = NULL,
            ExpectedJoiningDate      = NULL,
            EmployeeCode             = NULL,
            HiredDate                = NULL,
            CandidateTags            = NULL,
            LastUpdatedDate          = GETDATE(),
            LastUpdatedBy            = @CreatedBy
        WHERE pk_appId = @ExistingRejectedAppId;

        INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
            fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
            ActionByUserId, ActionByName, Remarks, ActionDate, CompanyId, fk_companyId
        ) VALUES (
            @ExistingRejectedAppId, @ExistingAppNo, 'REAPPLY_RESET', 'Rejected', 'Applied',
            @CreatedBy, @CreatedBy,
            CONCAT('Previously rejected candidate re-applied for job [', @MrfCode, ']. Reset profile state to Applied.'),
            GETDATE(), @CompanyId, @CompanyId
        );

        SELECT 
            CAST(1 AS BIT) AS Success,
            CAST(0 AS BIT) AS IsRejected,
            CONCAT('Candidate successfully re-applied for position ', @MrfCode, ' with Application No ', @ExistingAppNo) AS Message,
            @ExistingRejectedAppId AS appId,
            @ExistingAppNo AS applicationNo,
            @MrfCode AS mrfCode;
        RETURN;
    END

    -- 5. Standard Global Sequential ApplicationNo Generation for Fresh Candidate
    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;

    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');

    DECLARE @AppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- 6. Insert new candidate application
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus,
        CompanyId, fk_companyId, CreatedBy, CreatedDate, LastUpdatedBy, LastUpdatedDate
    ) VALUES (
        @AppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending',
        @CompanyId, @CompanyId, @CreatedBy, GETDATE(), @CreatedBy, GETDATE()
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Seed standard onboarding documents
    IF OBJECT_ID('dbo.usp_REC_SeedCandidateDocuments', 'P') IS NOT NULL
    BEGIN
        EXEC dbo.usp_REC_SeedCandidateDocuments @AppId = @NewAppId, @CompanyId = @CompanyId;
    END

    -- Log Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, Remarks, ActionDate, CompanyId, fk_companyId
    ) VALUES (
        @NewAppId, @AppNo, 'REGISTER_CANDIDATE', 'None', 'Applied',
        @CreatedBy, @CreatedBy,
        CONCAT('Candidate applied for job [', @MrfCode, '] via ', @SourceType),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success,
        CAST(0 AS BIT) AS IsRejected,
        CONCAT('Candidate successfully registered with Application No ', @AppNo) AS Message,
        @NewAppId AS appId,
        @AppNo AS applicationNo,
        @MrfCode AS mrfCode;
END;
GO
PRINT 'dbo.usp_REC_RegisterCandidateApplication updated with blacklisted Aadhaar check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Update dbo.usp_REC_SaveCandidateOnboardingDossier
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveCandidateOnboardingDossier
    @AppId           BIGINT,
    @AadhaarNo       NVARCHAR(20)  = NULL,
    @PanNo           NVARCHAR(20)  = NULL,
    @BankAccNo       NVARCHAR(50)  = NULL,
    @BankIfsc        NVARCHAR(20)  = NULL,
    @BankName        NVARCHAR(100) = NULL,
    @NomineeName     NVARCHAR(150) = NULL,
    @NomineeRelation NVARCHAR(50)  = NULL,
    @NomineeDOB      NVARCHAR(30)  = NULL,
    @NomineeContact  NVARCHAR(30)  = NULL,
    @UanNo           NVARCHAR(30)  = NULL,
    @EsicNo          NVARCHAR(30)  = NULL,
    @CandidateName   NVARCHAR(150) = NULL,
    @Mobile          NVARCHAR(20)  = NULL,
    @Email           NVARCHAR(100) = NULL,
    @Gender          NVARCHAR(20)  = NULL,
    @DateOfBirth     DATE          = NULL,
    @FatherName      NVARCHAR(150) = NULL,
    @SubmittedBy     NVARCHAR(100) = 'Site HR Admin',
    @CompanyId       NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    -- Normalize Aadhaar number for blacklist verification
    DECLARE @CleanAadhaar NVARCHAR(50) = NULL;
    IF @AadhaarNo IS NOT NULL AND LTRIM(RTRIM(@AadhaarNo)) <> ''
        SET @CleanAadhaar = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), ' ', ''), '-', ''), '.', '');
    ELSE
    BEGIN
        SELECT TOP 1 @CleanAadhaar = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(AadhaarNo)), ' ', ''), '-', ''), '.', '')
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- MANDATORY SECURITY CHECK: Blacklisted Candidate Aadhaar Verification
    -- ─────────────────────────────────────────────────────────────────────────
    IF @CleanAadhaar IS NOT NULL AND LEN(@CleanAadhaar) > 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = @CleanAadhaar COLLATE DATABASE_DEFAULT
              AND isBlacklisted = 1
              AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS Success, 
                   CONCAT('Security Restriction: Candidate with Aadhaar card [', @CleanAadhaar, '] is blacklisted in company employee records and cannot be saved or processed.') AS Message;
            RETURN;
        END
    END

    UPDATE dbo.REC_Candidate_Applications SET
        CandidateName   = ISNULL(NULLIF(@CandidateName, ''), CandidateName),
        Mobile          = ISNULL(NULLIF(@Mobile, ''), Mobile),
        Email           = ISNULL(NULLIF(@Email, ''), Email),
        Gender          = ISNULL(NULLIF(@Gender, ''), Gender),
        DateOfBirth     = COALESCE(@DateOfBirth, DateOfBirth),
        FatherName      = ISNULL(NULLIF(@FatherName, ''), FatherName),
        AadhaarNo       = ISNULL(NULLIF(@AadhaarNo, ''), AadhaarNo),
        PanNo           = ISNULL(NULLIF(@PanNo, ''), PanNo),
        BankAccNo       = ISNULL(NULLIF(@BankAccNo, ''), BankAccNo),
        BankIfsc        = ISNULL(NULLIF(@BankIfsc, ''), BankIfsc),
        BankName        = ISNULL(NULLIF(@BankName, ''), BankName),
        NomineeName     = @NomineeName,
        NomineeRelation = @NomineeRelation,
        NomineeDOB      = @NomineeDOB,
        NomineeContact  = @NomineeContact,
        UanNo           = @UanNo,
        EsicNo          = @EsicNo,
        LastUpdatedDate = GETDATE(),
        LastUpdatedBy   = @SubmittedBy
    WHERE pk_appId = @AppId 
      AND (CompanyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT OR @CompanyId IS NULL OR @CompanyId = '');

    -- Insert Audit Trail
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WITH (NOLOCK) WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'DOSSIER_UPDATE', 'Selected', 'Selected',
        @SubmittedBy, 'Vendor/Site HR',
        CONCAT('Updated candidate onboarding dossier and statutory details for [', ISNULL(@CandidateName, 'Candidate'), ']'),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 1 AS Success, 'Candidate onboarding dossier and statutory details saved successfully.' AS Message;
END;
GO
PRINT 'dbo.usp_REC_SaveCandidateOnboardingDossier updated with blacklisted Aadhaar check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Update dbo.usp_REC_UploadCandidateDocumentItem
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_UploadCandidateDocumentItem
    @AppId           BIGINT,
    @DocTypeCode     NVARCHAR(50),
    @FileName        NVARCHAR(255),
    @FilePath        NVARCHAR(500),
    @FileSize        BIGINT,
    @FileType        NVARCHAR(50),
    @UploadedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- MANDATORY SECURITY CHECK: Blacklisted Candidate Aadhaar Verification
    -- ─────────────────────────────────────────────────────────────────────────
    IF UPPER(LTRIM(RTRIM(@DocTypeCode))) = 'AADHAAR'
    BEGIN
        DECLARE @CandidateAadhaar NVARCHAR(50) = NULL;
        SELECT TOP 1 @CandidateAadhaar = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(AadhaarNo)), ' ', ''), '-', ''), '.', '')
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;

        IF @CandidateAadhaar IS NOT NULL AND LEN(@CandidateAadhaar) > 0
        BEGIN
            IF EXISTS (
                SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
                WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = @CandidateAadhaar COLLATE DATABASE_DEFAULT
                  AND isBlacklisted = 1
                  AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
            )
            BEGIN
                SELECT CAST(0 AS BIT) AS Success, 
                       CONCAT('Security Restriction: Candidate with Aadhaar card [', @CandidateAadhaar, '] is blacklisted in company employee records and Aadhaar document cannot be uploaded.') AS Message;
                RETURN;
            END
        END
    END

    -- Update or Insert Document Item
    IF EXISTS (SELECT 1 FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode)
    BEGIN
        UPDATE dbo.REC_Candidate_Documents SET
            FileName           = @FileName,
            FilePath           = @FilePath,
            FileSize           = @FileSize,
            FileType           = @FileType,
            VerificationStatus = 'Pending', -- Reset to pending for HR review upon upload/re-upload
            RejectionRemarks   = NULL,
            UploadedBy         = @UploadedBy,
            UploadedDate       = GETDATE(),
            CompanyId          = @CompanyId,
            fk_companyId       = @CompanyId
        WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Candidate_Documents (
            fk_appId, DocTypeCode, DocTypeName, DocCategory, IsMandatory,
            FileName, FilePath, FileSize, FileType, VerificationStatus,
            UploadedBy, UploadedDate, CompanyId, fk_companyId
        ) VALUES (
            @AppId, @DocTypeCode, @DocTypeCode, 'Uploaded', 1,
            @FileName, @FilePath, @FileSize, @FileType, 'Pending',
            @UploadedBy, GETDATE(), @CompanyId, @CompanyId
        );
    END;

    -- Sync back to REC_Candidate_Applications main fields if Aadhaar / PAN / Photo
    IF UPPER(@DocTypeCode) = 'AADHAAR'
        UPDATE dbo.REC_Candidate_Applications SET AadhaarDocPath = @FilePath WHERE pk_appId = @AppId;
    ELSE IF UPPER(@DocTypeCode) = 'PAN'
        UPDATE dbo.REC_Candidate_Applications SET PanDocPath = @FilePath WHERE pk_appId = @AppId;
    ELSE IF UPPER(@DocTypeCode) = 'PHOTO'
        UPDATE dbo.REC_Candidate_Applications SET PhotoDocPath = @FilePath WHERE pk_appId = @AppId;

    -- Audit Log
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'UPLOAD_DOC', 'Docs_Submitted', 'Docs_Submitted',
        NULL, @UploadedBy, 'Vendor/Site HR',
        CONCAT('Document [', @DocTypeCode, ' - ', @FileName, '] uploaded for verification'),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Document ', @FileName, ' uploaded successfully.') AS Message;
END;
GO
PRINT 'dbo.usp_REC_UploadCandidateDocumentItem updated with blacklisted Aadhaar check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Update dbo.usp_REC_VerifyCandidateDocumentItem
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_VerifyCandidateDocumentItem
    @AppId           BIGINT,
    @DocTypeCode     NVARCHAR(50),
    @Status          NVARCHAR(50), -- 'Approved' or 'Rejected'
    @RejectionRemarks NVARCHAR(500) = NULL,
    @VerifiedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- MANDATORY SECURITY CHECK: Blacklisted Candidate Aadhaar Verification
    -- ─────────────────────────────────────────────────────────────────────────
    IF UPPER(LTRIM(RTRIM(@DocTypeCode))) = 'AADHAAR' AND UPPER(LTRIM(RTRIM(@Status))) = 'APPROVED'
    BEGIN
        DECLARE @CandidateAadhaarVerify NVARCHAR(50) = NULL;
        SELECT TOP 1 @CandidateAadhaarVerify = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(AadhaarNo)), ' ', ''), '-', ''), '.', '')
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;

        IF @CandidateAadhaarVerify IS NOT NULL AND LEN(@CandidateAadhaarVerify) > 0
        BEGIN
            IF EXISTS (
                SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
                WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(adhaarNo)), ' ', ''), '-', ''), '.', '') COLLATE DATABASE_DEFAULT = @CandidateAadhaarVerify COLLATE DATABASE_DEFAULT
                  AND isBlacklisted = 1
                  AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId COLLATE DATABASE_DEFAULT = @CompanyId COLLATE DATABASE_DEFAULT)
            )
            BEGIN
                SELECT CAST(0 AS BIT) AS Success, 
                       CONCAT('Security Restriction: Candidate with Aadhaar card [', @CandidateAadhaarVerify, '] is blacklisted in company employee records and cannot be approved.') AS Message,
                       @Status AS Status, 0 AS ApprovedMandatory, 0 AS TotalMandatory;
                RETURN;
            END
        END
    END

    UPDATE dbo.REC_Candidate_Documents SET
        VerificationStatus = @Status,
        RejectionRemarks   = CASE WHEN @Status = 'Rejected' THEN @RejectionRemarks ELSE NULL END,
        VerifiedBy         = @VerifiedBy,
        VerifiedDate       = GETDATE()
    WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode;

    -- Check overall mandatory verification status
    DECLARE @TotalMandatory INT;
    DECLARE @ApprovedMandatory INT;
    DECLARE @RejectedCount INT;

    SELECT 
        @TotalMandatory = COUNT(1),
        @ApprovedMandatory = SUM(CASE WHEN VerificationStatus = 'Approved' THEN 1 ELSE 0 END),
        @RejectedCount = SUM(CASE WHEN VerificationStatus = 'Rejected' THEN 1 ELSE 0 END)
    FROM dbo.REC_Candidate_Documents
    WHERE fk_appId = @AppId AND IsMandatory = 1;

    -- Update Candidate Application overall status
    IF @ApprovedMandatory >= @TotalMandatory AND @TotalMandatory > 0
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            DocVerificationStatus = 'Verified',
            OnboardingStatus      = 'Completed',
            Stage                 = 'Docs_Verified',
            LastUpdatedDate       = GETDATE(),
            LastUpdatedBy         = @VerifiedBy
        WHERE pk_appId = @AppId;
    END
    ELSE IF @RejectedCount > 0
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            DocVerificationStatus = 'Deficient',
            OnboardingStatus      = 'Deficient',
            DeficiencyCount       = @RejectedCount,
            DeficiencyRemarks     = CONCAT(@RejectedCount, ' document(s) rejected during review. Correction & re-upload required.'),
            LastUpdatedDate       = GETDATE(),
            LastUpdatedBy         = @VerifiedBy
        WHERE pk_appId = @AppId;
    END;

    -- Audit Log
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'VERIFY_DOC', 'Docs_Submitted', 'Docs_Submitted',
        NULL, @VerifiedBy, 'Site HR Admin',
        CONCAT('Document [', @DocTypeCode, '] ', @Status, CASE WHEN @Status = 'Rejected' THEN CONCAT(' - Reason: ', @RejectionRemarks) ELSE '' END),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success,
        CONCAT('Document [', @DocTypeCode, '] marked as ', @Status, '.') AS Message,
        @Status AS Status,
        @ApprovedMandatory AS ApprovedMandatory,
        @TotalMandatory AS TotalMandatory;
END;
GO
PRINT 'dbo.usp_REC_VerifyCandidateDocumentItem updated with blacklisted Aadhaar check.';
GO

PRINT 'Migration 60 executed successfully.';
GO
