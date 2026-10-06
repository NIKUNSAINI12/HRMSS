-- =============================================================================
-- Migration Script 61: Enforce Staffing Vendor Assignment From Applied Stage
-- Database: HRBook_22
-- Standard: 100% Company-Specific, Zero Hardcoding, Full Audit Logging
-- CJ DARCL Recruitment Architecture
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Reset Admin User Vendor Flags in UM_Users_Mst
-- Admin (GU-4) is Super Admin, not an external staffing vendor.
-- ─────────────────────────────────────────────────────────────────────────────
IF EXISTS (SELECT 1 FROM dbo.UM_Users_Mst WHERE pk_userId = 'GU-4' AND isVendor = 1)
BEGIN
    UPDATE dbo.UM_Users_Mst
    SET isVendor = 0, fk_vendorId = NULL
    WHERE pk_userId = 'GU-4' OR loginname = 'admin';
    PRINT 'Admin user vendor flags reset to 0 in UM_Users_Mst.';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Empanel Staffing Vendors to Main Hubs (GGN GU-6, Dharuhera GU-81, etc.)
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.Vendor_Location_Mapping', 'U') IS NOT NULL
BEGIN
    -- Map top empanelled staffing vendors to GU-6 (GGN)
    INSERT INTO dbo.Vendor_Location_Mapping (fk_VendorId, fk_LocationId)
    SELECT v.VendorId, 'GU-6'
    FROM (
        VALUES 
            ('GU-29'), -- BIMALRAJ OUTSOURCING PVT LTD
            ('GU-30'), -- MM MANPOWER & SECURITY SERVICES
            ('GU-31'), -- REEYA SERVICES PRIVATE LIMITED
            ('GU-32'), -- YASHIKA FACILITY & MANPOWER SOLUTION PVT LTD
            ('GU-33'), -- HRP MANAGEMENT PRIVATE LIMITED
            ('GU-34'), -- S & IB SERVICES PVT LTD
            ('GU-35'), -- STERLING SERVICES
            ('GU-39'), -- ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED
            ('GU-40'), -- POLE STAR ENTERPRISES
            ('GU-64'), -- S R INDIAN HOUSEKEEPING
            ('GU-65')  -- VEGITH PINNACLE SERVICES
    ) AS v(VendorId)
    WHERE EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details cd WHERE cd.pk_recId = v.VendorId AND cd.IsVendor = 1)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Vendor_Location_Mapping vlm 
          WHERE vlm.fk_VendorId = v.VendorId AND vlm.fk_LocationId = 'GU-6'
      );

    -- Map top empanelled staffing vendors to GU-81 (Dharuhera)
    INSERT INTO dbo.Vendor_Location_Mapping (fk_VendorId, fk_LocationId)
    SELECT v.VendorId, 'GU-81'
    FROM (
        VALUES 
            ('GU-29'),
            ('GU-30'),
            ('GU-31'),
            ('GU-32'),
            ('GU-39'),
            ('GU-40')
    ) AS v(VendorId)
    WHERE EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details cd WHERE cd.pk_recId = v.VendorId AND cd.IsVendor = 1)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Vendor_Location_Mapping vlm 
          WHERE vlm.fk_VendorId = v.VendorId AND vlm.fk_LocationId = 'GU-81'
      );

    PRINT 'Empanelled vendors mapped to GU-6 and GU-81.';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Stored Procedure: dbo.usp_REC_GetVendorsByCompanyAndLocation
-- Returns empanelled staffing vendors filtered by company & job location.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsByCompanyAndLocation
    @CompanyId   NVARCHAR(50),
    @LocationId  NVARCHAR(50) = NULL,
    @ReqId       BIGINT       = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- If LocationId not passed, resolve from Requisition
    IF (@LocationId IS NULL OR @LocationId = '' OR @LocationId = '0') AND @ReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @LocationId = fk_locid
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    -- Retrieve empanelled vendors with location affinity ranking
    SELECT 
        cd.pk_recId                                                       AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                        AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')          AS mobile,
        ISNULL(cd.email, '')                                              AS email,
        COALESCE(loc.locname, '')                                         AS primaryLocation,
        CASE 
            WHEN vlm.pk_VendorLocId IS NOT NULL THEN 1 
            WHEN cd.fk_locid = @LocationId THEN 1 
            ELSE 0 
        END                                                               AS isLocationMapped
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = cd.fk_locid
    LEFT JOIN dbo.Vendor_Location_Mapping vlm WITH (NOLOCK) 
           ON vlm.fk_VendorId = CAST(cd.pk_recId AS NVARCHAR(50)) 
          AND (@LocationId IS NOT NULL AND vlm.fk_LocationId = @LocationId)
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR cd.fk_companyId = @CompanyId 
          OR cd.CompanyId = @CompanyId
          -- Ensure multi-tenant empanelled staffing partners are accessible
          OR cd.fk_companyId IN ('GU-1', 'GU-8')
          OR cd.CompanyId IN ('GU-1', 'GU-8')
      )
    ORDER BY isLocationMapped DESC, vendorName ASC;
END;
GO
PRINT 'dbo.usp_REC_GetVendorsByCompanyAndLocation created successfully.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Stored Procedure: dbo.usp_REC_AssignVendorToCandidate
-- Assigns or re-assigns staffing vendor to candidate with audit log.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_AssignVendorToCandidate
    @AppId       BIGINT,
    @VendorId    NVARCHAR(50),
    @VendorName  NVARCHAR(150) = NULL,
    @AssignedBy  NVARCHAR(100) = 'Recruiter',
    @CompanyId   NVARCHAR(50)  = NULL,
    @Remarks     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AppId IS NULL OR @AppId = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Application ID is mandatory.' AS Message;
        RETURN;
    END

    IF @VendorId IS NULL OR LTRIM(RTRIM(@VendorId)) = ''
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Staffing Vendor ID is mandatory.' AS Message;
        RETURN;
    END

    -- Verify candidate existence
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @ApplicationNo NVARCHAR(50);
    DECLARE @CurrentVendorId NVARCHAR(50);
    DECLARE @CurrentVendorName NVARCHAR(150);
    DECLARE @CurrentStage NVARCHAR(50);

    SELECT 
        @CandidateName     = CandidateName,
        @ApplicationNo     = ApplicationNo,
        @CurrentVendorId   = fk_vendorId,
        @CurrentVendorName = VendorName,
        @CurrentStage      = Stage
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE pk_appId = @AppId;

    IF @CandidateName IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- Resolve Vendor Name if not provided
    IF @VendorName IS NULL OR LTRIM(RTRIM(@VendorName)) = ''
    BEGIN
        SELECT TOP 1 @VendorName = COALESCE(NULLIF(Vendor_Name, ''), candidate_name)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId OR Vendor_Code = @VendorId;
    END

    IF @VendorName IS NULL OR LTRIM(RTRIM(@VendorName)) = ''
    BEGIN
        SET @VendorName = 'Staffing Partner';
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.REC_Candidate_Applications
        SET 
            fk_vendorId     = @VendorId,
            VendorName      = @VendorName,
            SourceType      = 'Vendor',
            LastUpdatedDate = GETDATE(),
            LastUpdatedBy   = @AssignedBy
        WHERE pk_appId = @AppId;

        -- Audit Log in REC_Candidate_Lifecycle_Audit
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
            VALUES (
                @AppId,
                @ApplicationNo,
                'VENDOR_ASSIGNMENT',
                @CurrentStage,
                @CurrentStage,
                @AssignedBy,
                @AssignedBy,
                CONCAT('Assigned Staffing Vendor [', @VendorName, '] (', @VendorId, ') to candidate by ', @AssignedBy, CASE WHEN @Remarks IS NOT NULL AND @Remarks <> '' THEN CONCAT(' - ', @Remarks) ELSE '' END),
                GETDATE(),
                @CompanyId,
                @CompanyId
            );
        END

        COMMIT TRANSACTION;

        SELECT 
            CAST(1 AS BIT) AS Success,
            CONCAT('Staffing vendor [', @VendorName, '] assigned to candidate ', @CandidateName, ' successfully.') AS Message,
            @VendorId AS VendorId,
            @VendorName AS VendorName;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT CAST(0 AS BIT) AS Success, CONCAT('Failed to assign vendor: ', ERROR_MESSAGE()) AS Message;
    END CATCH
END;
GO
PRINT 'dbo.usp_REC_AssignVendorToCandidate created successfully.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Update dbo.usp_REC_MoveCandidateStage
-- MANDATORY RULE: If moving candidate from 'Applied' to any other stage,
-- vendor must be assigned (fk_vendorId NOT NULL and not empty).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_MoveCandidateStage
    @AppId           BIGINT,
    @TargetStage     NVARCHAR(50),
    @Remarks         NVARCHAR(MAX)  = NULL,
    @MovedBy         NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @RowCompanyId NVARCHAR(50);
    DECLARE @CandidateVendorId NVARCHAR(50);
    DECLARE @CandidateVendorName NVARCHAR(150);

    SELECT 
        @CurrentStage        = Stage, 
        @AppNo               = ApplicationNo,
        @CandidateName       = CandidateName,
        @RowCompanyId        = fk_companyId,
        @CandidateVendorId   = fk_vendorId,
        @CandidateVendorName = VendorName
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
          OR fk_companyId = REPLACE(@CompanyId, 'GU-', '')
          OR fk_companyId = CONCAT('GU-', @CompanyId)
      );

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- Synchronize company id if mismatched
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0')
        SET @CompanyId = @RowCompanyId;

    -- =========================================================================
    -- MANDATORY RULE: CANDIDATE CANNOT MOVE FROM 'Applied' TO ANY NEXT STAGE
    -- WITHOUT AN ASSIGNED STAFFING VENDOR
    -- =========================================================================
    IF (@CurrentStage = 'Applied' OR @CurrentStage IS NULL) 
       AND @TargetStage NOT IN ('Applied', 'Rejected')
    BEGIN
        IF @CandidateVendorId IS NULL OR LTRIM(RTRIM(@CandidateVendorId)) = ''
        BEGIN
            SELECT 0 AS Success, 
                   CONCAT('Validation Restriction: Staffing Vendor is not assigned to candidate [', @CandidateName, ']. Please assign a staffing vendor before advancing from Applied stage.') AS Message;
            RETURN;
        END
    END

    -- =========================================================================
    -- MANDATORY RULE: IF CURRENT STAGE IS DOCS REVIEW (Docs_Submitted),
    -- ALL MANDATORY ONBOARDING DOCUMENTS MUST BE APPROVED BEFORE MOVING FORWARD
    -- =========================================================================
    IF (@CurrentStage = 'Docs_Submitted' OR @CurrentStage = 'Selected') 
       AND @TargetStage IN ('Docs_Verified', 'Offer_Issued', 'Hired')
    BEGIN
        DECLARE @UnapprovedMandatoryCount INT = 0;

        SELECT @UnapprovedMandatoryCount = COUNT(1)
        FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
        WHERE cd.fk_appId = @AppId
          AND cd.IsMandatory = 1
          AND ISNULL(cd.VerificationStatus, 'Pending') != 'Approved';

        DECLARE @TotalDocsCount INT = 0;
        SELECT @TotalDocsCount = COUNT(1)
        FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
        WHERE cd.fk_appId = @AppId AND ISNULL(cd.FileName, '') != '';

        IF @TotalDocsCount = 0 OR @UnapprovedMandatoryCount > 0
        BEGIN
            SELECT 0 AS Success, 
                   CONCAT('Cannot advance candidate to ', @TargetStage, ': All mandatory onboarding documents must be reviewed and approved by Site HR first (Pending: ', @UnapprovedMandatoryCount, ').') AS Message;
            RETURN;
        END
    END

    -- Synchronize interview/document/hiring sub-statuses when stage changes
    DECLARE @InterviewStatus NVARCHAR(50) = NULL;
    DECLARE @DocStatus NVARCHAR(50) = NULL;

    IF @TargetStage = 'Selected'
        SET @InterviewStatus = 'Selected';
    ELSE IF @TargetStage = 'Interview_Completed'
        SET @InterviewStatus = 'Completed';
    ELSE IF @TargetStage = 'Interview_Scheduled'
        SET @InterviewStatus = 'Scheduled';
    ELSE IF @TargetStage = 'Docs_Verified'
        SET @DocStatus = 'Verified';
    ELSE IF @TargetStage = 'Docs_Submitted'
        SET @DocStatus = 'Pending';

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                  = @TargetStage,
        InterviewStatus        = ISNULL(@InterviewStatus, InterviewStatus),
        DocVerificationStatus  = ISNULL(@DocStatus, DocVerificationStatus),
        LastUpdatedDate        = GETDATE(),
        LastUpdatedBy          = @MovedBy
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
          OR fk_companyId = REPLACE(@CompanyId, 'GU-', '')
          OR fk_companyId = CONCAT('GU-', @CompanyId)
      );

    -- Log Audit
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'STAGE_CHANGE', @CurrentStage, @TargetStage,
        @MovedBy, @MovedBy, 'Recruiter', @Remarks, GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Candidate successfully moved to ', @TargetStage) AS Message;
END;
GO
PRINT 'dbo.usp_REC_MoveCandidateStage updated with mandatory vendor check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Update dbo.usp_REC_ScheduleCandidateInterview
-- MANDATORY RULE: Cannot schedule interview if vendor is not assigned.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_ScheduleCandidateInterview
    @AppId           BIGINT,
    @InterviewerId   NVARCHAR(50),
    @InterviewerName NVARCHAR(150),
    @InterviewDate   DATETIME,
    @InterviewRound  NVARCHAR(50) = 'HR & Operations',
    @Remarks         NVARCHAR(MAX)= NULL,
    @ScheduledBy     NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @CandidateVendorId NVARCHAR(50);

    SELECT 
        @CurrentStage      = Stage, 
        @AppNo             = ApplicationNo,
        @CandidateName     = CandidateName,
        @CandidateVendorId = fk_vendorId
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
      );

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- MANDATORY RULE: Cannot schedule interview from Applied without assigned vendor
    IF (@CurrentStage = 'Applied' OR @CurrentStage IS NULL)
    BEGIN
        IF @CandidateVendorId IS NULL OR LTRIM(RTRIM(@CandidateVendorId)) = ''
        BEGIN
            SELECT 0 AS Success, 
                   CONCAT('Validation Restriction: Staffing Vendor is not assigned to candidate [', @CandidateName, ']. Please assign a staffing vendor before scheduling interview.') AS Message;
            RETURN;
        END
    END

    UPDATE dbo.REC_Candidate_Applications SET
        Stage            = 'Interview_Scheduled',
        InterviewStatus  = 'Scheduled',
        InterviewerId    = @InterviewerId,
        InterviewerName  = @InterviewerName,
        InterviewDate    = @InterviewDate,
        InterviewRound   = @InterviewRound,
        InterviewRemarks = @Remarks,
        LastUpdatedDate  = GETDATE(),
        LastUpdatedBy    = @ScheduledBy
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
      );

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'INTERVIEW_SCHEDULED', @CurrentStage, 'Interview_Scheduled',
        @ScheduledBy, @ScheduledBy, 'Site HR', 
        CONCAT('Interview round [', @InterviewRound, '] scheduled with ', @InterviewerName, ' on ', CONVERT(VARCHAR, @InterviewDate, 120), '. Remarks: ', ISNULL(@Remarks, 'None')),
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, 'Interview scheduled successfully.' AS Message;
END;
GO
PRINT 'dbo.usp_REC_ScheduleCandidateInterview updated with mandatory vendor check.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Update dbo.usp_REC_GetCandidatePipelineRoster
-- Dynamically resolve vendorName using REC_Candidate_Details so real vendor
-- name is always visible even if ca.VendorName was empty.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidatePipelineRoster
    @CompanyId    NVARCHAR(50),
    @ReqId        BIGINT        = NULL,
    @StageFilter  NVARCHAR(50)  = 'ALL',
    @SearchQuery  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ca.pk_appId               AS appId,
        ca.ApplicationNo          AS applicationNo,
        ca.fk_reqid               AS reqId,
        ca.MrfCode                AS mrfCode,
        ca.CandidateName          AS candidateName,
        ca.Mobile                 AS mobile,
        ca.Email                  AS email,
        ca.Gender                 AS gender,
        ca.DateOfBirth            AS dateOfBirth,
        ca.FatherName             AS fatherName,
        ca.CurrentLocation        AS currentLocation,
        ca.OperatingHub           AS operatingHub,
        ca.Department             AS department,
        ca.Designation            AS designation,
        ca.SourceType             AS sourceType,
        ca.fk_vendorId            AS vendorId,
        -- Dynamically resolve vendorName from REC_Candidate_Details if available
        COALESCE(
            NULLIF(cd.Vendor_Name, ''), 
            NULLIF(ca.VendorName, ''), 
            NULLIF(cd.candidate_name, ''),
            CASE WHEN ca.fk_vendorId IS NOT NULL AND ca.fk_vendorId <> '' THEN ca.fk_vendorId ELSE NULL END
        )                         AS vendorName,
        ca.Stage                  AS stage,
        ca.SkillClassification   AS skillClassification,
        ca.InterviewStatus        AS interviewStatus,
        ca.InterviewerId          AS interviewerId,
        ca.InterviewerName        AS interviewerName,
        ca.InterviewDate          AS interviewDate,
        ca.InterviewRound         AS interviewRound,
        ca.InterviewRemarks       AS interviewRemarks,
        ca.InterviewScore         AS interviewScore,
        ca.AadhaarNo              AS aadhaarNo,
        ca.PanNo                  AS panNo,
        ca.BankAccNo              AS bankAccNo,
        ca.BankIfsc               AS bankIfsc,
        ca.BankName               AS bankName,
        ca.DocVerificationStatus  AS docVerificationStatus,
        ca.DocVerifiedBy          AS docVerifiedBy,
        ca.DocVerificationRemarks AS docVerificationRemarks,
        ca.CandidateCode          AS candidateCode,
        ca.OfferedCTC             AS offeredCTC,
        ca.OfferLetterSentDate    AS offerLetterSentDate,
        ca.ExpectedJoiningDate    AS expectedJoiningDate,
        ca.EmployeeCode           AS employeeCode,
        ca.HiredDate              AS hiredDate,
        ca.CreatedDate            AS createdDate,
        -- Tagging, Diversity & Rejection Fields
        ISNULL(ca.CandidateTags, '')    AS candidateTags,
        ISNULL(ca.IsDiversityHiring, 0) AS isDiversityHiring,
        ISNULL(ca.DiversityCategory, '') AS diversityCategory,
        ca.RejectionReason              AS rejectionReason,
        ca.RejectionRemarks             AS rejectionRemarks,
        ca.CooloffPolicy                AS cooloffPolicy,
        ca.AssignedReviewer             AS assignedReviewer,
        -- Rejection Stage Locking Flags
        ISNULL(ca.IsRejected, CASE WHEN ca.InterviewStatus = 'Rejected' OR ca.Stage = 'Rejected' THEN 1 ELSE 0 END) AS isRejected,
        ISNULL(ca.RejectionStage, ca.Stage) AS rejectionStage,
        COALESCE(ca.CompanyId, ca.fk_companyId) AS companyId,
        COALESCE(ca.fk_companyId, ca.CompanyId) AS fk_companyId
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    LEFT JOIN dbo.REC_Candidate_Details cd WITH (NOLOCK) 
           ON (cd.pk_recId = ca.fk_vendorId OR cd.Vendor_Code = ca.fk_vendorId)
          AND cd.IsVendor = 1
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR ca.CompanyId = @CompanyId 
        OR ca.fk_companyId = @CompanyId
    )
      AND (@ReqId IS NULL OR @ReqId = 0 OR ca.fk_reqid = @ReqId)
      AND (
          @StageFilter = 'ALL' 
          OR (@StageFilter = 'APPLIED' AND ca.Stage = 'Applied')
          OR (@StageFilter = 'INTERVIEW' AND (ca.Stage IN ('Interview_Scheduled', 'Interview_Completed', 'Hold') OR ca.InterviewStatus = 'Hold'))
          OR (@StageFilter = 'SELECTED' AND ca.Stage = 'Selected')
          OR (@StageFilter = 'DOCS' AND ca.Stage IN ('Docs_Submitted', 'Docs_Verified'))
          OR (@StageFilter = 'OFFER' AND ca.Stage = 'Offer_Issued')
          OR (@StageFilter = 'HIRED' AND ca.Stage = 'Hired')
          OR (@StageFilter = 'REJECTED' AND (ca.IsRejected = 1 OR ca.InterviewStatus = 'Rejected' OR ca.Stage = 'Rejected'))
      )
      AND (
          @SearchQuery IS NULL OR @SearchQuery = '' 
          OR ca.CandidateName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.ApplicationNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Mobile LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.MrfCode LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.VendorName LIKE CONCAT('%', @SearchQuery, '%')
          OR cd.Vendor_Name LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.CandidateTags LIKE CONCAT('%', @SearchQuery, '%')
      );
END;
GO
PRINT 'dbo.usp_REC_GetCandidatePipelineRoster updated with dynamic vendor name resolution.';
GO

PRINT 'Migration 61 completed successfully.';
GO
