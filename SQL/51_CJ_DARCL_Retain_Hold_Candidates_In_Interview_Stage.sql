-- ============================================================================
-- 51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql
-- Fix: Prevent Candidates with 'Hold' Decision from Disappearing
-- Retains Hold Candidates in 'Interview_Scheduled' Stage with InterviewStatus = 'Hold'
-- Updates usp_REC_SubmitInterviewEvaluation and usp_REC_GetCandidatePipelineRoster
-- ============================================================================

USE [HRBook_22];
GO

PRINT '1. Recovering existing Hold candidates back to Interview stage...';
UPDATE dbo.REC_Candidate_Applications
SET Stage = 'Interview_Scheduled',
    InterviewStatus = 'Hold'
WHERE Stage = 'Hold';
GO

PRINT '2. Updating dbo.usp_REC_SubmitInterviewEvaluation...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitInterviewEvaluation
    @AppId               BIGINT,
    @SkillClassification NVARCHAR(50)  = 'Semi-Skilled', -- Unskilled / Semi-Skilled / Skilled / Highly Skilled
    @Decision            NVARCHAR(50)  = 'Selected',     -- Selected / Rejected / Hold / Pending
    @Remarks             NVARCHAR(MAX) = 'Interview completed.',
    @Score               INT           = 80,
    @EvaluatorName       NVARCHAR(150) = 'Interviewer',
    @CompanyId           NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CleanCompId NVARCHAR(50) = REPLACE(ISNULL(@CompanyId, ''), 'GU-', '');
    DECLARE @PrefixedCompId NVARCHAR(50) = CASE WHEN @CleanCompId <> '' THEN 'GU-' + @CleanCompId ELSE '' END;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @ActualCompanyId NVARCHAR(50);

    -- 1. Try finding application matching company scope
    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @ActualCompanyId = COALESCE(CompanyId, fk_companyId, @CompanyId)
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId
      AND (
          @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
          OR CompanyId IN (@CompanyId, @CleanCompId, @PrefixedCompId)
          OR fk_companyId IN (@CompanyId, @CleanCompId, @PrefixedCompId)
      );

    -- 2. Fallback by pk_appId if company formatting differed in session
    IF @AppNo IS NULL
    BEGIN
        SELECT 
            @CurrentStage = Stage, 
            @AppNo = ApplicationNo,
            @ActualCompanyId = COALESCE(CompanyId, fk_companyId, @CompanyId)
        FROM dbo.REC_Candidate_Applications
        WHERE pk_appId = @AppId;
    END

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- 3. Determine next workflow stage based on interview decision:
    -- 'Hold' candidates MUST stay in 'Interview_Scheduled' with InterviewStatus = 'Hold'
    -- so they remain visible on the pipeline board under the Interview stage!
    DECLARE @NextStage NVARCHAR(50) = CASE 
        WHEN @Decision = 'Selected' THEN 'Selected'
        WHEN @Decision = 'Rejected' THEN 'Rejected'
        WHEN @Decision = 'Hold'     THEN 'Interview_Scheduled'
        ELSE 'Interview_Completed'
    END;

    -- 4. Update Candidate Application Record with Evaluation Details & Score
    UPDATE dbo.REC_Candidate_Applications SET
        Stage                = @NextStage,
        InterviewStatus      = @Decision,
        SkillClassification  = ISNULL(@SkillClassification, 'Semi-Skilled'),
        InterviewRemarks     = @Remarks,
        InterviewScore       = ISNULL(@Score, 80),
        InterviewerName      = @EvaluatorName,
        InterviewDate        = GETDATE(),
        LastUpdatedDate      = GETDATE(),
        LastUpdatedBy        = @EvaluatorName
    WHERE pk_appId = @AppId;

    -- 5. If Decision is Rejected, lock rejection stage
    IF @Decision = 'Rejected'
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            IsRejected       = 1,
            RejectionStage   = ISNULL(RejectionStage, 'Interview_Scheduled'),
            RejectionReason  = ISNULL(RejectionReason, 'Interview Evaluation Not Cleared'),
            RejectionRemarks = ISNULL(@Remarks, 'Did not meet competency benchmark during interview assessment')
        WHERE pk_appId = @AppId;
    END
    ELSE
    BEGIN
        -- If previously marked rejected and now Selected or Hold, clear isRejected lock
        UPDATE dbo.REC_Candidate_Applications SET
            IsRejected       = 0
        WHERE pk_appId = @AppId;
    END

    -- 6. Insert Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'EVALUATE', @CurrentStage, @NextStage,
        NULL, @EvaluatorName, 'Interviewer', 
        CONCAT('Evaluation: ', @Decision, ' | Skill Level: ', @SkillClassification, ' | Score: ', @Score, ' | Remarks: ', @Remarks), 
        GETDATE(), @ActualCompanyId
    );

    SELECT 
        1 AS Success, 
        'Interview evaluation saved successfully.' AS Message, 
        ISNULL(@Score, 80) AS Score, 
        @NextStage AS NewStage,
        @Decision AS Decision;
END;
GO

PRINT '3. Updating dbo.usp_REC_GetCandidatePipelineRoster to include Hold candidates in Interview stage...';
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
          OR ca.CandidateTags LIKE CONCAT('%', @SearchQuery, '%')
      );
END;
GO

PRINT 'SQL script 51 completed successfully.';
GO
