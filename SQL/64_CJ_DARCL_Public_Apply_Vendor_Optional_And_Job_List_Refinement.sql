-- ==========================================================================================
-- SCRIPT: 64_CJ_DARCL_Public_Apply_Vendor_Optional_And_Job_List_Refinement.sql
-- PURPOSE:
--   1. Update dbo.usp_REC_GetPublicLocationJobsAndVendors:
--      - Strict Company-wise and Location-wise filtering for Job Requisitions.
--      - Strict Company-wise and Location-wise filtering for Sourcing Vendors via Vendor_Location_Mapping.
--      - Returns 4th Result Set: List of active company locations for public walk-in hub selector.
--      - Accurately return only approved & active job requisitions (exclude rejected & unapproved).
--   2. Update dbo.usp_REC_SubmitWalkInCandidate:
--      - Vendor is strictly OPTIONAL. If unselected, defaults to 'Direct Walk-In / Self' with SourceType = 'Location QR - Walk-In'.
--      - If LocationId is empty, dynamically resolve Location & Hub from the selected Job Requisition.
-- ==========================================================================================

USE [HRBook_22];
GO

PRINT '>>> Updating dbo.usp_REC_GetPublicLocationJobsAndVendors with Company & Location scoping...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetPublicLocationJobsAndVendors
    @LocationId VARCHAR(100),
    @CompanyId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Dynamic Company Code & Client ID Resolution
    DECLARE @CompanyCode VARCHAR(50) = NULL;
    DECLARE @ClientPkId VARCHAR(50) = NULL;

    IF @CompanyId IS NOT NULL AND @CompanyId <> ''
    BEGIN
        SELECT TOP 1 
            @CompanyCode = fk_companyId,
            @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
        FROM dbo.Common_Client_Details WITH (NOLOCK)
        WHERE fk_companyId = @CompanyId OR CAST(pk_clientid AS VARCHAR(50)) = @CompanyId;

        IF @CompanyCode IS NULL
        BEGIN
            SET @CompanyCode = @CompanyId;
        END;
    END;

    -- Fallback: deduce company from Location record if companyId wasn't passed directly
    IF (@CompanyCode IS NULL OR @CompanyCode = '') AND @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @CompanyCode = loc.fk_companyId
        FROM dbo.Location_Mst loc WITH (NOLOCK)
        WHERE loc.pk_locid = @LocationId OR loc.code = @LocationId OR loc.locationCode = @LocationId OR loc.locname = @LocationId;

        IF @CompanyCode IS NOT NULL
        BEGIN
            SELECT TOP 1 @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
            FROM dbo.Common_Client_Details WITH (NOLOCK)
            WHERE fk_companyId = @CompanyCode;
        END;
    END;

    -- Dynamic Resolution: If company was not passed and not found from location, query from Common_Client_Details
    IF @CompanyCode IS NULL OR @CompanyCode = ''
    BEGIN
        SELECT TOP 1 
            @CompanyCode = fk_companyId,
            @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
        FROM dbo.Common_Client_Details WITH (NOLOCK)
        ORDER BY pk_clientid ASC;
    END;

    -- Resolve Location ID to standard pk_locid
    DECLARE @ResolvedLocId VARCHAR(50) = NULL;
    IF @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @ResolvedLocId = pk_locid
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE pk_locid = @LocationId OR code = @LocationId OR locationCode = @LocationId OR locname = @LocationId;
    END;

    -- 2. Result Set 1: Location Details with Company Name & Logo
    IF @ResolvedLocId IS NOT NULL AND @ResolvedLocId <> ''
    BEGIN
        SELECT TOP 1
            loc.pk_locid AS locationId,
            loc.locname AS locationName,
            ISNULL(loc.locationCode, loc.code) AS locationCode,
            ISNULL(st.description, 'Operational Hub') AS state,
            ISNULL(zn.zoneDescription, 'General Zone') AS zone,
            ISNULL(ccd.compname, 'HRMS Portal') AS companyName,
            ISNULL(cfg.Company_LogoPath, ccd.complogo) AS companyLogo
        FROM dbo.Location_Mst loc WITH (NOLOCK)
        LEFT JOIN dbo.SAL_State_Mst st WITH (NOLOCK) ON TRY_CAST(loc.fk_stateid AS SMALLINT) = st.pk_stateid
        LEFT JOIN dbo.SAL_Zone_Mst zn WITH (NOLOCK) ON TRY_CAST(loc.fk_zoneId AS BIGINT) = zn.pk_zoneId
        LEFT JOIN dbo.Common_Client_Details ccd WITH (NOLOCK) ON (
            ccd.fk_companyId = @CompanyCode 
            OR CAST(ccd.pk_clientid AS VARCHAR(50)) = @ClientPkId
            OR ccd.fk_companyId = loc.fk_companyId
        )
        LEFT JOIN dbo.SAL_Company_Config cfg WITH (NOLOCK) ON (
            cfg.pk_companyId = ccd.fk_companyId 
            OR cfg.pk_companyId = @CompanyCode 
            OR cfg.pk_companyId = loc.fk_companyId
        )
        WHERE loc.pk_locid = @ResolvedLocId;
    END
    ELSE
    BEGIN
        SELECT TOP 1
            '' AS locationId,
            'Walk-In Recruitment Portal' AS locationName,
            'WALKIN' AS locationCode,
            'All Operational Hubs' AS state,
            'All Zones' AS zone,
            ISNULL(ccd.compname, 'HRMS Portal') AS companyName,
            ISNULL(cfg.Company_LogoPath, ccd.complogo) AS companyLogo
        FROM dbo.Common_Client_Details ccd WITH (NOLOCK)
        LEFT JOIN dbo.SAL_Company_Config cfg WITH (NOLOCK) ON (
            cfg.pk_companyId = ccd.fk_companyId 
            OR cfg.pk_companyId = @CompanyCode
        )
        WHERE ccd.fk_companyId = @CompanyCode OR CAST(ccd.pk_clientid AS VARCHAR(50)) = @ClientPkId;
    END;

    -- 3. Result Set 2: Dynamic Job Requisitions (STRICTLY Company-Wise and Location-Wise)
    SELECT 
        req.pk_reqid AS jobId,
        req.Mrfcode AS mrfCode,
        req.jobtitle AS jobTitle,
        ISNULL(dept.description, '') AS department,
        ISNULL(desg.designation, req.jobtitle) AS designation,
        ISNULL(loc.locname, 'Hub') AS locationName,
        req.fk_locid AS locationId,
        'On-Site' AS workplaceType,
        'Full-Time' AS employmentType,
        ISNULL(req.No_of_post, 1) AS openPositions,
        ISNULL(req.Experience_From, 0) AS expMin,
        ISNULL(req.Experience_To, 5) AS expMax,
        ISNULL(req.CTC_From, 0) AS ctcMin,
        ISNULL(req.CTC_To, 0) AS ctcMax,
        ISNULL(req.Technical_Skills, '') AS primarySkills,
        CONVERT(VARCHAR(10), req.dated, 120) AS targetStartDate
    FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON req.fk_deptid = dept.pk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst desg WITH (NOLOCK) ON req.fk_desgid = desg.pk_desgid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON req.fk_locid = loc.pk_locid
    WHERE (
        req.fk_companyId = @CompanyCode 
        OR req.fk_companyId = @ClientPkId 
        OR req.fk_companyId = @CompanyId
        OR req.CompanyId = @CompanyCode
    )
    AND (
        @ResolvedLocId IS NULL OR @ResolvedLocId = ''
        OR req.fk_locid = @ResolvedLocId
    )
    -- Exclude rejected and unapproved requisitions; only show approved/active jobs
    AND ISNULL(req.isDisapproved, 0) = 0
    AND ISNULL(req.RequisitionStatus, '') <> 'Rejected'
    AND ISNULL(req.WorkflowStatus, '') <> 'Rejected'
    AND (req.isApproved = 1 OR req.WorkflowStatus IN ('Active', 'Approved'))
    ORDER BY req.dated DESC;

    -- 4. Result Set 3: Sourcing Vendors (STRICTLY Company-Wise and Location-Wise)
    IF @ResolvedLocId IS NOT NULL AND @ResolvedLocId <> ''
    BEGIN
        SELECT DISTINCT
            cd.pk_recId                                                       AS vendorId,
            COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
            ISNULL(cd.Vendor_Code, '')                                        AS vendorCode
        FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
        INNER JOIN dbo.Vendor_Location_Mapping vlm WITH (NOLOCK) 
                ON vlm.fk_VendorId = CAST(cd.pk_recId AS NVARCHAR(50))
        WHERE cd.IsVendor = 1
          AND (cd.fk_companyId = @CompanyCode OR cd.CompanyId = @CompanyCode OR @CompanyCode IS NULL)
          AND vlm.fk_LocationId = @ResolvedLocId
        ORDER BY vendorName ASC;
    END
    ELSE
    BEGIN
        SELECT DISTINCT
            cd.pk_recId                                                       AS vendorId,
            COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
            ISNULL(cd.Vendor_Code, '')                                        AS vendorCode
        FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
        WHERE cd.IsVendor = 1
          AND (cd.fk_companyId = @CompanyCode OR cd.CompanyId = @CompanyCode OR @CompanyCode IS NULL)
          AND cd.Vendor_Name IS NOT NULL AND LTRIM(RTRIM(cd.Vendor_Name)) <> ''
        ORDER BY vendorName ASC;
    END;

    -- 5. Result Set 4: Active Locations for Company (For Public Walk-In Hub Filter)
    SELECT 
        loc.pk_locid AS locationId,
        loc.locname AS locationName,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(st.description, 'Operational Hub') AS state,
        ISNULL(zn.zoneDescription, 'General Zone') AS zone
    FROM dbo.Location_Mst loc WITH (NOLOCK)
    LEFT JOIN dbo.SAL_State_Mst st WITH (NOLOCK) ON TRY_CAST(loc.fk_stateid AS SMALLINT) = st.pk_stateid
    LEFT JOIN dbo.SAL_Zone_Mst zn WITH (NOLOCK) ON TRY_CAST(loc.fk_zoneId AS BIGINT) = zn.pk_zoneId
    WHERE (loc.fk_companyId = @CompanyCode OR @CompanyCode IS NULL OR @CompanyCode = '')
      AND loc.locname IS NOT NULL AND LTRIM(RTRIM(loc.locname)) <> ''
    ORDER BY loc.locname ASC;
END;
GO

PRINT '>>> Updating dbo.usp_REC_SubmitWalkInCandidate...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitWalkInCandidate
    @CandidateName NVARCHAR(200),
    @MobileNumber NVARCHAR(50),
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

    -- Sanitize Mobile Number
    SET @MobileNumber = REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@MobileNumber)), '+91', ''), '-', ''), ' ', ''), '+', '');
    IF LEN(@MobileNumber) > 10
    BEGIN
        SET @MobileNumber = RIGHT(@MobileNumber, 10);
    END

    -- Sanitize Aadhaar Number (if provided)
    SET @AadhaarNo = CASE 
        WHEN @AadhaarNo IS NOT NULL AND LTRIM(RTRIM(@AadhaarNo)) <> '' 
        THEN REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', '') 
        ELSE NULL 
    END;

    SET @CandidateName = LTRIM(RTRIM(@CandidateName));

    -- ── 1. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Applications) ──────
    DECLARE @ExistingAppName NVARCHAR(200);
    DECLARE @ExistingAppStatus NVARCHAR(100);
    DECLARE @ExistingAppJob NVARCHAR(200);

    SELECT TOP 1
        @ExistingAppName = CandidateName,
        @ExistingAppStatus = ISNULL(InterviewStatus, Stage),
        @ExistingAppJob = Designation
    FROM REC_Candidate_Applications
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
            'Mobile Number ' + @MobileNumber + ' already exists (' + @ExistingAppName + ' - ' + ISNULL(@ExistingAppStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 2. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Details) ───────────
    DECLARE @ExistingDetName NVARCHAR(200);
    DECLARE @ExistingDetStatus NVARCHAR(100);

    SELECT TOP 1
        @ExistingDetName = candidate_name,
        @ExistingDetStatus = status
    FROM REC_Candidate_Details
    WHERE (IsVendor = 0 OR IsVendor IS NULL)
      AND (
        RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
        OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      )
    ORDER BY pk_recId DESC;

    IF @ExistingDetName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingDetName AS CandidateName,
            'Spot Candidate' AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' is already registered under ' + @ExistingDetName + '. Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 3. DUPLICATE AADHAAR NUMBER CHECK (If Provided) ────────────────────
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @AadhaarDupName NVARCHAR(200);
        DECLARE @AadhaarDupStatus NVARCHAR(100);

        SELECT TOP 1 
            @AadhaarDupName = CandidateName,
            @AadhaarDupStatus = ISNULL(InterviewStatus, Stage)
        FROM REC_Candidate_Applications
        WHERE REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', '') = @AadhaarNo
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
    END

    -- ── 4. RESOLVE VENDOR DETAILS (Strictly Optional) ──────────────────────
    DECLARE @IsVendorSelected BIT = 0;
    IF @VendorId IS NOT NULL AND @VendorId <> '' AND @VendorId <> 'DIRECT' AND @VendorId <> 'V-DIR-01'
    BEGIN
        SET @IsVendorSelected = 1;
        IF @VendorName IS NULL OR @VendorName = '' OR @VendorName = 'Direct Walk-In'
        BEGIN
            SELECT TOP 1 @VendorName = Vendor_Name 
            FROM REC_Candidate_Details 
            WHERE (pk_recId = @VendorId OR Vendor_Code = @VendorId) AND IsVendor = 1;
        END
    END
    ELSE
    BEGIN
        SET @VendorName = 'Direct Walk-In / Self';
    END

    -- ── 5. RESOLVE REQUISITION, LOCATION & COMPANY ─────────────────────────
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
        FROM Location_Mst 
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

    -- If companyId is missing or numeric '1', dynamically resolve from Job Requisition, Location, or Common_Client_Details (Zero Hardcoding)
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

    -- ── 6. INSERT INTO REC_Candidate_Applications ──────────────────────────
    INSERT INTO REC_Candidate_Applications (
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
        @ValidReqId,
        @CandidateName,
        @MobileNumber,
        @AadhaarNo,
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

    -- ── 7. INSERT INTO REC_Candidate_Details ───────────────────────────────
    DECLARE @NewRecId VARCHAR(50) = 'REC-' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(20));
    DECLARE @DefaultUserId VARCHAR(50) = (SELECT TOP 1 pk_userId FROM UM_Users_Mst);

    INSERT INTO REC_Candidate_Details (
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
        NULL,
        @CandidateName,
        @MobileNumber,
        @AadhaarNo,
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

PRINT 'Procedures updated successfully.';
GO
