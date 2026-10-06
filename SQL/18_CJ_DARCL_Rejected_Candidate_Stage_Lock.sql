-- =============================================================================
-- Migration 18: Rejected Candidate Stays at Current Stage in Red & Locked (Cannot Move)
-- Standard: 100% Company-Specific, Zero Hardcoding, Mandatory SQL Script Tracking
-- =============================================================================

USE HRBook_22;
GO

PRINT 'Starting Migration 18: Rejected Candidate Stage Lock & Job Table fk_companyId...';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Add fk_companyId in Job Tables if missing
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 1: Checking fk_companyId in Job Tables...';

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_companyId'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_companyId NVARCHAR(50) NULL;
    PRINT 'Added fk_companyId to REC_JobRequisition_Mst.';
END
ELSE
BEGIN
    PRINT 'fk_companyId already exists in REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Open_Newjob' AND COLUMN_NAME = 'fk_companyId'
)
BEGIN
    ALTER TABLE dbo.REC_Open_Newjob ADD fk_companyId NVARCHAR(50) NULL;
    PRINT 'Added fk_companyId to REC_Open_Newjob.';
END
ELSE
BEGIN
    PRINT 'fk_companyId already exists in REC_Open_Newjob.';
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Ensure IsRejected and RejectionStage columns exist in REC_Candidate_Applications
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 2: Adding IsRejected and RejectionStage columns to REC_Candidate_Applications...';

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'IsRejected'
)
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD IsRejected BIT NULL DEFAULT 0;
    PRINT 'Added IsRejected to REC_Candidate_Applications.';
END;

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'RejectionStage'
)
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD RejectionStage NVARCHAR(50) NULL;
    PRINT 'Added RejectionStage to REC_Candidate_Applications.';
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Backfill past rejected candidates so they revert to their actual stage
-- (Candidate stays on their stage marked as Rejected, instead of moving to a generic 'Rejected' stage)
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 3: Backfilling previously rejected candidates to their active stage...';

UPDATE ca
SET ca.IsRejected = 1,
    ca.RejectionStage = COALESCE(cla.PreviousStage, 'Applied'),
    ca.Stage = CASE 
                  WHEN ca.Stage = 'Rejected' THEN COALESCE(cla.PreviousStage, 'Applied') 
                  ELSE ca.Stage 
               END
FROM dbo.REC_Candidate_Applications ca
OUTER APPLY (
    SELECT TOP 1 PreviousStage 
    FROM dbo.REC_Candidate_Lifecycle_Audit 
    WHERE fk_appId = ca.pk_appId AND ActionType = 'REJECT' AND PreviousStage <> 'Rejected'
    ORDER BY pk_auditId DESC
) cla
WHERE ca.Stage = 'Rejected' OR ca.InterviewStatus = 'Rejected';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Update dbo.usp_REC_RejectCandidate
-- When rejected, candidate REMAINS on their current stage, flagged as IsRejected = 1
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 4: Updating dbo.usp_REC_RejectCandidate...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_RejectCandidate
    @AppId           BIGINT,
    @RejectionReason NVARCHAR(150),
    @Remarks         NVARCHAR(MAX),
    @CooloffPolicy   NVARCHAR(50)  = '90_Days', -- 90_Days / Immediate_Other_Roles / Blacklist
    @NotifyCandidate BIT           = 1,
    @RejectedBy      NVARCHAR(100) = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @CandidateName NVARCHAR(150);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @CandidateName = CandidateName
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- User Rule: In case of reject, candidate STAYS on that stage, marked in red & locked
    UPDATE dbo.REC_Candidate_Applications SET
        -- Keep Stage unchanged at @CurrentStage
        IsRejected       = 1,
        RejectionStage   = @CurrentStage,
        InterviewStatus  = 'Rejected',
        RejectionReason  = @RejectionReason,
        RejectionRemarks = @Remarks,
        CooloffPolicy    = @CooloffPolicy,
        LastUpdatedDate  = GETDATE(),
        LastUpdatedBy    = @RejectedBy
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Insert Audit Entry (Step 15)
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'REJECT', @CurrentStage, CONCAT(@CurrentStage, ' (Rejected)'),
        NULL, @RejectedBy, 'Site HR Admin',
        CONCAT('Candidate Rejected at stage [', @CurrentStage, '] | Reason: [', @RejectionReason, '] | Remarks: ', @Remarks),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success, 
        CONCAT('Candidate ', @CandidateName, ' marked as Rejected at ', @CurrentStage, ' stage. Candidate remains locked in red at this stage.') AS Message,
        @AppId AS AppId,
        @CurrentStage AS Stage,
        1 AS IsRejected,
        @RejectionReason AS RejectionReason;
END;
GO

PRINT 'dbo.usp_REC_RejectCandidate successfully updated.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Update dbo.usp_REC_GetCandidatePipelineRoster
-- Return IsRejected and RejectionStage, keeping candidates in their respective stage
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 5: Updating dbo.usp_REC_GetCandidatePipelineRoster...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidatePipelineRoster
    @CompanyId   NVARCHAR(50),
    @ReqId       BIGINT       = NULL,
    @StageFilter NVARCHAR(50) = 'ALL',
    @SearchQuery NVARCHAR(100)= NULL
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
        ca.VendorName             AS vendorName,
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
    FROM dbo.REC_Candidate_Applications ca
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
          OR (@StageFilter = 'INTERVIEW' AND ca.Stage IN ('Interview_Scheduled', 'Interview_Completed'))
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
          OR ca.CandidateTags LIKE CONCAT('%', @SearchQuery, '%')
      )
    ORDER BY ca.pk_appId DESC;
END;
GO

PRINT 'dbo.usp_REC_GetCandidatePipelineRoster successfully updated.';
PRINT 'Migration 18 completed successfully!';
GO
