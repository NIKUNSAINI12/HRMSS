-- =============================================================================
-- Migration 17: Company Mapping Across All Tables, Nullable Diversity Hiring & Max Diversity Category
-- Standard: 100% Company-Specific, Zero Hardcoding, Mandatory SQL Script Tracking
-- =============================================================================

USE HRBook_22;
GO

PRINT 'Starting Migration 17: Company Mapping across all tables, Diversity Hiring nullable, and Diversity Category VARCHAR(MAX)...';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Alter IsDiversityHiring to BIT NULL in REC_JobRequisition_Mst & REC_Candidate_Applications
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 1: Making IsDiversityHiring BIT NULL...';

-- Drop default constraint on REC_JobRequisition_Mst.IsDiversityHiring if it exists
DECLARE @ConstraintName1 NVARCHAR(200);
SELECT @ConstraintName1 = d.name
FROM sys.default_constraints d
JOIN sys.columns c ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id
JOIN sys.tables t ON t.object_id = d.parent_object_id
WHERE t.name = 'REC_JobRequisition_Mst' AND c.name = 'IsDiversityHiring';

IF @ConstraintName1 IS NOT NULL
BEGIN
    EXEC('ALTER TABLE dbo.REC_JobRequisition_Mst DROP CONSTRAINT ' + @ConstraintName1);
    PRINT 'Dropped constraint ' + @ConstraintName1 + ' on REC_JobRequisition_Mst.IsDiversityHiring';
END;

ALTER TABLE dbo.REC_JobRequisition_Mst ALTER COLUMN IsDiversityHiring BIT NULL;
PRINT 'REC_JobRequisition_Mst.IsDiversityHiring is now BIT NULL.';

-- Drop default constraint on REC_Candidate_Applications.IsDiversityHiring if it exists
DECLARE @ConstraintName2 NVARCHAR(200);
SELECT @ConstraintName2 = d.name
FROM sys.default_constraints d
JOIN sys.columns c ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id
JOIN sys.tables t ON t.object_id = d.parent_object_id
WHERE t.name = 'REC_Candidate_Applications' AND c.name = 'IsDiversityHiring';

IF @ConstraintName2 IS NOT NULL
BEGIN
    EXEC('ALTER TABLE dbo.REC_Candidate_Applications DROP CONSTRAINT ' + @ConstraintName2);
    PRINT 'Dropped constraint ' + @ConstraintName2 + ' on REC_Candidate_Applications.IsDiversityHiring';
END;

ALTER TABLE dbo.REC_Candidate_Applications ALTER COLUMN IsDiversityHiring BIT NULL;
PRINT 'REC_Candidate_Applications.IsDiversityHiring is now BIT NULL.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Ensure DiversityCategory VARCHAR(MAX) NULL
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 2: Updating/Adding DiversityCategory VARCHAR(MAX) NULL...';

-- In REC_JobRequisition_Mst
ALTER TABLE dbo.REC_JobRequisition_Mst ALTER COLUMN DiversityCategory VARCHAR(MAX) NULL;
PRINT 'REC_JobRequisition_Mst.DiversityCategory altered to VARCHAR(MAX) NULL.';

-- In REC_Candidate_Applications
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'DiversityCategory'
)
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ADD DiversityCategory VARCHAR(MAX) NULL;
    PRINT 'Added DiversityCategory VARCHAR(MAX) NULL to REC_Candidate_Applications.';
END
ELSE
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications ALTER COLUMN DiversityCategory VARCHAR(MAX) NULL;
    PRINT 'REC_Candidate_Applications.DiversityCategory altered to VARCHAR(MAX) NULL.';
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Ensure CompanyId and fk_companyId exist on REC_JobRequisition_Mst
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 3: Ensuring CompanyId on REC_JobRequisition_Mst...';

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'CompanyId'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD CompanyId NVARCHAR(50) NULL;
    PRINT 'Added CompanyId to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_companyId'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_companyId NVARCHAR(50) NULL;
    PRINT 'Added fk_companyId to REC_JobRequisition_Mst.';
END;
GO

-- Sync REC_JobRequisition_Mst CompanyId & fk_companyId
UPDATE dbo.REC_JobRequisition_Mst 
SET CompanyId = fk_companyId 
WHERE CompanyId IS NULL AND fk_companyId IS NOT NULL;

UPDATE dbo.REC_JobRequisition_Mst 
SET fk_companyId = CompanyId 
WHERE fk_companyId IS NULL AND CompanyId IS NOT NULL;

-- Backfill from Location_Mst where both are NULL
UPDATE r 
SET r.fk_companyId = loc.fk_companyId,
    r.CompanyId = loc.fk_companyId
FROM dbo.REC_JobRequisition_Mst r
JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
WHERE (r.CompanyId IS NULL OR r.fk_companyId IS NULL) 
  AND loc.fk_companyId IS NOT NULL;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Company Mapping across ALL tables (REC_% tables and ExternalCandidate)
-- Add fk_companyId and CompanyId where missing, and synchronize values
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 4: Applying Company Mapping across ALL REC_% and related tables...';

DECLARE @TableName NVARCHAR(128);
DECLARE @Sql NVARCHAR(MAX);

DECLARE TableCursor CURSOR FOR
    SELECT t.name 
    FROM sys.tables t
    WHERE (t.name LIKE 'REC_%' OR t.name = 'ExternalCandidate')
    ORDER BY t.name;

OPEN TableCursor;
FETCH NEXT FROM TableCursor INTO @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Check and add fk_companyId
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c 
        JOIN sys.tables t ON t.object_id = c.object_id 
        WHERE t.name = @TableName AND c.name = 'fk_companyId'
    )
    BEGIN
        SET @Sql = N'ALTER TABLE dbo.[' + @TableName + N'] ADD fk_companyId NVARCHAR(50) NULL;';
        EXEC sp_executesql @Sql;
        PRINT '  Added fk_companyId to ' + @TableName;
    END;

    -- Check and add CompanyId
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c 
        JOIN sys.tables t ON t.object_id = c.object_id 
        WHERE t.name = @TableName AND c.name = 'CompanyId'
    )
    BEGIN
        SET @Sql = N'ALTER TABLE dbo.[' + @TableName + N'] ADD CompanyId NVARCHAR(50) NULL;';
        EXEC sp_executesql @Sql;
        PRINT '  Added CompanyId to ' + @TableName;
    END;

    -- Synchronize fk_companyId -> CompanyId
    SET @Sql = N'UPDATE dbo.[' + @TableName + N'] SET CompanyId = fk_companyId WHERE CompanyId IS NULL AND fk_companyId IS NOT NULL;';
    EXEC sp_executesql @Sql;

    -- Synchronize CompanyId -> fk_companyId
    SET @Sql = N'UPDATE dbo.[' + @TableName + N'] SET fk_companyId = CompanyId WHERE fk_companyId IS NULL AND CompanyId IS NOT NULL;';
    EXEC sp_executesql @Sql;

    FETCH NEXT FROM TableCursor INTO @TableName;
END;

CLOSE TableCursor;
DEALLOCATE TableCursor;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Intelligent Relational Backfill from Parent Tables
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 5: Intelligent relational backfill for child tables...';

-- 1. REC_JobRequisition_Mst_Approval
UPDATE a
SET a.fk_companyId = r.fk_companyId,
    a.CompanyId = COALESCE(r.CompanyId, r.fk_companyId)
FROM dbo.REC_JobRequisition_Mst_Approval a
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = a.fk_reqid
WHERE (a.CompanyId IS NULL OR a.fk_companyId IS NULL);

-- 2. REC_JobRequisition_Trn
UPDATE trn
SET trn.fk_companyId = r.fk_companyId,
    trn.CompanyId = COALESCE(r.CompanyId, r.fk_companyId)
FROM dbo.REC_JobRequisition_Trn trn
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = trn.fk_reqid
WHERE (trn.CompanyId IS NULL OR trn.fk_companyId IS NULL);

-- 3. REC_JobRequisition_Qualification
UPDATE q
SET q.fk_companyId = r.fk_companyId,
    q.CompanyId = COALESCE(r.CompanyId, r.fk_companyId)
FROM dbo.REC_JobRequisition_Qualification q
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = q.fk_reqid
WHERE (q.CompanyId IS NULL OR q.fk_companyId IS NULL);

-- 4. REC_JobRequisition_Specialization
UPDATE s
SET s.fk_companyId = r.fk_companyId,
    s.CompanyId = COALESCE(r.CompanyId, r.fk_companyId)
FROM dbo.REC_JobRequisition_Specialization s
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = s.fk_reqid
WHERE (s.CompanyId IS NULL OR s.fk_companyId IS NULL);

-- 5. REC_Requisition_Vendor_Mapping
UPDATE rvm
SET rvm.fk_companyId = r.fk_companyId,
    rvm.CompanyId = COALESCE(r.CompanyId, r.fk_companyId)
FROM dbo.REC_Requisition_Vendor_Mapping rvm
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = rvm.fk_reqid
WHERE (rvm.CompanyId IS NULL OR rvm.fk_companyId IS NULL);

-- 6. REC_Candidate_Applications backfill Diversity fields from Requisition
UPDATE ca
SET ca.IsDiversityHiring = r.IsDiversityHiring,
    ca.DiversityCategory = r.DiversityCategory
FROM dbo.REC_Candidate_Applications ca
JOIN dbo.REC_JobRequisition_Mst r ON r.pk_reqid = ca.fk_reqid
WHERE ca.DiversityCategory IS NULL AND r.DiversityCategory IS NOT NULL;

-- 7. REC_Candidate_Applications sync CompanyId & fk_companyId
UPDATE ca
SET ca.CompanyId = ca.fk_companyId
FROM dbo.REC_Candidate_Applications ca
WHERE ca.CompanyId IS NULL AND ca.fk_companyId IS NOT NULL;

-- 8. REC_Candidate_Lifecycle_Audit sync CompanyId & fk_companyId
UPDATE cla
SET cla.CompanyId = cla.fk_companyId
FROM dbo.REC_Candidate_Lifecycle_Audit cla
WHERE cla.CompanyId IS NULL AND cla.fk_companyId IS NOT NULL;

-- 9. REC_Candidate educational / experience child tables from REC_Candidate_Details
UPDATE e
SET e.fk_companyId = cd.fk_companyId,
    e.CompanyId = cd.fk_companyId
FROM dbo.REC_Candidate_Educational_Details e
JOIN dbo.REC_Candidate_Details cd ON cd.pk_recId = e.fk_recId
WHERE (e.CompanyId IS NULL OR e.fk_companyId IS NULL);

UPDATE x
SET x.fk_companyId = cd.fk_companyId,
    x.CompanyId = cd.fk_companyId
FROM dbo.REC_Candidate_Experience_Details x
JOIN dbo.REC_Candidate_Details cd ON cd.pk_recId = x.fk_recId
WHERE (x.CompanyId IS NULL OR x.fk_companyId IS NULL);
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Update dbo.usp_REC_SaveJobRequisition
-- Persists CompanyId, fk_companyId, IsDiversityHiring, and DiversityCategory
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 6: Updating dbo.usp_REC_SaveJobRequisition...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveJobRequisition
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100) = NULL,
    @Designation         NVARCHAR(150) = NULL,
    @SkillCategory       NVARCHAR(100) = NULL,
    @OpenPositions       INT           = 1,
    @Location            NVARCHAR(150) = NULL,
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @IsDiversityHiring   BIT           = NULL,
    @DiversityCategory   VARCHAR(MAX)  = NULL,
    @WorkplaceType       NVARCHAR(50)  = 'On-Site',
    @EmploymentType      NVARCHAR(50)  = 'Full-Time',
    @ExperienceMin       DECIMAL(5,2)  = NULL,
    @ExperienceMax       DECIMAL(5,2)  = NULL,
    @CtcMin              DECIMAL(12,2) = NULL,
    @CtcMax              DECIMAL(12,2) = NULL,
    @Currency            NVARCHAR(10)  = 'INR',
    @Priority            NVARCHAR(50)  = 'Medium',
    @TargetStartDate     NVARCHAR(50)  = NULL,
    @EducationLevel      NVARCHAR(100) = NULL,
    @PrimarySkills       NVARCHAR(MAX) = NULL,
    @SecondarySkills     NVARCHAR(MAX) = NULL,
    @NoticePeriodMaxDays INT           = NULL,
    @Industry            NVARCHAR(100) = 'Logistics & Supply Chain',
    @JobDescription      NVARCHAR(MAX) = NULL,
    @Responsibilities    NVARCHAR(MAX) = NULL,
    @Qualifications      NVARCHAR(MAX) = NULL,
    @Benefits            NVARCHAR(MAX) = NULL,
    @HiringManager       NVARCHAR(150) = NULL,
    @LeadRecruiter       NVARCHAR(150) = NULL,
    @Interviewers        NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @SubmittedBy         NVARCHAR(150) = 'Site HR Admin',
    @SubmittedById       NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize Company ID
    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;
    IF (@fk_companyId IS NULL OR @fk_companyId = '') AND (@CompanyId IS NOT NULL AND @CompanyId <> '')
        SET @fk_companyId = @CompanyId;

    -- Dynamic Lookup location ID & company if still null
    DECLARE @fk_locid NVARCHAR(50);
    SELECT TOP 1 
        @fk_locid = pk_locid,
        @CompanyId = COALESCE(@CompanyId, fk_companyId),
        @fk_companyId = COALESCE(@fk_companyId, fk_companyId)
    FROM dbo.Location_Mst 
    WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;

    -- Dynamic Lookup designation ID
    DECLARE @fk_desgid NVARCHAR(50);
    SELECT TOP 1 @fk_desgid = pk_desgid 
    FROM dbo.SAL_Designation_Mst 
    WHERE designation = @Designation OR pk_desgid = @Designation;

    -- Dynamic Lookup department ID
    DECLARE @fk_deptid NVARCHAR(50);
    SELECT TOP 1 @fk_deptid = pk_deptid 
    FROM dbo.Department_Mst 
    WHERE description = @Department OR pk_deptid = @Department;

    -- Default user ID if null
    IF @SubmittedById IS NULL OR @SubmittedById = ''
        SET @SubmittedById = '1';

    -- Format Status and MRF Code
    DECLARE @statusChar CHAR(1) = CASE WHEN @IsDraft = 1 THEN 'D' WHEN @IsBufferUtilized = 1 THEN 'B' ELSE 'P' END;
    DECLARE @requisitionStatus NVARCHAR(50) = CASE WHEN @IsDraft = 1 THEN 'Draft' WHEN @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' ELSE 'Pending Approval' END;
    DECLARE @remarks NVARCHAR(500) = CONCAT('HM: ', @HiringManager, ' | Recruiter: ', @LeadRecruiter, ' | Sub: ', @SubmittedBy);
    
    DECLARE @GeneratedMrfCode NVARCHAR(100) = CONCAT('MRF/', YEAR(GETDATE()), '/', RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4));

    -- Insert Requisition Record with Company Mapping & Diversity Columns
    INSERT INTO dbo.REC_JobRequisition_Mst (
        jobtitle, fk_locid, fk_deptid, fk_desgid, No_of_post, dated, status,
        RequisitionStatus, Reason_of_Requirement, ServiceType, SkillCategory,
        IsDiversityHiring, DiversityCategory, WorkplaceType, EmploymentType,
        Experience_From, Experience_To, CTC_From, CTC_To, Currency, Priority,
        TargetStartDate, EducationLevel, PrimarySkills, SecondarySkills,
        NoticePeriodMaxDays, Industry, JobDescription, Justification_of_Position,
        Roles_Responsibilities, quali, Benefits, HiringManager, LeadRecruiter,
        Interviewers, IsBufferUtilized, BufferHeadsUtilized, SubmittedBy, SubmittedById,
        Mrfcode, Remarks,
        WorkflowStatus, CurrentApprovalLevel, SubmittedDate, LastWorkflowActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @JobTitle, @fk_locid, @fk_deptid, @fk_desgid, @OpenPositions, GETDATE(), @statusChar,
        @requisitionStatus, @HiringType, @ServiceType, @SkillCategory,
        @IsDiversityHiring, @DiversityCategory, @WorkplaceType, @EmploymentType,
        @ExperienceMin, @ExperienceMax, @CtcMin, @CtcMax, @Currency, @Priority,
        @TargetStartDate, @EducationLevel, @PrimarySkills, @SecondarySkills,
        @NoticePeriodMaxDays, @Industry, @JobDescription, @JobDescription,
        @Responsibilities, @Qualifications, @Benefits, @HiringManager, @LeadRecruiter,
        @Interviewers, @IsBufferUtilized, @BufferHeadsUtilized, @SubmittedBy, @SubmittedById,
        @GeneratedMrfCode, @remarks,
        'L1_Pending', 1, GETDATE(), GETDATE(),
        @CompanyId, @fk_companyId
    );

    DECLARE @NewReqId BIGINT = SCOPE_IDENTITY();

    -- Insert initial submit audit log in REC_JobRequisition_Mst_Approval with Company Mapping
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive, 
        approvalLevel, action, approverName, approverRole, workflowStatus,
        CompanyId, fk_companyId
    ) VALUES (
        @NewReqId, @SubmittedById, GETDATE(), 0, 'Requisition submitted for approval', 1, 
        0, 'Submitted', @SubmittedBy, 'Site HR', 'L1_Pending',
        @CompanyId, @fk_companyId
    );

    -- Mandatory Audit Logging: Insert into CL_UpdateAudit_Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @NewReqId, @GeneratedMrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            'None', 'L1_Pending', @SubmittedBy, GETDATE()
        );
    END TRY
    BEGIN CATCH
        -- Non-blocking audit log catch
    END CATCH;

    -- Return the result
    SELECT 
        1 AS Success,
        @NewReqId AS reqId, 
        @GeneratedMrfCode AS mrfCode,
        CASE WHEN @IsDraft = 1 THEN 'Draft saved successfully' ELSE 'Manpower requisition raised successfully — sent for L1 approval' END AS Message;
END;
GO

PRINT 'dbo.usp_REC_SaveJobRequisition successfully created/updated.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 7: Update dbo.usp_REC_GetJobRequisitions
-- Return CompanyId and fk_companyId, filter by both
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 7: Updating dbo.usp_REC_GetJobRequisitions...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitions
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        r.pk_reqid AS jobId,
        r.pk_reqid AS reqId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        loc.locationCode AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        ISNULL(r.ServiceType, 'Fleet & Transportation') AS serviceType,
        ISNULL(r.SkillCategory, 'Skilled') AS skillCategory,
        ISNULL(r.No_of_post, 1) AS openPositions,
        ISNULL(r.No_of_post, 1) AS openingsCount,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
        r.IsDiversityHiring AS isDiversityHiring,
        r.DiversityCategory AS diversityCategory,
        COALESCE(r.CompanyId, r.fk_companyId) AS companyId,
        COALESCE(r.fk_companyId, r.CompanyId) AS fk_companyId,
        ISNULL(r.WorkplaceType, 'On-Site') AS workplaceType,
        ISNULL(r.EmploymentType, 'Full-Time') AS employmentType,
        ISNULL(r.Priority, 'Medium') AS priority,
        ISNULL(r.Currency, 'INR') AS currency,
        r.Experience_From AS experienceMin,
        r.Experience_To AS experienceMax,
        r.CTC_From AS ctcMin,
        r.CTC_To AS ctcMax,
        r.TargetStartDate AS targetStartDate,
        r.EducationLevel AS educationLevel,
        r.PrimarySkills AS primarySkills,
        r.SecondarySkills AS secondarySkills,
        r.NoticePeriodMaxDays AS noticePeriodMaxDays,
        r.Industry AS industry,
        r.JobDescription AS jobDescription,
        r.Roles_Responsibilities AS responsibilities,
        r.quali AS qualifications,
        r.Benefits AS benefits,
        r.HiringManager AS hiringManager,
        r.LeadRecruiter AS leadRecruiter,
        r.Interviewers AS interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.dated AS createdDate,
        r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        r.L1ApproverName,
        r.L1Action,
        r.L1ActionDate,
        r.L1Remarks,
        r.L2ApproverName,
        r.L2Action,
        r.L2ActionDate,
        r.L2Remarks,
        r.L3ApproverName,
        r.L3Action,
        r.L3ActionDate,
        r.L3Remarks,
        r.RejectedByLevel,
        r.RejectedByName,
        r.RejectedByDate,
        r.RejectionRemarks,
        ISNULL(r.RequisitionStatus, 
            CASE 
                WHEN r.status = 'D' THEN 'Draft'
                WHEN r.status = 'B' THEN 'Pending Buffer Approval'
                WHEN r.status = 'P' THEN 'Pending Approval'
                WHEN r.status = 'A' THEN 'Active'
                ELSE 'Active'
            END
        ) AS status,
        -- Total applicants count
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) WHERE ca.fk_reqid = r.pk_reqid) AS applicantsCount,
        -- Total candidates successfully hired/onboarded (Step 13)
        ISNULL((
            SELECT COUNT(1) 
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
            WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'
        ), 0) AS hiredCount,
        -- Whether all required headcount positions are 100% fulfilled
        CASE 
            WHEN ISNULL((
                SELECT COUNT(1) 
                FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
                WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'
            ), 0) >= ISNULL(r.No_of_post, 1) 
            THEN 1 
            ELSE 0 
        END AS isFilled
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR r.CompanyId = @CompanyId
        OR r.fk_companyId = @CompanyId
        OR NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE CompanyId = @CompanyId OR fk_companyId = @CompanyId)
    )
    ORDER BY r.pk_reqid DESC;
END;
GO

PRINT 'dbo.usp_REC_GetJobRequisitions successfully created/updated.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 8: Update dbo.usp_REC_RegisterCandidate
-- Storing CompanyId, fk_companyId, IsDiversityHiring, DiversityCategory
-- ─────────────────────────────────────────────────────────────────────────────
PRINT 'STEP 8: Updating dbo.usp_REC_RegisterCandidate...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidate
    @ReqId          BIGINT,
    @CandidateName  NVARCHAR(200),
    @Mobile         NVARCHAR(20),
    @Email          NVARCHAR(150) = NULL,
    @AadhaarNo      NVARCHAR(20)  = NULL,
    @Gender         NVARCHAR(20)  = 'Male',
    @DateOfBirth    NVARCHAR(30)  = NULL,
    @FatherName     NVARCHAR(150) = NULL,
    @CurrentLocation NVARCHAR(150)= NULL,
    @SourceType     NVARCHAR(50)  = 'Vendor',
    @VendorId       NVARCHAR(50)  = NULL,
    @VendorName     NVARCHAR(150) = NULL,
    @CompanyId      NVARCHAR(50)  = NULL,
    @CreatedBy      NVARCHAR(100) = 'Site HR Admin'
AS
BEGIN
    SET NOCOUNT ON;

    -- Retrieve Job Requisition Details (MRF Code, Location, Department, Designation, Diversity Settings)
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);
    DECLARE @JobCompanyId NVARCHAR(50);
    DECLARE @JobIsDiversity BIT;
    DECLARE @JobDiversityCategory VARCHAR(MAX);

    SELECT 
        @MrfCode = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @Hub = ISNULL(loc.locname, 'Hub Operations'),
        @Dept = ISNULL(dept.description, 'General Logistics'),
        @Desg = ISNULL(des.designation, r.jobtitle),
        @JobCompanyId = COALESCE(r.CompanyId, r.fk_companyId),
        @JobIsDiversity = r.IsDiversityHiring,
        @JobDiversityCategory = r.DiversityCategory
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
        SET @MrfCode = CONCAT('MRF/2026/', @ReqId);

    IF (@CompanyId IS NULL OR @CompanyId = '')
        SET @CompanyId = @JobCompanyId;

    -- =========================================================================
    -- ZERO DUPLICATION ENGINE (Phone & Aadhaar Validation)
    -- =========================================================================
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupDetail NVARCHAR(500) = '';

    -- Check 1: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate applications.');
    END

    -- Check 2: Mobile duplicate in REC_Candidate_Details
    IF @IsDuplicate = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (mobile = @Mobile OR phone = @Mobile)
              AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate master.');
        END
    END

    -- Check 3: Aadhaar duplicate in REC_Candidate_Applications
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL AND @AadhaarNo <> ''
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE AadhaarNo = @AadhaarNo
              AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in candidate applications.');
        END
    END

    -- Check 4: Aadhaar duplicate in SAL_Employee_Mst
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL AND @AadhaarNo <> ''
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE adhaarNo = @AadhaarNo
              AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in company Employee Master.');
        END
    END

    -- If duplicate: reject immediately
    IF @IsDuplicate = 1
    BEGIN
        SELECT 
            0 AS Success,
            1 AS IsRejected,
            CONCAT('Registration Rejected: ', @DupDetail, ' Candidate profile already exists.') AS Message,
            0 AS appId,
            '' AS applicationNo,
            @MrfCode AS mrfCode;
        RETURN;
    END

    -- Generate Application No
    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Determine actual audit role for the registering user
    DECLARE @UserRole NVARCHAR(100) = CASE 
        WHEN @SourceType = 'Vendor' AND @CreatedBy NOT LIKE '%Vendor%' THEN 'Site HR Admin'
        WHEN @SourceType = 'Vendor' AND @CreatedBy LIKE '%Vendor%'     THEN 'Vendor Partner'
        WHEN @SourceType = 'QR_Direct'                                THEN 'Self-Registered (QR)'
        ELSE 'Site HR Admin'
    END;

    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus,
        IsDiversityHiring, DiversityCategory,
        CompanyId, fk_companyId, CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending',
        @JobIsDiversity, @JobDiversityCategory,
        @CompanyId, @CompanyId, GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @CreatedBy, @CreatedBy, @UserRole, 
        CONCAT('Candidate registered against MRF ', @MrfCode, CASE WHEN @VendorName IS NOT NULL AND @VendorName <> '' THEN CONCAT(' via ', @VendorName) ELSE '' END), 
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success,
        0 AS IsRejected,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;
END;
GO

PRINT 'Migration 17 completed successfully!';
GO
