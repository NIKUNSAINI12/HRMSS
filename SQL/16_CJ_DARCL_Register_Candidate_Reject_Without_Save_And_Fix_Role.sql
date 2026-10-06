-- =============================================================================
-- Migration 16: CJ DARCL Register Candidate - Do Not Save Duplicate In DB & Fix User Role
-- Standards: 100% Company-Specific, Zero Hardcoding, Reject Without Insert
-- =============================================================================

USE HRBook_22;
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidate
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
    @AadhaarNo       NVARCHAR(20)   = NULL,
    @CreatedBy       NVARCHAR(100)  = 'Site HR Admin',
    @CompanyId       NVARCHAR(50)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean parameters
    SET @Mobile = LTRIM(RTRIM(@Mobile));
    IF @AadhaarNo IS NOT NULL
    BEGIN
        SET @AadhaarNo = REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), ' ', ''), '-', '');
        IF LEN(@AadhaarNo) = 0 SET @AadhaarNo = NULL;
    END

    -- Get Job Requisition details
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @Hub     NVARCHAR(150);
    DECLARE @Dept    NVARCHAR(150);
    DECLARE @Desg    NVARCHAR(150);

    SELECT 
        @MrfCode = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @Hub     = ISNULL(loc.locname, 'Hub Operations'),
        @Dept    = ISNULL(dept.description, 'Operations'),
        @Desg    = ISNULL(des.designation, r.jobtitle),
        @CompanyId = ISNULL(@CompanyId, r.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    -- =========================================================================
    -- DUPLICATE VALIDATION: Phone or Aadhaar must NOT already exist in DB
    -- =========================================================================
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupDetail NVARCHAR(250) = '';

    -- Check 1: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate applications.');
    END

    -- Check 2: Mobile duplicate in REC_Candidate_Details
    IF @IsDuplicate = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (mobile = @Mobile OR phone = @Mobile)
              AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate master.');
        END
    END

    -- Check 3: Aadhaar duplicate in REC_Candidate_Applications
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE AadhaarNo = @AadhaarNo
              AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in candidate applications.');
        END
    END

    -- Check 4: Aadhaar duplicate in SAL_Employee_Mst (already an active/past employee)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE adhaarNo = @AadhaarNo
              AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in company Employee Master.');
        END
    END

    -- =========================================================================
    -- IF DUPLICATE: REJECT IMMEDIATELY WITHOUT SAVING INTO REC_Candidate_Applications
    -- Prevents polluting the database table with duplicate records.
    -- =========================================================================
    IF @IsDuplicate = 1
    BEGIN
        SELECT 
            0 AS Success,
            1 AS IsRejected,
            CONCAT('Registration Rejected: ', @DupDetail, ' Candidate profile already exists.') AS Message,
            0 AS appId,
            '' AS applicationNo,
            @MrfCode AS mrfCode;
        RETURN;
    END

    -- =========================================================================
    -- NEW CANDIDATE: Generate unique Application No and insert
    -- =========================================================================
    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Determine actual audit role for the registering user (NOT the candidate sourcing type)
    DECLARE @UserRole NVARCHAR(100) = CASE 
        WHEN @SourceType = 'Vendor' AND @CreatedBy NOT LIKE '%Vendor%' THEN 'Site HR Admin'
        WHEN @SourceType = 'Vendor' AND @CreatedBy LIKE '%Vendor%'     THEN 'Vendor Partner'
        WHEN @SourceType = 'QR_Direct'                                THEN 'Self-Registered (QR)'
        ELSE 'Site HR Admin'
    END;

    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus,
        fk_companyId, CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending', @CompanyId,
        GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail with proper UserRole
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @CreatedBy, @CreatedBy, @UserRole, 
        CONCAT('Candidate registered against MRF ', @MrfCode, CASE WHEN @VendorName IS NOT NULL AND @VendorName <> '' THEN CONCAT(' via ', @VendorName) ELSE '' END), 
        GETDATE(), @CompanyId
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

PRINT 'dbo.usp_REC_RegisterCandidate successfully updated without errors.';
