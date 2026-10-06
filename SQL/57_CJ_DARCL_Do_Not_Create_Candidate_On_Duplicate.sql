-- =============================================================================
-- Migration 57: CJ DARCL - Do Not Create or Insert Candidate on Duplicate
-- Standards: 100% Company-Specific, Zero Hardcoding, Reject Without Insert
-- Problem: Previously when duplicate mobile or Aadhaar was found, the SP inserted
--          a record with Stage = 'Rejected' into REC_Candidate_Applications.
-- Solution: Immediately abort and return error WITHOUT creating any candidate in DB.
-- =============================================================================

USE HRBook_22;
GO

PRINT 'Starting Migration 57: Do Not Create Candidate on Duplicate...';
GO

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

    -- 3. Duplicate Validations: Check active applications and database records
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupAadhaar BIT = 0;
    DECLARE @DupDetail NVARCHAR(500) = '';

    -- Check 1: Active application duplicate in REC_Candidate_Applications (Company-Scoped)
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
          AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
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
                RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
                OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
            )
            AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
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
            WHERE REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', '') = @AadhaarNo 
              AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
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
            WHERE (REPLACE(REPLACE(adhaarNo, '-', ''), ' ', '') = @AadhaarNo 
                   OR adhaarNo = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
              AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId = @CompanyId)
              AND ISNULL(active, 'Y') IN ('Y', '1', 'True')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists as an active employee in Employee Master.');
        END
    END

    -- =========================================================================
    -- CRITICAL RULE: IF DUPLICATE IS FOUND, DO NOT CREATE THE CANDIDATE!
    -- DO NOT INSERT INTO REC_Candidate_Applications!
    -- DO NOT INSERT INTO REC_Candidate_Lifecycle_Audit!
    -- DO NOT GENERATE AN APPLICATION SEQUENCE!
    -- Return failure immediately so no record is persisted.
    -- =========================================================================
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

    -- =========================================================================
    -- 4. NEW CANDIDATE: Generate unique Application No: APP/YEAR/XXXX
    -- =========================================================================
    DECLARE @NextAppNo NVARCHAR(50);
    DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
    DECLARE @MaxSeq INT = 0;

    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');

    SET @NextAppNo = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Determine actual audit role for the registering user
    DECLARE @UserRole NVARCHAR(100) = CASE 
        WHEN @SourceType = 'Vendor' AND @CreatedBy NOT LIKE '%Vendor%' THEN 'Recruiter / Site HR'
        WHEN @SourceType = 'Vendor' AND @CreatedBy LIKE '%Vendor%'     THEN 'Vendor Partner'
        WHEN @SourceType = 'QR_Direct'                                THEN 'Self-Registered (QR)'
        ELSE 'Recruiter'
    END;

    -- Normal successful registration as fresh Applied candidate
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
        @VendorId, @CreatedBy, @UserRole, 
        CONCAT('Candidate registered against MRF ', @MrfCode, CASE WHEN @VendorName IS NOT NULL AND @VendorName <> '' THEN CONCAT(' via ', @VendorName) ELSE '' END), 
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success,
        CAST(0 AS BIT) AS IsRejected,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;

END;
GO

PRINT 'Migration 57 completed: dbo.usp_REC_RegisterCandidateApplication updated to reject duplicate candidate without any database insertion.';
GO
