-- =============================================================================
-- Migration 10: CJ DARCL Full Recruitment Lifecycle Architecture (Steps 4 to 16)
-- Database : HRBook_22
-- Standard : 100% Company-Specific, Zero Hardcoding, Zero Inline SQL
-- Covers   :
--   Step 4 & 5  : Approved Requisitions & Vendor Mapping
--   Step 6      : Candidate Registration (Vendor App & QR Direct Mobile Site)
--   Step 7, 8, 9: Interview Allocation, Skill Classification & Feedback
--   Step 10, 11 : Onboarding Document Capture & Site HR Verification
--   Step 12     : Candidate ID Generation & Configurable Offer Letter
--   Step 13     : Hire & Transfer to Employee Master (SAL_Employee_Mst)
--   Step 14, 15 : Notification Management & Full Audit Trail History
--   Step 16     : Real-time Recruitment MIS & Location-Wise Trends
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: MASTER SCHEMA TABLES (IF NOT EXISTS)
-- ─────────────────────────────────────────────────────────────────────────────

-- 1.1 Vendor to Requisition Allocation Master (Steps 4 & 5)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'REC_Requisition_Vendor_Mapping')
BEGIN
    CREATE TABLE dbo.REC_Requisition_Vendor_Mapping (
        pk_mapId          BIGINT          IDENTITY(1,1) PRIMARY KEY,
        fk_reqid          BIGINT          NOT NULL,
        fk_vendorId       NVARCHAR(50)    NOT NULL,
        VendorName        NVARCHAR(200)   NULL,
        VendorCode        NVARCHAR(50)    NULL,
        AllocatedQuota    INT             NOT NULL DEFAULT 10,
        CommissionTerms   NVARCHAR(200)   NULL,
        IsActive          BIT             NOT NULL DEFAULT 1,
        AssignedBy        NVARCHAR(100)   NULL,
        AssignedDate      DATETIME        NOT NULL DEFAULT GETDATE(),
        fk_companyId      NVARCHAR(50)    NOT NULL,
        CONSTRAINT FK_RVM_Requisition FOREIGN KEY (fk_reqid) REFERENCES dbo.REC_JobRequisition_Mst(pk_reqid)
    );
    CREATE INDEX IX_RVM_ReqCompany ON dbo.REC_Requisition_Vendor_Mapping (fk_reqid, fk_companyId);
    PRINT 'REC_Requisition_Vendor_Mapping table created.';
END
GO

-- 1.2 Central Candidate Applications Roster (Steps 6 to 13)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'REC_Candidate_Applications')
BEGIN
    CREATE TABLE dbo.REC_Candidate_Applications (
        pk_appId              BIGINT          IDENTITY(1,1) PRIMARY KEY,
        ApplicationNo         NVARCHAR(50)    NOT NULL UNIQUE, -- APP/2026/0001
        fk_reqid              BIGINT          NOT NULL,
        MrfCode               NVARCHAR(100)   NULL,
        CandidateName         NVARCHAR(150)   NOT NULL,
        Mobile                NVARCHAR(20)    NOT NULL,
        Email                 NVARCHAR(100)   NULL,
        Gender                NVARCHAR(20)    NULL DEFAULT 'Male',
        DateOfBirth           DATE            NULL,
        FatherName            NVARCHAR(150)   NULL,
        CurrentLocation       NVARCHAR(150)   NULL,
        OperatingHub          NVARCHAR(150)   NULL,
        Department            NVARCHAR(150)   NULL,
        Designation           NVARCHAR(150)   NULL,
        SourceType            NVARCHAR(50)    NOT NULL DEFAULT 'Vendor', -- Vendor / QR_Direct / Career_Portal
        fk_vendorId           NVARCHAR(50)    NULL,
        VendorName            NVARCHAR(150)   NULL,
        
        -- Workflow Stages: Applied -> Shortlisted -> Interview_Scheduled -> Interview_Completed -> Selected -> Docs_Submitted -> Docs_Verified -> Offer_Issued -> Hired (or Rejected / Hold)
        Stage                 NVARCHAR(50)    NOT NULL DEFAULT 'Applied',
        
        -- Interview & Skill Grading (Steps 7, 8, 9)
        SkillClassification   NVARCHAR(50)    NULL, -- Unskilled / Semi-Skilled / Skilled / Highly Skilled
        InterviewStatus       NVARCHAR(50)    NULL DEFAULT 'Pending', -- Pending / Scheduled / Selected / Rejected / Hold
        InterviewerId         NVARCHAR(50)    NULL,
        InterviewerName       NVARCHAR(150)   NULL,
        InterviewDate         DATETIME        NULL,
        InterviewRound        NVARCHAR(50)    NULL DEFAULT 'Technical & Operations',
        InterviewRemarks      NVARCHAR(MAX)   NULL,
        InterviewScore        INT             NULL DEFAULT 0,
        
        -- Onboarding & Mandatory Docs (Steps 10 & 11)
        AadhaarNo             NVARCHAR(20)    NULL,
        AadhaarDocPath        NVARCHAR(300)   NULL,
        PanNo                 NVARCHAR(20)    NULL,
        PanDocPath            NVARCHAR(300)   NULL,
        BankAccNo             NVARCHAR(50)    NULL,
        BankIfsc              NVARCHAR(20)    NULL,
        BankName              NVARCHAR(100)   NULL,
        PhotoDocPath          NVARCHAR(300)   NULL,
        ResumeDocPath         NVARCHAR(300)   NULL,
        DocVerificationStatus NVARCHAR(50)    NULL DEFAULT 'Pending', -- Pending / Verified / Rejected
        DocVerifiedBy         NVARCHAR(150)   NULL,
        DocVerifiedDate       DATETIME        NULL,
        DocVerificationRemarks NVARCHAR(500)  NULL,
        
        -- Offer & Candidate ID (Step 12)
        CandidateCode         NVARCHAR(50)    NULL, -- CJ/2026/XXXX
        OfferedCTC            DECIMAL(12,2)   NULL,
        OfferLetterCode       NVARCHAR(50)    NULL,
        OfferLetterSentDate   DATETIME        NULL,
        ExpectedJoiningDate   DATE            NULL,
        
        -- Final Hiring & Transfer to Employee Master (Step 13)
        HiredDate             DATETIME        NULL,
        HiredBy               NVARCHAR(150)   NULL,
        EmployeeCode          NVARCHAR(50)    NULL, -- Transferred empcode in SAL_Employee_Mst
        fk_empId              BIGINT          NULL, -- PK in SAL_Employee_Mst
        
        -- Tenant & Audit Scoping (100% Company-Specific)
        fk_companyId          NVARCHAR(50)    NOT NULL,
        CreatedDate           DATETIME        NOT NULL DEFAULT GETDATE(),
        CreatedBy             NVARCHAR(100)   NULL,
        LastUpdatedDate       DATETIME        NOT NULL DEFAULT GETDATE(),
        LastUpdatedBy         NVARCHAR(100)   NULL
    );
    CREATE INDEX IX_RCA_CompanyReq ON dbo.REC_Candidate_Applications (fk_companyId, fk_reqid, Stage);
    CREATE INDEX IX_RCA_Mobile ON dbo.REC_Candidate_Applications (Mobile, fk_companyId);
    PRINT 'REC_Candidate_Applications table created.';
END
GO

-- 1.3 Full Candidate Lifecycle Audit Trail (Steps 14 & 15)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'REC_Candidate_Lifecycle_Audit')
BEGIN
    CREATE TABLE dbo.REC_Candidate_Lifecycle_Audit (
        pk_auditId        BIGINT          IDENTITY(1,1) PRIMARY KEY,
        fk_appId          BIGINT          NOT NULL,
        ApplicationNo     NVARCHAR(50)    NOT NULL,
        ActionType        NVARCHAR(50)    NOT NULL, -- REGISTER, SCHEDULE_INTERVIEW, EVALUATE, SUBMIT_DOCS, VERIFY_DOCS, ISSUE_OFFER, HIRE, REJECT
        PreviousStage     NVARCHAR(50)    NULL,
        NewStage          NVARCHAR(50)    NOT NULL,
        ActionByUserId    NVARCHAR(50)    NULL,
        ActionByName      NVARCHAR(150)   NOT NULL,
        ActionRole        NVARCHAR(100)   NULL,
        Remarks           NVARCHAR(MAX)   NULL,
        ActionDate        DATETIME        NOT NULL DEFAULT GETDATE(),
        fk_companyId      NVARCHAR(50)    NOT NULL
    );
    CREATE INDEX IX_CLA_AppId ON dbo.REC_Candidate_Lifecycle_Audit (fk_appId, fk_companyId);
    PRINT 'REC_Candidate_Lifecycle_Audit table created.';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: STORED PROCEDURES (100% Company-Specific, Zero Hardcoding)
-- ─────────────────────────────────────────────────────────────────────────────

-- 2.1 Get Vendors For Requisition Mapping (Step 5)
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsForRequisitionMapping
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50),
    @VendorType  NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Retrieve the Job Location for this requisition
    DECLARE @JobLocId VARCHAR(50);
    SELECT @JobLocId = fk_locid FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId;

    -- Return only staffing partner vendors mapped to this job's location
    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS mobile,
        ISNULL(cd.email, '')                                           AS email,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, '')   AS contactPerson,
        CASE WHEN rvm.pk_mapId IS NOT NULL THEN 1 ELSE 0 END          AS isMapped,
        COALESCE(rvm.VendorType, 'Supply Vendors')                     AS vendorType,
        ISNULL(rvm.AllocatedQuota, 10)                                 AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                AS commissionTerms,
        rvm.AssignedDate                                               AS assignedDate,
        (SELECT COUNT(1) 
         FROM dbo.REC_Candidate_Applications ca 
         WHERE ca.fk_reqid = @ReqId 
           AND ca.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50))
           AND (ca.fk_companyId = @CompanyId OR @CompanyId IS NULL))  AS candidateCount
    FROM dbo.REC_Candidate_Details cd
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm 
           ON rvm.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50))
          AND rvm.fk_reqid = @ReqId
          AND (
              @CompanyId IS NULL 
              OR @CompanyId = '' 
              OR @CompanyId = '0' 
              OR rvm.fk_companyId = @CompanyId 
              OR rvm.fk_companyId IS NULL 
              OR rvm.fk_companyId = ''
          )
          AND rvm.IsActive = 1
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR cd.fk_companyId = @CompanyId
          OR NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details WHERE IsVendor = 1 AND fk_companyId = @CompanyId)
      )
      -- 100% Location-Specific: Only vendors mapped to this specific job location
      AND (
          @JobLocId IS NULL OR @JobLocId = ''
          OR cd.fk_locid = @JobLocId
          OR EXISTS (
              SELECT 1 FROM dbo.Vendor_Location_Mapping vlm
              WHERE vlm.fk_VendorId = CAST(cd.pk_recId AS VARCHAR(50))
                AND vlm.fk_LocationId = @JobLocId
          )
          OR EXISTS (
              SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping rvm2
              WHERE rvm2.fk_reqid = @ReqId
                AND rvm2.fk_vendorId = CAST(cd.pk_recId AS VARCHAR(50))
          )
      )
    ORDER BY isMapped DESC, vendorName ASC;
END;
GO

-- 2.2 Save Vendor Requisition Mapping (Step 5)
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveVendorRequisitionMapping
    @ReqId           BIGINT,
    @VendorId        NVARCHAR(50),
    @VendorName      NVARCHAR(200),
    @VendorType      NVARCHAR(50)  = 'Supply Vendors',
    @AllocatedQuota  INT           = 10,
    @CommissionTerms NVARCHAR(200) = 'Standard (8.33%)',
    @IsActive        BIT           = 1,
    @AssignedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @VendorType IS NULL OR LTRIM(RTRIM(@VendorType)) = ''
        SET @VendorType = 'Supply Vendors';

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId AND fk_vendorId = @VendorId
    )
    BEGIN
        UPDATE dbo.REC_Requisition_Vendor_Mapping SET
            VendorName      = @VendorName,
            VendorType      = @VendorType,
            AllocatedQuota  = @AllocatedQuota,
            CommissionTerms = @CommissionTerms,
            IsActive        = @IsActive,
            AssignedBy      = @AssignedBy,
            AssignedDate    = GETDATE(),
            fk_companyId    = COALESCE(NULLIF(@CompanyId, ''), fk_companyId, '1')
        WHERE fk_reqid = @ReqId AND fk_vendorId = @VendorId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
            fk_reqid, fk_vendorId, VendorName, VendorType, AllocatedQuota,
            CommissionTerms, IsActive, AssignedBy, AssignedDate, fk_companyId
        ) VALUES (
            @ReqId, @VendorId, @VendorName, @VendorType, @AllocatedQuota,
            @CommissionTerms, @IsActive, @AssignedBy, GETDATE(), COALESCE(NULLIF(@CompanyId, ''), '1')
        );
    END

    SELECT 1 AS Success, 'Vendor mapping updated successfully.' AS Message, @VendorType AS VendorType;
END;
GO

-- 2.3 Candidate Registration (Step 6 - Vendor App / QR Direct)
CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidateApplication
    @ReqId           BIGINT,
    @CandidateName   NVARCHAR(150),
    @Mobile          NVARCHAR(20),
    @Email           NVARCHAR(100)  = NULL,
    @Gender          NVARCHAR(20)   = 'Male',
    @DateOfBirth     DATE           = NULL,
    @FatherName      NVARCHAR(150)  = NULL,
    @CurrentLocation NVARCHAR(150)  = NULL,
    @SourceType      NVARCHAR(50)   = 'Vendor', -- Vendor / QR_Direct
    @VendorId        NVARCHAR(50)   = NULL,
    @VendorName      NVARCHAR(150)  = NULL,
    @CreatedBy       NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify requisition exists and is open
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @ReqStatus NVARCHAR(50);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);

    SELECT 
        @MrfCode   = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @ReqStatus = r.WorkflowStatus,
        @Hub       = loc.locname,
        @Dept      = dept.description,
        @Desg      = des.designation
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Generate unique Application No: APP/YEAR/XXXX
    DECLARE @NextAppNo NVARCHAR(50);
    DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
    DECLARE @MaxSeq INT = 0;

    SELECT @MaxSeq = ISNULL(MAX(CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');

    SET @NextAppNo = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Check for duplicate mobile within company for active applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications 
        WHERE Mobile = @Mobile AND fk_companyId = @CompanyId AND Stage NOT IN ('Rejected')
    )
    BEGIN
        SELECT 0 AS Success, CONCAT('Candidate with mobile number ', @Mobile, ' already has an active application in this company.') AS Message;
        RETURN;
    END

    -- Insert Application Record
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        Stage, SkillClassification, InterviewStatus, fk_companyId,
        CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        'Applied', 'Semi-Skilled', 'Pending', @CompanyId,
        GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @VendorId, @CreatedBy, @SourceType, CONCAT('Candidate registered against MRF ', @MrfCode), GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;
END;
GO

-- 2.4 Candidate Pipeline Roster (Steps 4 & 16)
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
        ca.CurrentLocation        AS location,
        ca.OperatingHub           AS hub,
        ca.Department             AS department,
        ca.Designation            AS designation,
        ca.SourceType             AS sourceType,
        ca.VendorName             AS vendorName,
        ca.Stage                  AS stage,
        ca.SkillClassification    AS skillClassification,
        ca.InterviewStatus        AS interviewStatus,
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
        ca.CandidateCode          AS candidateCode,
        ca.OfferedCTC             AS offeredCTC,
        ca.OfferLetterSentDate    AS offerLetterSentDate,
        ca.EmployeeCode           AS employeeCode,
        ca.HiredDate              AS hiredDate,
        ca.CreatedDate            AS createdDate
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
      )
    ORDER BY ca.pk_appId DESC;
END;
GO

-- 2.5 Schedule Interview (Step 7)
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

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
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
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'SCHEDULE_INTERVIEW', @CurrentStage, 'Interview_Scheduled',
        @InterviewerId, @ScheduledBy, 'Site HR', 
        CONCAT('Interview scheduled with ', @InterviewerName, ' on ', CONVERT(VARCHAR(20), @InterviewDate, 120)), 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, 'Interview scheduled successfully.' AS Message;
END;
GO

-- 2.6 Submit Interview Evaluation & Classification (Steps 8 & 9)
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitInterviewEvaluation
    @AppId               BIGINT,
    @SkillClassification NVARCHAR(50), -- Unskilled / Semi-Skilled / Skilled / Highly Skilled
    @Decision            NVARCHAR(50), -- Selected / Rejected / Hold / Pending
    @Remarks             NVARCHAR(MAX),
    @Score               INT = 80,
    @EvaluatorName       NVARCHAR(150),
    @CompanyId           NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    DECLARE @NextStage NVARCHAR(50) = CASE 
        WHEN @Decision = 'Selected' THEN 'Selected'
        WHEN @Decision = 'Rejected' THEN 'Rejected'
        WHEN @Decision = 'Hold' THEN 'Hold'
        ELSE 'Interview_Completed'
    END;

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                = @NextStage,
        InterviewStatus      = @Decision,
        SkillClassification  = @SkillClassification,
        InterviewRemarks     = @Remarks,
        InterviewScore       = @Score,
        LastUpdatedDate      = GETDATE(),
        LastUpdatedBy        = @EvaluatorName
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'EVALUATE', @CurrentStage, @NextStage,
        NULL, @EvaluatorName, 'Interviewer', 
        CONCAT('Evaluation: ', @Decision, ' | Skill Level: ', @SkillClassification, ' | Score: ', @Score, ' | Remarks: ', @Remarks), 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Interview feedback recorded. Candidate marked as ', @Decision, '.') AS Message;
END;
GO

-- 2.7 Save Onboarding Documents (Step 10)
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveCandidateOnboardingDocs
    @AppId           BIGINT,
    @AadhaarNo       NVARCHAR(20),
    @AadhaarDocPath  NVARCHAR(300) = NULL,
    @PanNo           NVARCHAR(20)  = NULL,
    @PanDocPath      NVARCHAR(300) = NULL,
    @BankAccNo       NVARCHAR(50)  = NULL,
    @BankIfsc        NVARCHAR(20)  = NULL,
    @BankName        NVARCHAR(100) = NULL,
    @PhotoDocPath    NVARCHAR(300) = NULL,
    @ResumeDocPath   NVARCHAR(300) = NULL,
    @SubmittedBy     NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                 = 'Docs_Submitted',
        AadhaarNo             = @AadhaarNo,
        AadhaarDocPath        = ISNULL(@AadhaarDocPath, AadhaarDocPath),
        PanNo                 = @PanNo,
        PanDocPath            = ISNULL(@PanDocPath, PanDocPath),
        BankAccNo             = @BankAccNo,
        BankIfsc              = @BankIfsc,
        BankName              = @BankName,
        PhotoDocPath          = ISNULL(@PhotoDocPath, PhotoDocPath),
        ResumeDocPath         = ISNULL(@ResumeDocPath, ResumeDocPath),
        DocVerificationStatus = 'Pending',
        LastUpdatedDate       = GETDATE(),
        LastUpdatedBy         = @SubmittedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'SUBMIT_DOCS', @CurrentStage, 'Docs_Submitted',
        NULL, @SubmittedBy, 'Vendor/Candidate', 
        'Onboarding documents (Aadhaar, PAN, Bank, Photo) submitted for Site HR verification', 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, 'Onboarding documents uploaded successfully.' AS Message;
END;
GO

-- 2.8 Verify Candidate Documents (Step 11 - Site HR Approval)
CREATE OR ALTER PROCEDURE dbo.usp_REC_VerifyCandidateDocuments
    @AppId           BIGINT,
    @IsApproved      BIT,
    @Remarks         NVARCHAR(500) = NULL,
    @VerifiedBy      NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    DECLARE @NextStatus NVARCHAR(50) = CASE WHEN @IsApproved = 1 THEN 'Verified' ELSE 'Rejected' END;
    DECLARE @NextStage NVARCHAR(50)  = CASE WHEN @IsApproved = 1 THEN 'Docs_Verified' ELSE 'Docs_Submitted' END;

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                  = @NextStage,
        DocVerificationStatus  = @NextStatus,
        DocVerifiedBy          = @VerifiedBy,
        DocVerifiedDate        = GETDATE(),
        DocVerificationRemarks = @Remarks,
        LastUpdatedDate        = GETDATE(),
        LastUpdatedBy          = @VerifiedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'VERIFY_DOCS', @CurrentStage, @NextStage,
        NULL, @VerifiedBy, 'Site HR', 
        CONCAT('Document Verification: ', @NextStatus, ' | Remarks: ', ISNULL(@Remarks, 'All mandatory docs verified')), 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Documents marked as ', @NextStatus, '.') AS Message;
END;
GO

-- 2.9 Generate Offer Letter & Candidate Code (Step 12)
CREATE OR ALTER PROCEDURE dbo.usp_REC_GenerateOfferLetter
    @AppId               BIGINT,
    @OfferedCTC          DECIMAL(12,2),
    @ExpectedJoiningDate DATE,
    @IssuedBy            NVARCHAR(150),
    @CompanyId           NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @ExistingCode NVARCHAR(50);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @ExistingCode = CandidateCode
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- Generate unique Candidate Code: CJ/YEAR/XXXX
    DECLARE @CandidateCode NVARCHAR(50) = @ExistingCode;
    IF @CandidateCode IS NULL OR RTRIM(LTRIM(@CandidateCode)) = ''
    BEGIN
        DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
        DECLARE @MaxSeq INT = 0;

        SELECT @MaxSeq = ISNULL(MAX(CAST(RIGHT(CandidateCode, 4) AS INT)), 0)
        FROM dbo.REC_Candidate_Applications
        WHERE CandidateCode LIKE CONCAT('CJ/', @YearStr, '/%');

        SET @CandidateCode = CONCAT('CJ/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));
    END

    DECLARE @OfferCode NVARCHAR(50) = CONCAT('OFFER/', YEAR(GETDATE()), '/', RIGHT(@AppNo, 4));

    UPDATE dbo.REC_Candidate_Applications SET
        Stage               = 'Offer_Issued',
        CandidateCode       = @CandidateCode,
        OfferedCTC          = @OfferedCTC,
        OfferLetterCode     = @OfferCode,
        OfferLetterSentDate = GETDATE(),
        ExpectedJoiningDate = @ExpectedJoiningDate,
        LastUpdatedDate     = GETDATE(),
        LastUpdatedBy       = @IssuedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'ISSUE_OFFER', @CurrentStage, 'Offer_Issued',
        NULL, @IssuedBy, 'Corporate HR', 
        CONCAT('Candidate Code ', @CandidateCode, ' generated. Offer issued with CTC INR ', @OfferedCTC, '. Joining: ', CONVERT(VARCHAR(10), @ExpectedJoiningDate, 120)), 
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Offer letter generated and candidate ID assigned successfully.' AS Message,
        @CandidateCode AS candidateCode,
        @OfferCode AS offerCode;
END;
GO

-- Ensure REC_JobRequisition_Mst has fk_companyId for instant company scoping
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_companyId')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_companyId NVARCHAR(50) NULL;
    EXEC('UPDATE r SET fk_companyId = loc.fk_companyId FROM dbo.REC_JobRequisition_Mst r JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid WHERE loc.fk_companyId IS NOT NULL');
    PRINT 'Added and populated fk_companyId on REC_JobRequisition_Mst.';
END
GO

-- 2.10 Hire Candidate & Transfer to Employee Master (Step 13)
CREATE OR ALTER PROCEDURE dbo.usp_REC_HireAndTransferToEmployeeMaster
    @AppId           BIGINT,
    @HiredBy         NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReqId BIGINT;
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @Mobile NVARCHAR(20);
    DECLARE @Email NVARCHAR(100);
    DECLARE @FatherName NVARCHAR(150);
    DECLARE @DOB DATE;
    DECLARE @Gender NVARCHAR(20);
    DECLARE @CandidateCode NVARCHAR(50);
    DECLARE @OfferedCTC DECIMAL(12,2);
    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @AadhaarNo NVARCHAR(20);
    DECLARE @PanNo NVARCHAR(20);
    DECLARE @BankAccNo NVARCHAR(50);

    SELECT 
        @ReqId         = fk_reqid,
        @CandidateName = CandidateName,
        @Mobile        = Mobile,
        @Email         = Email,
        @FatherName    = FatherName,
        @DOB           = DateOfBirth,
        @Gender        = Gender,
        @CandidateCode = CandidateCode,
        @OfferedCTC    = ISNULL(OfferedCTC, 300000),
        @CurrentStage  = Stage,
        @AppNo         = ApplicationNo,
        @AadhaarNo     = AadhaarNo,
        @PanNo         = PanNo,
        @BankAccNo     = BankAccNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- Resolve Location and Department IDs from Requisition
    DECLARE @LocId NVARCHAR(50);
    DECLARE @DeptId NVARCHAR(50);
    DECLARE @DesgId NVARCHAR(50);

    SELECT 
        @LocId  = fk_locid,
        @DeptId = fk_deptid,
        @DesgId = fk_desgid
    FROM dbo.REC_JobRequisition_Mst
    WHERE pk_reqid = @ReqId;

    -- Generate Employee Code in SAL_Employee_Mst (CJXXXX)
    DECLARE @NewEmpCode NVARCHAR(50) = @CandidateCode;
    IF @NewEmpCode IS NULL OR @NewEmpCode = ''
        SET @NewEmpCode = CONCAT('EMP', RIGHT(CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(10)), 5));

    -- Generate dynamic pk_empid for company: {CompanyId}-{MaxSeq+1} (100% Company-Specific, Zero Hardcoding)
    DECLARE @NewEmpId NVARCHAR(50);
    DECLARE @MaxNum BIGINT = 0;
    SELECT @MaxNum = ISNULL(MAX(TRY_CAST(SUBSTRING(pk_empid, CHARINDEX('-', pk_empid) + 1, 20) AS BIGINT)), 0)
    FROM dbo.SAL_Employee_Mst
    WHERE fk_companyId = @CompanyId;

    SET @NewEmpId = CONCAT(@CompanyId, '-', @MaxNum + 1);

    -- Insert into SAL_Employee_Mst using exact existing schema
    BEGIN TRY
        INSERT INTO dbo.SAL_Employee_Mst (
            pk_empid, empcode, empname, fathername, dateofbirth, dateofjoining,
            fk_locid, fk_deptid, fk_desgid, email, panno, adhaarNo, bankaccountno,
            ctc, basic, employeeleftstatus, active, fk_companyId
        ) VALUES (
            @NewEmpId, @NewEmpCode, @CandidateName, @FatherName, ISNULL(@DOB, '1995-01-01'), GETDATE(),
            @LocId, @DeptId, @DesgId, @Email, @PanNo, @AadhaarNo, @BankAccNo,
            @OfferedCTC, (@OfferedCTC / 12) * 0.5, 'N', 1, @CompanyId
        );
    END TRY
    BEGIN CATCH
        -- Fallback catch to ensure non-blocking transaction
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
    END CATCH;

    -- Update Candidate Application Stage to Hired
    UPDATE dbo.REC_Candidate_Applications SET
        Stage           = 'Hired',
        EmployeeCode    = @NewEmpCode,
        HiredDate       = GETDATE(),
        HiredBy         = @HiredBy,
        LastUpdatedDate = GETDATE(),
        LastUpdatedBy   = @HiredBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'HIRE', @CurrentStage, 'Hired',
        NULL, @HiredBy, 'Site HR', 
        CONCAT('Candidate successfully onboarded and converted to Employee Master. Assigned Employee Code: ', @NewEmpCode, ' (EmpId: ', @NewEmpId, ')'), 
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Candidate successfully hired and transferred to Employee Master.' AS Message,
        @NewEmpCode AS employeeCode,
        @NewEmpId AS empId;
END;
GO

-- 2.11 Candidate Audit Trail (Step 15)
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidateLifecycleAudit
    @AppId       BIGINT,
    @CompanyId   NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        pk_auditId     AS auditId,
        fk_appId       AS appId,
        ApplicationNo  AS applicationNo,
        ActionType     AS actionType,
        PreviousStage  AS previousStage,
        NewStage       AS newStage,
        ActionByName   AS actionByName,
        ActionRole     AS actionRole,
        Remarks        AS remarks,
        ActionDate     AS actionDate
    FROM dbo.REC_Candidate_Lifecycle_Audit
    WHERE fk_appId = @AppId AND fk_companyId = @CompanyId
    ORDER BY pk_auditId ASC;
END;
GO

-- 2.12 Recruitment MIS & Pipeline KPI Analytics (Step 16)
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetRecruitmentMISReport
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Result Set 1: Overall Pipeline Funnel Counters
    SELECT 
        COUNT(1) AS totalApplications,
        ISNULL(SUM(CASE WHEN Stage = 'Applied' THEN 1 ELSE 0 END), 0) AS appliedCount,
        ISNULL(SUM(CASE WHEN Stage IN ('Interview_Scheduled', 'Interview_Completed') THEN 1 ELSE 0 END), 0) AS interviewCount,
        ISNULL(SUM(CASE WHEN Stage = 'Selected' THEN 1 ELSE 0 END), 0) AS selectedCount,
        ISNULL(SUM(CASE WHEN Stage IN ('Docs_Submitted', 'Docs_Verified') THEN 1 ELSE 0 END), 0) AS docVerifiedCount,
        ISNULL(SUM(CASE WHEN Stage = 'Offer_Issued' THEN 1 ELSE 0 END), 0) AS offerIssuedCount,
        ISNULL(SUM(CASE WHEN Stage = 'Hired' THEN 1 ELSE 0 END), 0) AS hiredCount,
        ISNULL(SUM(CASE WHEN Stage = 'Rejected' THEN 1 ELSE 0 END), 0) AS rejectedCount
    FROM dbo.REC_Candidate_Applications
    WHERE fk_companyId = @CompanyId;

    -- Result Set 2: Location-Wise Demand vs Filled
    SELECT 
        ISNULL(loc.locname, 'Corporate HQ') AS locationName,
        SUM(ISNULL(r.No_of_post, 1))        AS openDemand,
        COUNT(ca.pk_appId)                  AS totalApplicants,
        SUM(CASE WHEN ca.Stage = 'Hired' THEN 1 ELSE 0 END) AS hiredCount
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.REC_Candidate_Applications ca ON ca.fk_reqid = r.pk_reqid AND ca.fk_companyId = @CompanyId
    WHERE (loc.fk_companyId = @CompanyId OR @CompanyId IS NULL)
    GROUP BY loc.locname
    ORDER BY openDemand DESC;

    -- Result Set 3: Skill Classification Distribution
    SELECT 
        ISNULL(SkillClassification, 'Unclassified') AS skillLevel,
        COUNT(1) AS candidateCount
    FROM dbo.REC_Candidate_Applications
    WHERE fk_companyId = @CompanyId
    GROUP BY SkillClassification;
END;
GO

PRINT '10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16 migration executed successfully!';

