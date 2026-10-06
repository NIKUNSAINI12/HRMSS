-- ==========================================================================================
-- SCRIPT: 65_CJ_DARCL_Public_Apply_Enforce_Duplicate_And_Blacklist_Checks.sql
-- PURPOSE:
--   1. Update dbo.usp_REC_CheckCandidateAadhaarStatus:
--      - MANDATORY BLACKLIST CHECK: If Aadhaar belongs to an employee in SAL_Employee_Mst with isBlacklisted = 1,
--        strictly block application (CanProceed = 0, ExistsStatus = 1, CurrentStatus = 'Blacklisted').
--      - DUPLICATE AADHAAR CHECK: If candidate has an active application in REC_Candidate_Applications
--        or REC_Candidate_Details (not Rejected/Dropped), block application.
--      - Allow re-application only if previous application was Rejected or Dropped.
--   2. Update dbo.usp_REC_SubmitWalkInCandidate:
--      - MANDATORY BLACKLIST CHECK for both Aadhaar and Mobile Number against SAL_Employee_Mst / SAL_EmployeeOther_Details.
--      - STRICT DUPLICATE MOBILE CHECK against active records in REC_Candidate_Applications and REC_Candidate_Details.
--      - STRICT DUPLICATE AADHAAR CHECK against active records in REC_Candidate_Applications and REC_Candidate_Details.
--      - ZERO HARDCODING: Dynamically resolves company context from Requisition, Location, or Common_Client_Details.
-- ==========================================================================================

USE [HRBook_22];
GO

PRINT '>>> Updating dbo.usp_REC_CheckCandidateAadhaarStatus with Blacklist & Duplicate Enforcement...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_CheckCandidateAadhaarStatus
    @AadhaarNo NVARCHAR(50),
    @CompanyId VARCHAR(100) = NULL,
    @LocationId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @AadhaarNo = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', ''), '.', '');

    -- ─────────────────────────────────────────────────────────────────────────
    -- 1. MANDATORY BLACKLIST CHECK: SAL_Employee_Mst (isBlacklisted = 1)
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @BlkEmpName NVARCHAR(200);
    DECLARE @BlkReason NVARCHAR(500);

    SELECT TOP 1
        @BlkEmpName = emp.empname,
        @BlkReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
    FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(emp.adhaarNo)), ' ', ''), '-', ''), '.', '') = @AadhaarNo
      AND emp.isBlacklisted = 1
      AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

    IF @BlkEmpName IS NOT NULL
    BEGIN
        SELECT 
            1 AS ExistsStatus,
            0 AS CanProceed,
            @BlkEmpName AS CandidateName,
            'Blacklisted' AS CurrentStatus,
            'Blacklisted' AS JobTitle,
            'Security Restriction: Candidate (' + @BlkEmpName + ') with Aadhaar [' + @AadhaarNo + '] is blacklisted in company records (' + @BlkReason + '). Application cannot be submitted.' AS Message;
        RETURN;
    END;

    -- ─────────────────────────────────────────────────────────────────────────
    -- 2. DUPLICATE AADHAAR CHECK: REC_Candidate_Applications
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @AppCandidateName NVARCHAR(200);
    DECLARE @AppStage NVARCHAR(100);
    DECLARE @AppInterviewStatus NVARCHAR(100);
    DECLARE @AppJobTitle NVARCHAR(200);

    SELECT TOP 1
        @AppCandidateName = CandidateName,
        @AppStage = Stage,
        @AppInterviewStatus = InterviewStatus,
        @AppJobTitle = Designation
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
    ORDER BY pk_appId DESC;

    IF @AppCandidateName IS NOT NULL
    BEGIN
        -- If candidate is already in active interview or selected or hired
        IF @AppInterviewStatus IN ('Selected', 'Interview Scheduled', 'L1 Cleared', 'L2 Cleared', 'HR Cleared', 'Offer Released', 'Joined')
           OR @AppStage IN ('Interview', 'Selected', 'Offer', 'Onboarding', 'Hired')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @AppCandidateName AS CandidateName,
                ISNULL(@AppInterviewStatus, @AppStage) AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate is already in active interview / selection process (' + ISNULL(@AppInterviewStatus, @AppStage) + '). New application cannot be submitted.' AS Message;
            RETURN;
        END
        ELSE IF @AppInterviewStatus IN ('Rejected', 'Dropped')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                1 AS CanProceed,
                @AppCandidateName AS CandidateName,
                @AppInterviewStatus AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate record found (Previous Status: ' + @AppInterviewStatus + '). Re-application allowed.' AS Message;
            RETURN;
        END
        ELSE
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @AppCandidateName AS CandidateName,
                ISNULL(@AppInterviewStatus, 'Under Review') AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'An application with this Aadhaar number is already pending review (' + ISNULL(@AppInterviewStatus, 'Applied') + '). Duplicate submission not allowed.' AS Message;
            RETURN;
        END
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 3. DUPLICATE AADHAAR CHECK: REC_Candidate_Details (Vendor_AaddharNo)
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @DetCandidateName NVARCHAR(200);
    DECLARE @DetStatus NVARCHAR(100);
    DECLARE @DetJobTitle NVARCHAR(200);

    SELECT TOP 1
        @DetCandidateName = candidate_name,
        @DetStatus = status,
        @DetJobTitle = designation
    FROM dbo.REC_Candidate_Details WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(Vendor_AaddharNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
    ORDER BY pk_recId DESC;

    IF @DetCandidateName IS NOT NULL
    BEGIN
        IF @DetStatus IN ('Selected', 'Final Selected', 'Joined', 'Onboarding', 'Active', 'Interview')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @DetCandidateName AS CandidateName,
                @DetStatus AS CurrentStatus,
                ISNULL(@DetJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate already exists in onboarding/selection (' + @DetStatus + '). New submission blocked.' AS Message;
            RETURN;
        END
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. ALL CLEAR: Eligible to Apply
    -- ─────────────────────────────────────────────────────────────────────────
    SELECT 
        0 AS ExistsStatus,
        1 AS CanProceed,
        '' AS CandidateName,
        'New' AS CurrentStatus,
        '' AS JobTitle,
        'Aadhaar number verified and clear. Candidate eligible to apply.' AS Message;
END;
GO

PRINT '>>> Updating dbo.usp_REC_SubmitWalkInCandidate with Blacklist & Duplicate Enforcement...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitWalkInCandidate
    @CandidateName NVARCHAR(200),
    @MobileNumber NVARCHAR(20),
    @AadhaarNo NVARCHAR(50) = NULL,
    @VendorId VARCHAR(100) = NULL,
    @VendorName NVARCHAR(200) = NULL,
    @JobId VARCHAR(100) = NULL,
    @JobTitle NVARCHAR(200) = NULL,
    @LocationId VARCHAR(100) = NULL,
    @CompanyId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @CandidateName = LTRIM(RTRIM(@CandidateName));
    SET @MobileNumber = RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@MobileNumber)), '+91', ''), '-', ''), ' ', ''), '+', ''), 10);
    SET @AadhaarNo = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@AadhaarNo, ''))), '-', ''), ' ', ''), '.', '');

    -- ── 1. MANDATORY BLACKLIST CHECK (SAL_Employee_Mst isBlacklisted = 1) ────
    -- Check 1a: Blacklisted Aadhaar
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @BlkAadhaarName NVARCHAR(200);
        DECLARE @BlkAadhaarReason NVARCHAR(500);

        SELECT TOP 1
            @BlkAadhaarName = emp.empname,
            @BlkAadhaarReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
        FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(emp.adhaarNo)), ' ', ''), '-', ''), '.', '') = @AadhaarNo
          AND emp.isBlacklisted = 1
          AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

        IF @BlkAadhaarName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @BlkAadhaarName AS CandidateName,
                'Blacklisted' AS JobTitle,
                'Security Restriction: Candidate (' + @BlkAadhaarName + ') with Aadhaar [' + @AadhaarNo + '] is blacklisted in company employee records (' + @BlkAadhaarReason + '). Application cannot be submitted.' AS Message;
            RETURN;
        END
    END

    -- Check 1b: Blacklisted Mobile Number
    IF @MobileNumber IS NOT NULL AND LEN(@MobileNumber) = 10
    BEGIN
        DECLARE @BlkMobileName NVARCHAR(200);
        DECLARE @BlkMobileReason NVARCHAR(500);

        SELECT TOP 1
            @BlkMobileName = emp.empname,
            @BlkMobileReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
        FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
        LEFT JOIN dbo.SAL_EmployeeOther_Details oth WITH (NOLOCK) ON emp.pk_empid = oth.fk_empid
        WHERE emp.isBlacklisted = 1
          AND (
            RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(oth.PersonalContactno, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
            OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(oth.permanentContactNo, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
            OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(emp.NomineeMobileNo, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
          )
          AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

        IF @BlkMobileName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @BlkMobileName AS CandidateName,
                'Blacklisted' AS JobTitle,
                'Security Restriction: Candidate (' + @BlkMobileName + ') with Mobile Number [' + @MobileNumber + '] is blacklisted in company records (' + @BlkMobileReason + '). Application cannot be submitted.' AS Message;
            RETURN;
        END
    END

    -- ── 2. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Applications) ──────
    DECLARE @ExistingAppName NVARCHAR(200);
    DECLARE @ExistingAppStatus NVARCHAR(100);
    DECLARE @ExistingAppJob NVARCHAR(200);

    SELECT TOP 1
        @ExistingAppName = CandidateName,
        @ExistingAppStatus = ISNULL(InterviewStatus, Stage),
        @ExistingAppJob = Designation
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
    ORDER BY pk_appId DESC;

    IF @ExistingAppName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingAppName AS CandidateName,
            ISNULL(@ExistingAppJob, 'Spot Candidate') AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' already exists with active application (' + @ExistingAppName + ' - ' + ISNULL(@ExistingAppStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 3. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Details) ───────────
    DECLARE @ExistingDetName NVARCHAR(200);
    DECLARE @ExistingDetStatus NVARCHAR(100);

    SELECT TOP 1
        @ExistingDetName = candidate_name,
        @ExistingDetStatus = status
    FROM dbo.REC_Candidate_Details WITH (NOLOCK)
    WHERE (IsVendor = 0 OR IsVendor IS NULL)
      AND (
        RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
        OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      )
      AND ISNULL(status, '') NOT IN ('Rejected', 'Dropped')
    ORDER BY pk_recId DESC;

    IF @ExistingDetName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingDetName AS CandidateName,
            'Spot Candidate' AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' is already registered under ' + @ExistingDetName + ' (' + ISNULL(@ExistingDetStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 4. DUPLICATE AADHAAR NUMBER CHECK (If Provided) ────────────────────
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @AadhaarDupName NVARCHAR(200);
        DECLARE @AadhaarDupStatus NVARCHAR(100);

        SELECT TOP 1 
            @AadhaarDupName = CandidateName,
            @AadhaarDupStatus = ISNULL(InterviewStatus, Stage)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
          AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
        ORDER BY pk_appId DESC;

        IF @AadhaarDupName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @AadhaarDupName AS CandidateName,
                'Spot Candidate' AS JobTitle,
                'Aadhaar Number already exists with active application (' + @AadhaarDupName + ' - ' + ISNULL(@AadhaarDupStatus, 'Active') + '). Duplicate application not allowed.' AS Message;
            RETURN;
        END

        -- Check in REC_Candidate_Details
        DECLARE @DetAadhaarName NVARCHAR(200);
        DECLARE @DetAadhaarStatus NVARCHAR(100);

        SELECT TOP 1
            @DetAadhaarName = candidate_name,
            @DetAadhaarStatus = status
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(Vendor_AaddharNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
          AND ISNULL(status, '') NOT IN ('Rejected', 'Dropped')
        ORDER BY pk_recId DESC;

        IF @DetAadhaarName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @DetAadhaarName AS CandidateName,
                'Spot Candidate' AS JobTitle,
                'Aadhaar Number is already registered in recruitment records under ' + @DetAadhaarName + ' (' + ISNULL(@DetAadhaarStatus, 'Active') + '). Duplicate application not allowed.' AS Message;
            RETURN;
        END
    END

    -- ── 5. RESOLVE VENDOR DETAILS (Strictly Optional) ──────────────────────
    DECLARE @IsVendorSelected BIT = 0;
    IF @VendorId IS NOT NULL AND @VendorId <> '' AND @VendorId <> 'DIRECT' AND @VendorId <> 'V-DIR-01'
    BEGIN
        SET @IsVendorSelected = 1;
        IF @VendorName IS NULL OR @VendorName = '' OR @VendorName = 'Direct Walk-In'
        BEGIN
            SELECT TOP 1 @VendorName = Vendor_Name 
            FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (pk_recId = @VendorId OR Vendor_Code = @VendorId) AND IsVendor = 1;
        END
    END
    ELSE
    BEGIN
        SET @VendorId = NULL;
        SET @VendorName = 'Direct Walk-In / Self';
    END

    -- ── 6. RESOLVE REQUISITION, LOCATION & COMPANY (Zero Hardcoding) ───────
    DECLARE @ValidReqId BIGINT = 0;
    IF @JobId IS NOT NULL AND TRY_CAST(@JobId AS BIGINT) IS NOT NULL
    BEGIN
        SET @ValidReqId = CAST(@JobId AS BIGINT);
    END

    DECLARE @AppNo NVARCHAR(50) = 'APP/WLK/' + FORMAT(GETDATE(), 'yyyy') + '/' + RIGHT(CAST(ABS(CHECKSUM(NEWID())) AS NVARCHAR(20)), 4);
    DECLARE @LocName NVARCHAR(200) = 'Hub';

    -- If locationId was provided, resolve location name
    IF @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @LocName = locname 
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE pk_locid = @LocationId OR code = @LocationId OR locationCode = @LocationId OR locname = @LocationId;
    END

    -- If locationId was not provided, dynamically resolve from Job Requisition
    IF (@LocationId IS NULL OR @LocationId = '') AND @ValidReqId > 0
    BEGIN
        SELECT TOP 1 
            @LocationId = req.fk_locid,
            @LocName = ISNULL(loc.locname, 'Hub')
        FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
        LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON req.fk_locid = loc.pk_locid
        WHERE req.pk_reqid = @ValidReqId;
    END

    -- Dynamically resolve CompanyId from Requisition, Location or active Client Details
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1')
    BEGIN
        IF @ValidReqId > 0
        BEGIN
            SELECT TOP 1 @CompanyId = req.fk_companyId
            FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
            WHERE req.pk_reqid = @ValidReqId;
        END

        IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1') AND @LocationId IS NOT NULL AND @LocationId <> ''
        BEGIN
            SELECT TOP 1 @CompanyId = loc.fk_companyId
            FROM dbo.Location_Mst loc WITH (NOLOCK)
            WHERE loc.pk_locid = @LocationId OR loc.code = @LocationId OR loc.locationCode = @LocationId;
        END

        IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1'
        BEGIN
            SELECT TOP 1 @CompanyId = fk_companyId 
            FROM dbo.Common_Client_Details WITH (NOLOCK) 
            ORDER BY pk_clientid ASC;
        END
    END

    -- ── 7. INSERT INTO REC_Candidate_Applications ──────────────────────────
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo,
        fk_reqid,
        CandidateName,
        Mobile,
        AadhaarNo,
        OperatingHub,
        Designation,
        SourceType,
        fk_vendorId,
        VendorName,
        Stage,
        InterviewStatus,
        fk_companyId,
        CompanyId,
        CreatedDate,
        CreatedBy
    ) VALUES (
        @AppNo,
        NULLIF(@ValidReqId, 0),
        @CandidateName,
        @MobileNumber,
        NULLIF(@AadhaarNo, ''),
        @LocName,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate'),
        CASE WHEN @IsVendorSelected = 1 THEN 'Vendor Sourced' ELSE 'Location QR - Walk-In' END,
        CASE WHEN @IsVendorSelected = 1 THEN @VendorId ELSE NULL END,
        @VendorName,
        'Applied',
        'Walk-In Applied',
        @CompanyId,
        @CompanyId,
        GETDATE(),
        'Location QR Portal'
    );

    -- ── 8. INSERT INTO REC_Candidate_Details ───────────────────────────────
    DECLARE @NewRecId VARCHAR(50) = 'REC-' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(20));
    DECLARE @DefaultUserId VARCHAR(50) = (SELECT TOP 1 pk_userId FROM dbo.UM_Users_Mst WITH (NOLOCK));

    DECLARE @ResolvedLegacyJobId VARCHAR(50) = NULL;
    IF @ValidReqId > 0 AND EXISTS (SELECT 1 FROM dbo.REC_Open_Newjob WITH (NOLOCK) WHERE pk_JobId = @ValidReqId)
    BEGIN
        SET @ResolvedLegacyJobId = CAST(@ValidReqId AS VARCHAR(50));
    END

    INSERT INTO dbo.REC_Candidate_Details (
        pk_recId,
        fk_jobId,
        candidate_name,
        mobile,
        Vendor_AaddharNo,
        Vendor_Name,
        Vendor_Code,
        fk_locid,
        designation,
        source,
        status,
        IsVendor,
        online_submit,
        fk_companyId,
        InsDate,
        fk_insUserID
    ) VALUES (
        @NewRecId,
        @ResolvedLegacyJobId,
        @CandidateName,
        @MobileNumber,
        NULLIF(@AadhaarNo, ''),
        @VendorName,
        CASE WHEN @IsVendorSelected = 1 THEN @VendorId ELSE NULL END,
        @LocationId,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate'),
        CASE WHEN @IsVendorSelected = 1 THEN 'Vendor Sourced' ELSE 'Location QR - Walk-In' END,
        '1',
        0,
        1,
        @CompanyId,
        GETDATE(),
        @DefaultUserId
    );

    SELECT 
        1 AS Success,
        @AppNo AS ApplicationRef,
        @CandidateName AS CandidateName,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate') AS JobTitle,
        'Application registered successfully for ' + @LocName + '.' AS Message;
END;
GO

PRINT 'Migration 65 applied successfully.';
GO
