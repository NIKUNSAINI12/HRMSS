-- =============================================================================
-- Migration 13: CJ DARCL Candidate Tagging, Stage Progression & Rejection Architecture
-- Standard: 100% Company-Specific, Zero Hardcoding, Zero Inline SQL
-- Covers:
--   1. Tagging Candidates (Skill Classification, Diversity Hiring, Tags & Badges, Assignee)
--   2. Move Candidate to Next Stage (Flexible Stage Progression with Audit Trail)
--   3. Comprehensive Candidate Rejection (Reason Category, Detailed Feedback, Cool-off Policy)
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: SCHEMA ALTERATIONS (ADD REJECTION, TAGS & DIVERSITY FIELDS)
-- ─────────────────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'CandidateTags')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD CandidateTags NVARCHAR(250) NULL DEFAULT '';
    PRINT 'Added CandidateTags to REC_Candidate_Applications';
END
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'IsDiversityHiring')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD IsDiversityHiring BIT NOT NULL DEFAULT 0;
    PRINT 'Added IsDiversityHiring to REC_Candidate_Applications';
END
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'RejectionReason')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD RejectionReason NVARCHAR(150) NULL;
    PRINT 'Added RejectionReason to REC_Candidate_Applications';
END
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'RejectionRemarks')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD RejectionRemarks NVARCHAR(MAX) NULL;
    PRINT 'Added RejectionRemarks to REC_Candidate_Applications';
END
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'CooloffPolicy')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD CooloffPolicy NVARCHAR(50) NULL DEFAULT '90_Days';
    PRINT 'Added CooloffPolicy to REC_Candidate_Applications';
END
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'AssignedReviewer')
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD AssignedReviewer NVARCHAR(150) NULL;
    PRINT 'Added AssignedReviewer to REC_Candidate_Applications';
END
GO


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: STORED PROCEDURE - TAG CANDIDATE TO JOB / UPDATE CANDIDATE TAGS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_TagCandidate
    @AppId                BIGINT,
    @ReqId                BIGINT         = NULL,
    @SkillClassification  NVARCHAR(50)   = 'Semi-Skilled',
    @CandidateTags        NVARCHAR(250)  = NULL,
    @IsDiversityHiring    BIT            = 0,
    @AssignedReviewer     NVARCHAR(150)  = NULL,
    @Remarks              NVARCHAR(MAX)  = NULL,
    @TaggedBy             NVARCHAR(100)  = 'Recruiter',
    @CompanyId            NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @OldMrf NVARCHAR(100);
    DECLARE @TargetMrf NVARCHAR(100);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @OldMrf = MrfCode
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found for this company.' AS Message;
        RETURN;
    END

    -- If ReqId is provided and different from current, re-tag candidate to the new requisition
    IF @ReqId IS NOT NULL AND @ReqId > 0
    BEGIN
        SELECT @TargetMrf = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid))
        FROM dbo.REC_JobRequisition_Mst r
        WHERE r.pk_reqid = @ReqId;

        UPDATE dbo.REC_Candidate_Applications SET
            fk_reqid            = @ReqId,
            MrfCode             = ISNULL(@TargetMrf, MrfCode),
            SkillClassification = @SkillClassification,
            CandidateTags       = ISNULL(@CandidateTags, CandidateTags),
            IsDiversityHiring   = @IsDiversityHiring,
            AssignedReviewer    = ISNULL(@AssignedReviewer, AssignedReviewer),
            LastUpdatedDate     = GETDATE(),
            LastUpdatedBy       = @TaggedBy
        WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;
    END
    ELSE
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            SkillClassification = @SkillClassification,
            CandidateTags       = ISNULL(@CandidateTags, CandidateTags),
            IsDiversityHiring   = @IsDiversityHiring,
            AssignedReviewer    = ISNULL(@AssignedReviewer, AssignedReviewer),
            LastUpdatedDate     = GETDATE(),
            LastUpdatedBy       = @TaggedBy
        WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;
    END

    -- Insert Audit Entry
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'TAG_CANDIDATE', @CurrentStage, @CurrentStage,
        NULL, @TaggedBy, 'Recruiter',
        CONCAT('Candidate tags updated: Skill=', @SkillClassification, 
               ' | Tags=', ISNULL(@CandidateTags, 'None'), 
               ' | Diversity=', CASE WHEN @IsDiversityHiring = 1 THEN 'Yes' ELSE 'No' END,
               ' | Reviewer=', ISNULL(@AssignedReviewer, 'Unassigned'),
               CASE WHEN @Remarks IS NOT NULL THEN CONCAT(' | Note: ', @Remarks) ELSE '' END),
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Candidate tagged successfully with skill classification, tags, and reviewer.' AS Message,
        @AppId AS AppId,
        @SkillClassification AS SkillClassification,
        @CandidateTags AS CandidateTags;
END;
GO


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 3: STORED PROCEDURE - MOVE CANDIDATE TO NEXT STAGE (FLEXIBLE PROGRESSION)
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

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
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
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Insert Audit Entry
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'STAGE_TRANSITION', @CurrentStage, @TargetStage,
        NULL, @MovedBy, 'Recruiter',
        CONCAT('Candidate moved from [', @CurrentStage, '] to [', @TargetStage, ']. ', ISNULL(@Remarks, 'Stage progression confirmed.')),
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        CONCAT('Candidate moved to ', @TargetStage, ' stage successfully.') AS Message,
        @AppId AS AppId,
        @TargetStage AS NewStage;
END;
GO


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 4: STORED PROCEDURE - REJECT CANDIDATE (WITH REASON, REMARKS, COOL-OFF)
-- ─────────────────────────────────────────────────────────────────────────────
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
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- Update Candidate to Rejected
    UPDATE dbo.REC_Candidate_Applications SET
        Stage            = 'Rejected',
        InterviewStatus  = 'Rejected',
        RejectionReason  = @RejectionReason,
        RejectionRemarks = @Remarks,
        CooloffPolicy    = @CooloffPolicy,
        LastUpdatedDate  = GETDATE(),
        LastUpdatedBy    = @RejectedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Insert Audit Entry (Step 15)
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'REJECT', @CurrentStage, 'Rejected',
        NULL, @RejectedBy, 'Recruiter',
        CONCAT('Rejection Decision: [', @RejectionReason, '] | Cool-off: [', @CooloffPolicy, '] | Remarks: ', @Remarks),
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        CONCAT('Candidate ', @CandidateName, ' rejected at ', @CurrentStage, ' stage. Feedback recorded.') AS Message,
        @AppId AS AppId,
        'Rejected' AS NewStage,
        @RejectionReason AS RejectionReason;
END;
GO


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 5: UPDATE usp_REC_GetCandidatePipelineRoster TO RETURN NEW FIELDS
-- ─────────────────────────────────────────────────────────────────────────────
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
        -- New Tagging, Diversity & Rejection Fields
        ISNULL(ca.CandidateTags, '')    AS candidateTags,
        ISNULL(ca.IsDiversityHiring, 0) AS isDiversityHiring,
        ca.RejectionReason              AS rejectionReason,
        ca.RejectionRemarks             AS rejectionRemarks,
        ca.CooloffPolicy                AS cooloffPolicy,
        ca.AssignedReviewer             AS assignedReviewer
    FROM dbo.REC_Candidate_Applications ca
    WHERE ca.fk_companyId = @CompanyId
      AND (@ReqId IS NULL OR @ReqId = 0 OR ca.fk_reqid = @ReqId)
      AND (
          @StageFilter = 'ALL' 
          OR (@StageFilter = 'APPLIED' AND ca.Stage = 'Applied')
          OR (@StageFilter = 'INTERVIEW' AND ca.Stage IN ('Interview_Scheduled', 'Interview_Completed'))
          OR (@StageFilter = 'SELECTED' AND ca.Stage = 'Selected')
          OR (@StageFilter = 'DOCS' AND ca.Stage IN ('Docs_Submitted', 'Docs_Verified'))
          OR (@StageFilter = 'OFFER' AND ca.Stage = 'Offer_Issued')
          OR (@StageFilter = 'HIRED' AND ca.Stage = 'Hired')
          OR (@StageFilter = 'REJECTED' AND ca.Stage = 'Rejected')
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
