-- =============================================================================
-- Migration 14: CJ DARCL Candidate Registration with Optional Aadhaar & Duplicate Auto-Rejection
-- Standard: 100% Company-Specific, Zero Hardcoding, Full Audit Logging
-- Requirements:
--   1. Accept optional Aadhaar Card No (@AadhaarNo) during Step 6 Candidate Registration.
--   2. Check if Mobile No OR Aadhaar Card No is already present in DB for this company.
--   3. If already present, register candidate directly in 'Rejected' stage with reason/remarks and audit record.
-- =============================================================================

USE HRBook_22;
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

    -- Check for duplicate Mobile OR Aadhaar in Candidates or Employee Master for this company
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupAadhaar BIT = 0;
    DECLARE @DupDetail NVARCHAR(250) = '';

    -- Check 1: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile AND fk_companyId = @CompanyId
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in company recruitment pool.');
    END

    -- Check 2: Aadhaar duplicate in REC_Candidate_Applications (if provided)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE AadhaarNo = @AadhaarNo AND fk_companyId = @CompanyId
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in company candidate records.');
        END
    END

    -- Check 3: Aadhaar duplicate in SAL_Employee_Mst (already an active/past employee)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE adhaarNo = @AadhaarNo AND fk_companyId = @CompanyId
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in company Employee Master.');
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
            fk_companyId, CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
        ) VALUES (
            @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
            @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
            @Dept, @Desg, @SourceType, @VendorId, @VendorName,
            @AadhaarNo, 'Rejected', 'Unskilled', 'Rejected',
            @RejectionReason, @RejectionRemarks, '90_Days',
            @CompanyId, GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
        );

        DECLARE @RejectedAppId BIGINT = SCOPE_IDENTITY();

        -- Insert audit log for auto-rejection
        INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
            fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
            ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
        ) VALUES (
            @RejectedAppId, @NextAppNo, 'REJECT', 'None', 'Rejected',
            @VendorId, @CreatedBy, @SourceType, 
            CONCAT('Auto-rejected upon registration: ', @DupDetail), 
            GETDATE(), @CompanyId
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

    -- IF NOT DUPLICATE: NORMAL SUCCESSFUL REGISTRATION
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus, fk_companyId,
        CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending', @CompanyId,
        GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @VendorId, @CreatedBy, @SourceType, CONCAT('Candidate registered against MRF ', @MrfCode), GETDATE(), @CompanyId
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

PRINT 'dbo.usp_REC_RegisterCandidateApplication updated with optional Aadhaar and duplicate auto-rejection.';
