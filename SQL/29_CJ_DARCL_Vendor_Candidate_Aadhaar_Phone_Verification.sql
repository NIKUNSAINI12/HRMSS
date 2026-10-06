-- ============================================================================
-- SCRIPT: 29_CJ_DARCL_Vendor_Candidate_Aadhaar_Phone_Verification.sql
-- DESCRIPTION: Enhance dbo.usp_REC_SubmitVendorCandidate with strict Phone &
--              Aadhaar format verification, global sequence generation, and
--              comprehensive duplicate checking matching the Pipeline page standard.
-- ============================================================================

USE [HRBook_22]
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitVendorCandidate
    @ReqId          BIGINT,
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

    -- Dynamic Company resolution from Job Requisition if not supplied
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
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
    -- 2. Duplicate Validations (Matching Candidate Pipeline Page Standard)
    -- ─────────────────────────────────────────────────────────────────────────
    -- Check 2a: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2b: Mobile duplicate in REC_Candidate_Details
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE (mobile = @Mobile OR phone = @Mobile)
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Database.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2c: Aadhaar duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE AadhaarNo = @AadhaarNo
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Aadhaar card ', @AadhaarNo, ' already registered in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2d: Aadhaar duplicate in SAL_Employee_Mst
    IF EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE (adhaarNo = @AadhaarNo OR adhaarNo = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Candidate with Aadhaar ', @AadhaarNo, ' is already an employee in Company Master.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 3. Job Metadata Resolution & Global Unique Sequence Generation
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @MrfCode  NVARCHAR(50)  = '';
    DECLARE @JobTitle NVARCHAR(150) = 'Logistics Executive';
    DECLARE @LocName  NVARCHAR(100) = 'Hub Operations';
    DECLARE @DeptName NVARCHAR(100) = 'Operations';

    SELECT 
        @MrfCode  = ISNULL(jm.Mrfcode, CONCAT('MRF/', jm.pk_reqid)),
        @JobTitle = jm.jobtitle,
        @LocName  = ISNULL(loc.locname, 'Hub Operations'),
        @DeptName = ISNULL(dept.description, 'Operations')
    FROM dbo.REC_JobRequisition_Mst jm WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = jm.fk_deptid
    WHERE jm.pk_reqid = @ReqId;

    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    -- NOTE: Global across REC_Candidate_Applications to satisfy table UNIQUE constraint on ApplicationNo
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. Insert Candidate Application
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
    EXEC dbo.usp_REC_SeedCandidateDocuments @AppId = @NewAppId, @CompanyId = @CompanyId;

    -- Log Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'VENDOR_SUBMISSION', 'None', 'Applied',
        @SubmittedBy, 'Vendor Partner',
        CONCAT('Candidate profile verified and submitted by vendor [', @VendorName, '] for MRF ', @MrfCode, ' (', @JobTitle, ')'),
        GETDATE(), @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success, 
        CONCAT('Candidate ', @CandidateName, ' successfully registered with Application No ', @NextAppNo) AS Message,
        @NewAppId AS AppId,
        @NextAppNo AS ApplicationNo;
END;
GO

PRINT 'dbo.usp_REC_SubmitVendorCandidate updated with global sequence generation and duplicate verification.';
GO
