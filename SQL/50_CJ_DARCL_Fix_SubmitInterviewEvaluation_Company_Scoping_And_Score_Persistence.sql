-- ============================================================================
-- 50_CJ_DARCL_Fix_SubmitInterviewEvaluation_Company_Scoping_And_Score_Persistence.sql
-- Fixes Interview Evaluation Submission to Guarantee Score & Stage Persistence
-- Resolves Multi-Tenant Company Id (e.g., 'GU-1' vs '1') and Fallback by pk_appId
-- ============================================================================

USE [HRBook_22];
GO

PRINT 'Creating/Updating dbo.usp_REC_SubmitInterviewEvaluation...';
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

    -- 3. Determine next workflow stage based on interview decision
    DECLARE @NextStage NVARCHAR(50) = CASE 
        WHEN @Decision = 'Selected' THEN 'Selected'
        WHEN @Decision = 'Rejected' THEN 'Rejected'
        WHEN @Decision = 'Hold' THEN 'Hold'
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
        @NextStage AS NewStage;
END;
GO

PRINT 'dbo.usp_REC_SubmitInterviewEvaluation created/updated successfully.';
GO
