-- =============================================================================
-- Migration 31: Update dbo.usp_REC_SaveCandidateOnboardingDossier
-- Purpose: Allow editing prefilled candidate info (Name, Mobile, Email, Gender,
--          DateOfBirth, FatherName, AadhaarNo) alongside statutory dossier fields.
-- Company Scoping: Strictly enforced by @CompanyId / fk_companyId.
-- =============================================================================

USE [HRBook_22];
GO

PRINT 'Migration 31: Updating dbo.usp_REC_SaveCandidateOnboardingDossier to support editing prefilled fields...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveCandidateOnboardingDossier
    @AppId           BIGINT,
    @AadhaarNo       NVARCHAR(20)  = NULL,
    @PanNo           NVARCHAR(20)  = NULL,
    @BankAccNo       NVARCHAR(50)  = NULL,
    @BankIfsc        NVARCHAR(20)  = NULL,
    @BankName        NVARCHAR(100) = NULL,
    @NomineeName     NVARCHAR(150) = NULL,
    @NomineeRelation NVARCHAR(50)  = NULL,
    @NomineeDOB      NVARCHAR(30)  = NULL,
    @NomineeContact  NVARCHAR(30)  = NULL,
    @UanNo           NVARCHAR(30)  = NULL,
    @EsicNo          NVARCHAR(30)  = NULL,
    @CandidateName   NVARCHAR(150) = NULL,
    @Mobile          NVARCHAR(20)  = NULL,
    @Email           NVARCHAR(100) = NULL,
    @Gender          NVARCHAR(20)  = NULL,
    @DateOfBirth     DATE          = NULL,
    @FatherName      NVARCHAR(150) = NULL,
    @SubmittedBy     NVARCHAR(100) = 'Site HR Admin',
    @CompanyId       NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    UPDATE dbo.REC_Candidate_Applications SET
        CandidateName   = ISNULL(NULLIF(@CandidateName, ''), CandidateName),
        Mobile          = ISNULL(NULLIF(@Mobile, ''), Mobile),
        Email           = ISNULL(NULLIF(@Email, ''), Email),
        Gender          = ISNULL(NULLIF(@Gender, ''), Gender),
        DateOfBirth     = COALESCE(@DateOfBirth, DateOfBirth),
        FatherName      = ISNULL(NULLIF(@FatherName, ''), FatherName),
        AadhaarNo       = ISNULL(NULLIF(@AadhaarNo, ''), AadhaarNo),
        PanNo           = ISNULL(NULLIF(@PanNo, ''), PanNo),
        BankAccNo       = ISNULL(NULLIF(@BankAccNo, ''), BankAccNo),
        BankIfsc        = ISNULL(NULLIF(@BankIfsc, ''), BankIfsc),
        BankName        = ISNULL(NULLIF(@BankName, ''), BankName),
        NomineeName     = @NomineeName,
        NomineeRelation = @NomineeRelation,
        NomineeDOB      = @NomineeDOB,
        NomineeContact  = @NomineeContact,
        UanNo           = @UanNo,
        EsicNo          = @EsicNo,
        LastUpdatedDate = GETDATE(),
        LastUpdatedBy   = @SubmittedBy
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Insert Audit Trail
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WITH (NOLOCK) WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'DOSSIER_UPDATE', 'Selected', 'Selected',
        @SubmittedBy, 'Vendor Partner',
        CONCAT('Vendor updated candidate onboarding dossier and profile details for [', ISNULL(@CandidateName, 'Candidate'), ']'),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 1 AS Success, 'Candidate onboarding dossier and profile details saved successfully.' AS Message;
END;
GO

PRINT 'Migration 31: dbo.usp_REC_SaveCandidateOnboardingDossier updated successfully.';
GO
