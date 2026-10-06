-- =============================================================================
-- Migration 22: CJ DARCL Recruitment Vendor Portal Architecture
-- Standard: 100% Company-Specific, Zero Hardcoding, Direct DB Metric
-- Step 5 & 10: Vendor Allocation, Batch Sourcing & Selected Candidate Dossier
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Stored Procedure: Get Staffing Vendors for Portal Switcher
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorListForPortal
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS contactNo,
        ISNULL(cd.email, '')                                           AS email,
        -- Total Active MRFs Assigned to this vendor
        (
            SELECT COUNT(DISTINCT rvm.fk_reqid)
            FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
            INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
            WHERE rvm.fk_vendorId = cd.pk_recId
              AND rvm.IsActive = 1
              AND jm.RequisitionStatus = 'Active'
              AND (jm.CompanyId = @CompanyId OR jm.fk_companyId = @CompanyId)
        ) AS assignedJobsCount,
        -- Total Candidates Sourced by this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_vendorId = cd.pk_recId
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS totalCandidatesSourced
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    WHERE cd.IsVendor = 1
      AND (cd.CompanyId = @CompanyId OR cd.fk_companyId = @CompanyId)
    ORDER BY vendorName ASC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Stored Procedure: Get Vendor Portal Metrics
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPortalMetrics
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed (Zero hardcoding)
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    -- 1. Assigned Active Jobs
    DECLARE @AssignedJobsCount INT = 0;
    SELECT @AssignedJobsCount = COUNT(DISTINCT rvm.fk_reqid)
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      AND jm.RequisitionStatus = 'Active'
      AND (jm.CompanyId = @CompanyId OR jm.fk_companyId = @CompanyId);

    -- 2. Total Applications Submitted
    DECLARE @TotalSubmissions INT = 0;
    SELECT @TotalSubmissions = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 3. Candidates in Review / Interviewing
    DECLARE @InReviewCount INT = 0;
    SELECT @InReviewCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage NOT IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Issued', 'Hired')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 4. Selected Candidates (ACTION REQUIRED: Upload Dossier & Documents)
    DECLARE @SelectedCount INT = 0;
    SELECT @SelectedCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Selected'
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 5. Joined / Hired
    DECLARE @HiredCount INT = 0;
    SELECT @HiredCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Hired'
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    SELECT 
        @AssignedJobsCount AS assignedJobsCount,
        @TotalSubmissions  AS totalSubmissions,
        @InReviewCount     AS inReviewCount,
        @SelectedCount     AS selectedCount,
        @HiredCount        AS hiredCount;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Stored Procedure: Get Assigned Jobs for Vendor
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorAssignedJobs
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    SELECT 
        jm.pk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', YEAR(jm.dated), '/', jm.pk_reqid)) AS mrfCode,
        jm.jobtitle                                                      AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
        ISNULL(loc.locname, 'Hub Logistics')                             AS location,
        ISNULL(jm.No_of_post, 1)                                         AS openingsCount,
        ISNULL(rvm.AllocatedQuota, 10)                                   AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                  AS commissionTerms,
        COALESCE(rvm.VendorType, 'Supply Vendors')                       AS vendorType,
        ISNULL(jm.Priority, 'Medium')                                    AS priority,
        ISNULL(jm.WorkplaceType, 'On-Site')                              AS workplaceType,
        ISNULL(jm.EmploymentType, 'Full-Time')                           AS employmentType,
        jm.Experience_From                                               AS experienceMin,
        jm.Experience_To                                                 AS experienceMax,
        jm.CTC_From                                                      AS ctcMin,
        jm.CTC_To                                                        AS ctcMax,
        jm.JobDescription                                                AS jobDescription,
        rvm.AssignedDate                                                 AS assignedDate,
        -- Sourced by this vendor for this MRF
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS submittedCount,
        -- Reached 'Selected' from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Selected'
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS selectedCount,
        -- Hired from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Hired'
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS hiredCount
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = jm.fk_deptid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      AND (jm.CompanyId = @CompanyId OR jm.fk_companyId = @CompanyId)
    ORDER BY rvm.AssignedDate DESC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Stored Procedure: Get Selected Candidates for Vendor (Pending Dossier & Docs)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorSelectedCandidates
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.FatherName                                                    AS fatherName,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ca.PanNo                                                         AS panNo,
        ca.BankAccNo                                                     AS bankAccNo,
        ca.BankIfsc                                                      AS bankIfsc,
        ca.BankName                                                      AS bankName,
        ca.NomineeName                                                   AS nomineeName,
        ca.NomineeRelation                                               AS nomineeRelation,
        ca.NomineeDOB                                                    AS nomineeDOB,
        ca.NomineeContact                                                AS nomineeContact,
        ca.UanNo                                                         AS uanNo,
        ca.EsicNo                                                        AS esicNo,
        ca.fk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', ca.fk_reqid))                  AS mrfCode,
        ISNULL(jm.jobtitle, ca.Designation)                              AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
        ISNULL(loc.locname, 'Hub Operations')                            AS location,
        ca.Stage                                                         AS stage,
        ca.LastUpdatedDate                                               AS selectedDate,
        -- Total uploaded docs count
        ISNULL((
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
            WHERE cd.fk_appId = ca.pk_appId 
              AND ISNULL(cd.FileName, '') != ''
              AND (cd.CompanyId = @CompanyId OR cd.fk_companyId = @CompanyId)
        ), 0) AS uploadedDocsCount,
        -- Missing mandatory docs count
        ISNULL((
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
            WHERE cd.fk_appId = ca.pk_appId 
              AND cd.IsMandatory = 1 
              AND (cd.FileName IS NULL OR cd.FileName = '')
              AND (cd.CompanyId = @CompanyId OR cd.fk_companyId = @CompanyId)
        ), 0) AS missingMandatoryDocsCount
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    LEFT JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = ca.fk_reqid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = jm.fk_deptid
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Selected'
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
    ORDER BY ca.LastUpdatedDate DESC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4.b Helper Procedure: Seed Candidate Documents
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_SeedCandidateDocuments
    @AppId     BIGINT,
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId)
    BEGIN
        INSERT INTO dbo.REC_Candidate_Documents (
            fk_appId, DocTypeCode, DocTypeName, DocCategory, IsMandatory, VerificationStatus, CompanyId, fk_companyId
        ) VALUES 
        (@AppId, 'AADHAAR',             'Aadhaar Card (Front & Back Copy)',               'Identity',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PAN',                 'PAN Card Copy (Tax Compliance)',                 'Identity',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'BANK',                'Bank Proof (Cancelled Cheque / Passbook)',       'Financial',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PHOTO',               'Passport Size Photograph',                       'Personal',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EDUCATION',           'Educational Qualification Certificates',         'Academic',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EXPERIENCE',          'Previous Experience & Relieving Letters',        'Career',      0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ADDRESS',             'Address Proof (Voter ID / DL / Utility Bill)',   'Identity',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'POLICE_VERIFICATION', 'Police Verification Certificate',                'Compliance',  1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'MEDICAL_FITNESS',     'Pre-Employment Medical Fitness Report',          'Health',      1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ESIC',                'ESIC Declaration & Supporting Documents',        'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EPF',                 'EPF Declaration & UAN Details Form',             'Statutory',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'NOMINEE',             'Nominee Declaration & Proof Documents',          'Statutory',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'CONTRACT',            'Employment Contract / Appointment Ack',          'Legal',       1, 'Missing', @CompanyId, @CompanyId);
    END
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Stored Procedure: Submit Single / Batch Candidate by Vendor
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitVendorCandidate
    @ReqId           BIGINT,
    @VendorId        NVARCHAR(50),
    @VendorName      NVARCHAR(150),
    @CandidateName   NVARCHAR(150),
    @Mobile          NVARCHAR(20),
    @Email           NVARCHAR(100)  = NULL,
    @Gender          NVARCHAR(20)   = 'Male',
    @DateOfBirth     DATE           = NULL,
    @FatherName      NVARCHAR(150)  = NULL,
    @AadhaarNo       NVARCHAR(20)   = NULL,
    @ResumeDocPath   NVARCHAR(500)  = NULL,
    @SubmittedBy     NVARCHAR(100)  = 'Vendor Sourcing Portal',
    @CompanyId       NVARCHAR(50)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic Company resolution from Job Requisition if not supplied
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    -- Clean inputs
    SET @Mobile    = LTRIM(RTRIM(@Mobile));
    SET @Email     = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @AadhaarNo = NULLIF(LTRIM(RTRIM(@AadhaarNo)), '');

    -- Check 1: Duplicate Mobile on this active requisition
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE fk_reqid = @ReqId 
          AND Mobile = @Mobile
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId)
    )
    BEGIN
        SELECT 0 AS Success, CONCAT('Duplicate: Mobile ', @Mobile, ' already applied for this job MRF.') AS Message, 0 AS AppId;
        RETURN;
    END

    -- Check 2: Aadhaar duplicate in Employee Master
    IF @AadhaarNo IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE adhaarNo = @AadhaarNo 
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL)
    )
    BEGIN
        SELECT 0 AS Success, CONCAT('Duplicate: Candidate with Aadhaar ', @AadhaarNo, ' is already an employee in Company Master.') AS Message, 0 AS AppId;
        RETURN;
    END

    -- Retrieve Job Metadata
    DECLARE @MrfCode  NVARCHAR(50)  = '';
    DECLARE @JobTitle NVARCHAR(150) = 'Logistics Executive';
    DECLARE @LocName  NVARCHAR(100) = 'Hub Operations';
    DECLARE @DeptName NVARCHAR(100) = 'Operations';

    SELECT 
        @MrfCode  = ISNULL(jm.Mrfcode, CONCAT('MRF/', jm.pk_reqid)),
        @JobTitle = jm.jobtitle,
        @LocName  = ISNULL(loc.locname, 'Hub Operations'),
        @DeptName = ISNULL(dept.description, 'Operations')
    FROM dbo.REC_JobRequisition_Mst jm WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = jm.fk_deptid
    WHERE jm.pk_reqid = @ReqId;

    -- Generate Application No: APP/{Year}/{Seq}
    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%')
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId);
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Insert Candidate Application
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, ResumeDocPath, Stage, SkillClassification, InterviewStatus,
        fk_companyId, CompanyId, CreatedBy, CreatedDate, LastUpdatedBy, LastUpdatedDate
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @LocName, @LocName,
        @DeptName, @JobTitle, 'Vendor', @VendorId, @VendorName,
        @AadhaarNo, @ResumeDocPath, 'Applied', 'Semi-Skilled', 'Pending',
        @CompanyId, @CompanyId, @SubmittedBy, GETDATE(), @SubmittedBy, GETDATE()
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Seed 13 Standard Onboarding Document placeholders for this candidate
    EXEC dbo.usp_REC_SeedCandidateDocuments @AppId = @NewAppId, @CompanyId = @CompanyId;

    -- Log Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'VENDOR_SUBMISSION', 'None', 'Applied',
        @SubmittedBy, 'Vendor Partner',
        CONCAT('Candidate profile submitted by vendor [', @VendorName, '] for MRF ', @MrfCode, ' (', @JobTitle, ')'),
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        CONCAT('Candidate ', @CandidateName, ' successfully registered with ID ', @NextAppNo) AS Message,
        @NewAppId AS AppId,
        @NextAppNo AS ApplicationNo;
END;
GO

PRINT 'Migration 22: Vendor Portal SPs created successfully.';
GO
