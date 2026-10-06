-- ==============================================================================
-- 35_CJ_DARCL_JobRequisition_EmployeeMaster_Dropdowns_And_Save.sql
-- Synchronizes Job Requisition Master with Employee Master dropdowns & schema.
-- Adds fk_subdeptid, fk_catid, fk_zoneId, fk_cityid, BusinessVertical, 
-- HiringManagerId, LeadRecruiterId to dbo.REC_JobRequisition_Mst.
-- Updates dbo.usp_REC_SaveJobRequisition and dbo.usp_REC_GetJobRequisitions.
-- ==============================================================================

USE [HRBook_22];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'STEP 1: Adding missing columns to dbo.REC_JobRequisition_Mst...';
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_subdeptid')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_subdeptid NVARCHAR(50) NULL;
    PRINT 'Added fk_subdeptid to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_catid')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_catid NVARCHAR(50) NULL;
    PRINT 'Added fk_catid to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_zoneId')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_zoneId NVARCHAR(50) NULL;
    PRINT 'Added fk_zoneId to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'fk_cityid')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD fk_cityid NVARCHAR(50) NULL;
    PRINT 'Added fk_cityid to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'BusinessVertical')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD BusinessVertical NVARCHAR(150) NULL;
    PRINT 'Added BusinessVertical to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'HiringManagerId')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD HiringManagerId NVARCHAR(50) NULL;
    PRINT 'Added HiringManagerId to REC_JobRequisition_Mst.';
END;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'LeadRecruiterId')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD LeadRecruiterId NVARCHAR(50) NULL;
    PRINT 'Added LeadRecruiterId to REC_JobRequisition_Mst.';
END;
GO

PRINT 'STEP 2: Updating dbo.usp_REC_SaveJobRequisition...';
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
    @HiringManagerId     NVARCHAR(50)  = NULL,
    @LeadRecruiter       NVARCHAR(150) = NULL,
    @LeadRecruiterId     NVARCHAR(50)  = NULL,
    @Interviewers        NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @SubmittedBy         NVARCHAR(150) = 'Site HR Admin',
    @SubmittedById       NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL,
    -- Specific Foreign Key IDs from Employee Master Standard Dropdowns
    @fk_locid            NVARCHAR(50)  = NULL,
    @fk_deptid           NVARCHAR(50)  = NULL,
    @fk_subdeptid        NVARCHAR(50)  = NULL,
    @fk_desgid           NVARCHAR(50)  = NULL,
    @fk_classid          NVARCHAR(50)  = NULL, -- Grade
    @fk_catid            NVARCHAR(50)  = NULL, -- Category
    @fk_costcentreid     BIGINT        = NULL, -- Cost Center
    @fk_zoneId           NVARCHAR(50)  = NULL,
    @fk_cityid           NVARCHAR(50)  = NULL,
    @BusinessVertical    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize Company ID
    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;
    IF (@fk_companyId IS NULL OR @fk_companyId = '') AND (@CompanyId IS NOT NULL AND @CompanyId <> '')
        SET @fk_companyId = @CompanyId;

    -- Dynamic Lookup location ID if not explicitly provided
    IF @fk_locid IS NULL OR @fk_locid = ''
    BEGIN
        SELECT TOP 1 
            @fk_locid = pk_locid,
            @CompanyId = COALESCE(@CompanyId, fk_companyId),
            @fk_companyId = COALESCE(@fk_companyId, fk_companyId)
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;
    END
    ELSE
    BEGIN
        -- Also populate location name if missing
        IF @Location IS NULL OR @Location = ''
        BEGIN
            SELECT TOP 1 @Location = locname FROM dbo.Location_Mst WITH (NOLOCK) WHERE pk_locid = @fk_locid;
        END;
    END;

    -- Dynamic Lookup designation ID if not explicitly provided
    IF @fk_desgid IS NULL OR @fk_desgid = ''
    BEGIN
        SELECT TOP 1 @fk_desgid = pk_desgid 
        FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;
    END
    ELSE
    BEGIN
        IF @Designation IS NULL OR @Designation = ''
        BEGIN
            SELECT TOP 1 @Designation = designation FROM dbo.SAL_Designation_Mst WITH (NOLOCK) WHERE pk_desgid = @fk_desgid;
        END;
    END;

    -- Dynamic Lookup department ID if not explicitly provided
    IF @fk_deptid IS NULL OR @fk_deptid = ''
    BEGIN
        SELECT TOP 1 @fk_deptid = pk_deptid 
        FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;
    END
    ELSE
    BEGIN
        IF @Department IS NULL OR @Department = ''
        BEGIN
            SELECT TOP 1 @Department = description FROM dbo.Department_Mst WITH (NOLOCK) WHERE pk_deptid = @fk_deptid;
        END;
    END;

    -- Default user ID if null
    IF @SubmittedById IS NULL OR @SubmittedById = ''
        SET @SubmittedById = '1';

    -- Format Status and MRF Code
    DECLARE @statusChar CHAR(1) = CASE WHEN @IsDraft = 1 THEN 'D' WHEN @IsBufferUtilized = 1 THEN 'B' ELSE 'P' END;
    DECLARE @requisitionStatus NVARCHAR(50) = CASE WHEN @IsDraft = 1 THEN 'Draft' WHEN @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' ELSE 'Pending Approval' END;
    DECLARE @remarks NVARCHAR(500) = CONCAT('HM: ', @HiringManager, ' | Recruiter: ', @LeadRecruiter, ' | Sub: ', @SubmittedBy);
    
    DECLARE @GeneratedMrfCode NVARCHAR(100) = CONCAT('MRF/', YEAR(GETDATE()), '/', RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4));

    -- Insert Requisition Record with All Employee Master Standard Dropdowns
    INSERT INTO dbo.REC_JobRequisition_Mst (
        jobtitle, fk_locid, fk_deptid, fk_desgid, fk_classid, fk_costcentreid,
        fk_subdeptid, fk_catid, fk_zoneId, fk_cityid, BusinessVertical,
        HiringManagerId, LeadRecruiterId,
        No_of_post, dated, status,
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
        @JobTitle, @fk_locid, @fk_deptid, @fk_desgid, @fk_classid, @fk_costcentreid,
        @fk_subdeptid, @fk_catid, @fk_zoneId, @fk_cityid, @BusinessVertical,
        @HiringManagerId, @LeadRecruiterId,
        @OpenPositions, GETDATE(), @statusChar,
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

PRINT 'STEP 3: Updating dbo.usp_REC_GetJobRequisitions...';
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
        r.fk_deptid AS fk_deptid,
        r.fk_subdeptid AS fk_subdeptid,
        ISNULL(subdept.SubDepartmentName, '') AS subDepartment,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        r.fk_locid AS fk_locid,
        loc.locationCode AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        r.fk_desgid AS fk_desgid,
        r.fk_classid AS fk_classid,
        ISNULL(grd.GradeName, '') AS gradeName,
        r.fk_catid AS fk_catid,
        ISNULL(cat.categoryName, '') AS categoryName,
        r.fk_costcentreid AS fk_costcentreid,
        ISNULL(cc.costcentreName, '') AS costCenterName,
        r.fk_zoneId AS fk_zoneId,
        r.fk_cityid AS fk_cityid,
        ISNULL(r.BusinessVertical, '') AS businessVertical,
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
        r.HiringManagerId AS hiringManagerId,
        r.LeadRecruiter AS leadRecruiter,
        r.LeadRecruiterId AS leadRecruiterId,
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
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SubDepartment_Mst subdept WITH (NOLOCK) ON subdept.pk_subdeptid = r.fk_subdeptid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) ON des.pk_desgid = r.fk_desgid
    LEFT JOIN dbo.Grade_Mst grd WITH (NOLOCK) ON grd.pk_gradeid = r.fk_classid
    LEFT JOIN dbo.Category_Mst cat WITH (NOLOCK) ON cat.pk_catid = r.fk_catid
    LEFT JOIN dbo.CostCentre_Mst cc WITH (NOLOCK) ON cc.pk_costcentreid = r.fk_costcentreid
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
