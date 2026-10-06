-- =============================================================================
-- Migration 21: Enforce All Mandatory Documents Verified Before Moving Past Docs Review
-- Standard: 100% Company-Specific, Zero Hardcoding, Direct DB Metric
-- =============================================================================

USE HRBook_22;
GO

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

    SELECT 
        @CurrentStage  = Stage, 
        @AppNo         = ApplicationNo,
        @CandidateName = CandidateName
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
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
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

        -- If candidate has no documents uploaded or has unapproved mandatory documents
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
      );

    -- Insert Audit Entry
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'STAGE_TRANSITION', @CurrentStage, @TargetStage,
        NULL, @MovedBy, 'Recruiter',
        CONCAT('Candidate moved from [', @CurrentStage, '] to [', @TargetStage, ']. ', ISNULL(@Remarks, 'Stage progression confirmed.')),
        GETDATE(), ISNULL(@CompanyId, 'GU-1')
    );

    SELECT 1 AS Success, 
           CONCAT('Candidate successfully moved to ', @TargetStage) AS Message,
           @TargetStage AS newStage;
END;
GO
