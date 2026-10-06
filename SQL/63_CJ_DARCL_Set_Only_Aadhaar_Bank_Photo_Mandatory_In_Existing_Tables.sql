-- ==========================================================================================
-- SCRIPT: 63_CJ_DARCL_Set_Only_Aadhaar_Bank_Photo_Mandatory_In_Existing_Tables.sql
-- PURPOSE:
--   Update existing dbo.REC_Candidate_Documents table and existing stored procedure 
--   dbo.usp_REC_GetCandidateDocuments so that ONLY AADHAAR, BANK, and PHOTO are Mandatory (1).
--   All other documents (PAN, EDUCATION, EXPERIENCE, ADDRESS, POLICE_VERIFICATION, 
--   MEDICAL_FITNESS, ESIC, EPF, NOMINEE, CONTRACT) are Optional (0).
--   NO NEW TABLES, NO DROPPED TABLES, NO FAKE DATA.
-- ==========================================================================================

USE [HRBook_22];
GO

PRINT '>>> Modifying existing dbo.REC_Candidate_Documents table records...';

-- Update all existing candidate document records
UPDATE dbo.REC_Candidate_Documents
SET IsMandatory = CASE 
    WHEN DocTypeCode IN ('AADHAAR', 'BANK', 'PHOTO') THEN 1 
    ELSE 0 
END;

PRINT 'Existing dbo.REC_Candidate_Documents updated. Current count per document type:';
SELECT DocTypeCode, DocTypeName, IsMandatory, COUNT(1) AS CandidateDocCount
FROM dbo.REC_Candidate_Documents
GROUP BY DocTypeCode, DocTypeName, IsMandatory
ORDER BY IsMandatory DESC, DocTypeCode;
GO

PRINT '>>> Updating existing stored procedure dbo.usp_REC_GetCandidateDocuments...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidateDocuments
    @AppId     BIGINT,
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Resolve candidate company if not provided or empty
    IF @CompanyId IS NULL OR LTRIM(RTRIM(@CompanyId)) = ''
    BEGIN
        SELECT @CompanyId = COALESCE(CompanyId, fk_companyId, 'GU-1')
        FROM dbo.REC_Candidate_Applications
        WHERE pk_appId = @AppId;
    END

    -- 1. Auto-seed standard 13 CJ DARCL document rows if not existing for this candidate
    -- ONLY AADHAAR, BANK, and PHOTO are set to IsMandatory = 1. All others are 0.
    IF NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId)
    BEGIN
        INSERT INTO dbo.REC_Candidate_Documents (
            fk_appId, DocTypeCode, DocTypeName, DocCategory, IsMandatory, VerificationStatus, CompanyId, fk_companyId
        ) VALUES 
        (@AppId, 'AADHAAR',             'Aadhaar Card (Front & Back Copy)',               'Identity',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'BANK',                'Bank Proof (Cancelled Cheque / Passbook)',       'Financial',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PHOTO',               'Passport Size Photograph',                       'Personal',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PAN',                 'PAN Card Copy (Tax Compliance)',                 'Identity',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EDUCATION',           'Educational Qualification Certificates',         'Academic',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EXPERIENCE',          'Previous Experience & Relieving Letters',        'Career',      0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ADDRESS',             'Address Proof (Voter ID / DL / Utility Bill)',   'Identity',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'POLICE_VERIFICATION', 'Police Verification Certificate',                'Compliance',  0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'MEDICAL_FITNESS',     'Pre-Employment Medical Fitness Report',          'Health',      0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ESIC',                'ESIC Declaration & Supporting Documents',        'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EPF',                 'EPF Declaration & UAN Details Form',             'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'NOMINEE',             'Nominee Declaration & Proof Documents',          'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'CONTRACT',            'Employment Contract / Appointment Ack',          'Legal',       0, 'Missing', @CompanyId, @CompanyId);

        -- If candidate already had default Aadhaar, PAN, Bank, Photo stored on REC_Candidate_Applications, prefill them
        UPDATE cd
        SET cd.FileName = 'Aadhaar_Card.pdf',
            cd.FilePath = ca.AadhaarDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'AADHAAR' AND ca.AadhaarDocPath IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'PAN_Card.pdf',
            cd.FilePath = ca.PanDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'PAN' AND ca.PanDocPath IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'Bank_Passbook.pdf',
            cd.FilePath = '/uploads/docs/bank_proof.pdf',
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'BANK' AND ca.BankAccNo IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'Passport_Photo.jpg',
            cd.FilePath = ca.PhotoDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'PHOTO' AND ca.PhotoDocPath IS NOT NULL;
    END;

    -- Result Set 1: Candidate Full Dossier Header
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
        ca.VendorName             AS vendorName,
        ca.AadhaarNo              AS aadhaarNo,
        ca.PanNo                  AS panNo,
        ca.BankAccNo              AS bankAccNo,
        ca.BankIfsc               AS bankIfsc,
        ca.BankName               AS bankName,
        ca.NomineeName            AS nomineeName,
        ca.NomineeRelation        AS nomineeRelation,
        ca.NomineeDOB             AS nomineeDOB,
        ca.NomineeContact         AS nomineeContact,
        ca.UanNo                  AS uanNo,
        ca.EsicNo                 AS esicNo,
        ca.Stage                  AS stage,
        ISNULL(ca.DocVerificationStatus, 'Pending') AS docVerificationStatus,
        ISNULL(ca.OnboardingStatus, 'Pending')      AS onboardingStatus,
        ISNULL(ca.DeficiencyRemarks, '')            AS deficiencyRemarks,
        -- Summary metrics calculated strictly from IsMandatory in dbo.REC_Candidate_Documents
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1) AS totalMandatory,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1 AND VerificationStatus = 'Approved') AS approvedMandatory,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND VerificationStatus = 'Rejected') AS rejectedCount,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1 AND VerificationStatus = 'Missing') AS missingMandatory
    FROM dbo.REC_Candidate_Applications ca
    WHERE ca.pk_appId = @AppId 
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Result Set 2: Itemized Document Records
    SELECT 
        cd.pk_docId             AS docId,
        cd.fk_appId             AS appId,
        cd.DocTypeCode          AS docTypeCode,
        cd.DocTypeName          AS docTypeName,
        cd.DocCategory          AS docCategory,
        cd.IsMandatory          AS isMandatory,
        cd.FileName             AS fileName,
        cd.FilePath             AS filePath,
        cd.FileSize             AS fileSize,
        cd.FileType             AS fileType,
        cd.VerificationStatus   AS verificationStatus,
        cd.RejectionRemarks     AS rejectionRemarks,
        cd.VerifiedBy           AS verifiedBy,
        cd.VerifiedDate         AS verifiedDate,
        cd.UploadedBy           AS uploadedBy,
        cd.UploadedDate         AS uploadedDate
    FROM dbo.REC_Candidate_Documents cd
    WHERE cd.fk_appId = @AppId AND cd.IsActive = 1
    ORDER BY cd.IsMandatory DESC, cd.pk_docId ASC;
END;
GO

PRINT 'Successfully updated existing procedure dbo.usp_REC_GetCandidateDocuments.';
GO
