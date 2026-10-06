-- ============================================================================
-- Migration 41: Rejection-Edit-Resume Workflow for MRF Approval
-- CJ DARCL Recruitment Module  Date: 03-Oct-2026  Database: HRBook_22
-- Rule: Zero Hardcoding. All DB mutations via USPs. Company-Scoped.
-- ============================================================================
-- Logic:
--   L1 rejection -> HR edits -> resubmit goes to L1_Pending (start fresh at L1)
--   L2 rejection -> HR edits -> resubmit goes to L2_Pending (L1 already approved)
--   L3 rejection -> HR edits -> resubmit goes to L3_Pending (L1+L2 already approved)
--   After L1 approval: MRF NOT editable (WorkflowStatus = L2_Pending/L3_Pending/Approved)
--   isDisapproved=1 marks MRF as needs HR edit before re-entry
-- ============================================================================

USE [HRBook_22];
GO

-- STEP 1: Ensure required columns exist
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'isDisapproved')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD isDisapproved BIT NOT NULL DEFAULT 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'RejectedByLevel')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD RejectedByLevel NVARCHAR(10) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'RejectedByName')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD RejectedByName NVARCHAR(150) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'RejectedByDate')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD RejectedByDate DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'RejectionRemarks')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD RejectionRemarks NVARCHAR(MAX) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'ResubmittedDate')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD ResubmittedDate DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'ResubmittedBy')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD ResubmittedBy NVARCHAR(150) NULL;
GO

-- STEP 2: Update usp_REC_GetJobRequisitionById to expose rejection fields
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitionById
    @ReqId     BIGINT,
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CleanCompanyId    NVARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId NVARCHAR(50) = NULL;
    IF @CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '' AND @CompanyId <> '0'
    BEGIN
        SET @CleanCompanyId    = REPLACE(@CompanyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;
    SELECT TOP 1
        r.pk_reqid AS reqId,
        r.pk_reqid AS jobId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        r.fk_deptid, r.fk_subdeptid,
        ISNULL(subdept.description, '') AS subDepartment,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        r.fk_locid,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        r.fk_desgid, r.fk_classid,
        ISNULL(grd.gradedetails, '') AS gradeName,
        r.fk_catid,
        ISNULL(cat.category, '') AS categoryName,
        r.fk_costcentreid,
        ISNULL(cc.description, '') AS costCenterName,
        r.fk_zoneId, r.fk_cityid,
        ISNULL(r.BusinessVertical, '') AS businessVertical,
        ISNULL(r.ServiceType, 'Fleet & Transportation') AS serviceType,
        ISNULL(r.SkillCategory, 'Skilled') AS skillCategory,
        ISNULL(r.No_of_post, 1) AS openPositions,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
        r.ReplacedEmpName, r.Reason_of_Replacement AS replacementReason,
        r.IsDiversityHiring, r.DiversityCategory,
        COALESCE(r.CompanyId, r.fk_companyId) AS companyId,
        COALESCE(r.fk_companyId, r.CompanyId) AS fk_companyId,
        ISNULL(r.WorkplaceType, 'On-Site') AS workplaceType,
        ISNULL(r.EmploymentType, 'Full-Time') AS employmentType,
        ISNULL(r.Priority, 'Medium') AS priority,
        ISNULL(r.Currency, 'INR') AS currency,
        r.Experience_From AS experienceMin, r.Experience_To AS experienceMax,
        r.CTC_From AS ctcMin, r.CTC_To AS ctcMax,
        r.TargetStartDate, r.EducationLevel, r.PrimarySkills, r.SecondarySkills,
        r.NoticePeriodMaxDays, r.Industry,
        r.JobDescription, r.Roles_Responsibilities AS responsibilities,
        r.quali AS qualifications, r.Benefits AS benefits,
        r.HiringManager, r.HiringManagerId, r.LeadRecruiter, r.LeadRecruiterId,
        r.L1ApproverName, r.L1ApproverId, r.Interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.SubmittedById,
        r.UpdatedBy, r.UpdatedById, r.UpdatedDate,
        r.dated AS createdDate, r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        -- Rejection / Resubmit tracking
        ISNULL(r.isDisapproved, 0) AS isDisapproved,
        r.RejectedByLevel AS rejectedByLevel,
        r.RejectedByName  AS rejectedByName,
        r.RejectedByDate  AS rejectedByDate,
        r.RejectionRemarks AS rejectionRemarks,
        r.ResubmittedDate, r.ResubmittedBy,
        ISNULL(r.RequisitionStatus,
            CASE
                WHEN r.status = 'D' THEN 'Draft'
                WHEN r.status = 'B' THEN 'Pending Buffer Approval'
                WHEN r.status = 'P' THEN 'Pending Approval'
                WHEN r.status = 'A' THEN 'Active'
                ELSE 'Active'
            END
        ) AS status,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
         WHERE ca.fk_reqid = r.pk_reqid) AS applicantsCount,
        ISNULL((SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
                WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'), 0) AS hiredCount
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst        dept    WITH (NOLOCK) ON dept.pk_deptid        = r.fk_deptid
    LEFT JOIN dbo.Sub_Department_Mst    subdept WITH (NOLOCK) ON subdept.pk_subdeptid   = r.fk_subdeptid
    LEFT JOIN dbo.Location_Mst          loc     WITH (NOLOCK) ON loc.pk_locid           = r.fk_locid
    LEFT JOIN dbo.SAL_Designation_Mst   des     WITH (NOLOCK) ON des.pk_desgid          = r.fk_desgid
    LEFT JOIN dbo.SAL_Grade_Mst         grd     WITH (NOLOCK) ON grd.pk_gradeid         = r.fk_classid
    LEFT JOIN dbo.SAL_Category_Mst      cat     WITH (NOLOCK) ON cat.pk_catid           = r.fk_catid
    LEFT JOIN dbo.SAL_Cost_Centre_Mst   cc      WITH (NOLOCK) ON cc.pk_cost_centre_id   = r.fk_costcentreid
    WHERE r.pk_reqid = @ReqId
      AND (
            @CleanCompanyId IS NULL
            OR r.CompanyId    = @CleanCompanyId    OR r.CompanyId    = @PrefixedCompanyId
            OR r.fk_companyId = @CleanCompanyId    OR r.fk_companyId = @PrefixedCompanyId
            OR r.CompanyId IS NULL
          );
END;
GO

-- STEP 3: Update usp_REC_UpdateJobRequisition with Rejection-Resume routing
CREATE OR ALTER PROCEDURE dbo.usp_REC_UpdateJobRequisition
    @ReqId               BIGINT,
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100),
    @Designation         NVARCHAR(150),
    @SkillCategory       NVARCHAR(100),
    @OpenPositions       INT,
    @Location            NVARCHAR(150),
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @ReplacedEmpName     NVARCHAR(150) = NULL,
    @ReplacementReason   NVARCHAR(500) = NULL,
    @IsDiversityHiring   BIT           = NULL,
    @DiversityCategory   NVARCHAR(100) = NULL,
    @WorkplaceType       NVARCHAR(50)  = 'On-Site',
    @EmploymentType      NVARCHAR(50)  = 'Full-Time',
    @ExperienceMin       DECIMAL(4,1)  = NULL,
    @ExperienceMax       DECIMAL(4,1)  = NULL,
    @CtcMin              DECIMAL(18,2) = NULL,
    @CtcMax              DECIMAL(18,2) = NULL,
    @Currency            NVARCHAR(10)  = 'INR',
    @Priority            NVARCHAR(50)  = 'Medium',
    @TargetStartDate     NVARCHAR(50)  = NULL,
    @EducationLevel      NVARCHAR(100) = NULL,
    @PrimarySkills       NVARCHAR(500) = NULL,
    @SecondarySkills     NVARCHAR(500) = NULL,
    @NoticePeriodMaxDays INT           = NULL,
    @Industry            NVARCHAR(150) = NULL,
    @JobDescription      NVARCHAR(MAX) = NULL,
    @Responsibilities    NVARCHAR(MAX) = NULL,
    @Qualifications      NVARCHAR(MAX) = NULL,
    @Benefits            NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @UpdatedBy           NVARCHAR(150) = 'HR User',
    @UpdatedById         NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL,
    @fk_locid            NVARCHAR(50)  = NULL,
    @fk_deptid           NVARCHAR(50)  = NULL,
    @fk_subdeptid        NVARCHAR(50)  = NULL,
    @fk_desgid           NVARCHAR(50)  = NULL,
    @fk_classid          NVARCHAR(50)  = NULL,
    @fk_catid            NVARCHAR(50)  = NULL,
    @fk_costcentreid     BIGINT        = NULL,
    @fk_zoneId           NVARCHAR(50)  = NULL,
    @fk_cityid           NVARCHAR(50)  = NULL,
    @BusinessVertical    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    BEGIN
        SELECT 0 AS Success, @ReqId AS reqId, '' AS mrfCode, 'Job Requisition not found.' AS Message;
        RETURN;
    END;

    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;

    IF @fk_locid IS NULL OR @fk_locid = ''
        SELECT TOP 1 @fk_locid = pk_locid FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;

    IF @fk_desgid IS NULL OR @fk_desgid = ''
        SELECT TOP 1 @fk_desgid = pk_desgid FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;

    IF @fk_deptid IS NULL OR @fk_deptid = ''
        SELECT TOP 1 @fk_deptid = pk_deptid FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;

    DECLARE @CurrentStatus          CHAR(1);
    DECLARE @CurrentWorkflow        NVARCHAR(30);
    DECLARE @ExistingMrfCode        NVARCHAR(100);
    DECLARE @CurrentIsDisapproved   BIT;
    DECLARE @CurrentRejectedByLevel NVARCHAR(10);

    SELECT
        @CurrentStatus          = status,
        @CurrentWorkflow        = WorkflowStatus,
        @ExistingMrfCode        = Mrfcode,
        @CurrentIsDisapproved   = ISNULL(isDisapproved, 0),
        @CurrentRejectedByLevel = RejectedByLevel
    FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId;

    -- Workflow Resume: if rejected and not a draft save, route back to rejected level
    DECLARE @NewWorkflowStatus NVARCHAR(30);
    DECLARE @NewApprovalLevel  INT;
    DECLARE @IsResubmit        BIT = 0;

    IF @CurrentIsDisapproved = 1 AND @IsDraft = 0
    BEGIN
        SET @IsResubmit        = 1;
        SET @NewWorkflowStatus = CASE @CurrentRejectedByLevel
            WHEN 'L1' THEN 'L1_Pending'
            WHEN 'L2' THEN 'L2_Pending'
            WHEN 'L3' THEN 'L3_Pending'
            ELSE 'L1_Pending'
        END;
        SET @NewApprovalLevel  = CASE @CurrentRejectedByLevel
            WHEN 'L1' THEN 1
            WHEN 'L2' THEN 2
            WHEN 'L3' THEN 3
            ELSE 1
        END;
    END
    ELSE
    BEGIN
        SET @NewWorkflowStatus = ISNULL(@CurrentWorkflow, 'Submitted');
        SET @NewApprovalLevel  = CASE @CurrentWorkflow
            WHEN 'L1_Pending' THEN 1
            WHEN 'L2_Pending' THEN 2
            WHEN 'L3_Pending' THEN 3
            ELSE 1
        END;
    END;

    DECLARE @statusChar CHAR(1) = CASE
        WHEN @IsDraft = 1 THEN 'D'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'P'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 0 THEN 'P'
        ELSE @CurrentStatus
    END;

    DECLARE @requisitionStatus NVARCHAR(50) = CASE
        WHEN @IsDraft = 1 THEN 'Draft'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'Pending Approval'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 0 THEN 'Pending Approval'
        ELSE (SELECT ISNULL(RequisitionStatus,'Active') FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    END;

    UPDATE dbo.REC_JobRequisition_Mst SET
        jobtitle                  = @JobTitle,
        fk_locid                  = COALESCE(@fk_locid,  fk_locid),
        fk_deptid                 = COALESCE(@fk_deptid, fk_deptid),
        fk_subdeptid              = COALESCE(@fk_subdeptid, fk_subdeptid),
        fk_desgid                 = COALESCE(@fk_desgid, fk_desgid),
        fk_classid                = COALESCE(@fk_classid, fk_classid),
        fk_catid                  = COALESCE(@fk_catid,  fk_catid),
        fk_costcentreid           = COALESCE(@fk_costcentreid, fk_costcentreid),
        fk_zoneId                 = COALESCE(@fk_zoneId, fk_zoneId),
        fk_cityid                 = COALESCE(@fk_cityid, fk_cityid),
        BusinessVertical          = @BusinessVertical,
        No_of_post                = @OpenPositions,
        Reason_of_Requirement     = @HiringType,
        ReplacedEmpName           = @ReplacedEmpName,
        Reason_of_Replacement     = @ReplacementReason,
        ServiceType               = @ServiceType,
        SkillCategory             = @SkillCategory,
        IsDiversityHiring         = @IsDiversityHiring,
        DiversityCategory         = @DiversityCategory,
        WorkplaceType             = @WorkplaceType,
        EmploymentType            = @EmploymentType,
        Experience_From           = @ExperienceMin,
        Experience_To             = @ExperienceMax,
        CTC_From                  = @CtcMin,
        CTC_To                    = @CtcMax,
        Currency                  = @Currency,
        Priority                  = @Priority,
        TargetStartDate           = @TargetStartDate,
        EducationLevel            = @EducationLevel,
        PrimarySkills             = @PrimarySkills,
        SecondarySkills           = @SecondarySkills,
        NoticePeriodMaxDays       = @NoticePeriodMaxDays,
        Industry                  = @Industry,
        JobDescription            = @JobDescription,
        Justification_of_Position = @JobDescription,
        Roles_Responsibilities    = @Responsibilities,
        quali                     = @Qualifications,
        Benefits                  = @Benefits,
        IsBufferUtilized          = @IsBufferUtilized,
        BufferHeadsUtilized       = @BufferHeadsUtilized,
        status                    = @statusChar,
        RequisitionStatus         = @requisitionStatus,
        UpdatedBy                 = @UpdatedBy,
        UpdatedById               = @UpdatedById,
        UpdatedDate               = GETDATE(),
        WorkflowStatus            = @NewWorkflowStatus,
        CurrentApprovalLevel      = @NewApprovalLevel,
        isDisapproved             = CASE WHEN @IsResubmit = 1 THEN 0         ELSE isDisapproved  END,
        ResubmittedDate           = CASE WHEN @IsResubmit = 1 THEN GETDATE() ELSE ResubmittedDate END,
        ResubmittedBy             = CASE WHEN @IsResubmit = 1 THEN @UpdatedBy ELSE ResubmittedBy  END,
        LastWorkflowActionDate    = CASE WHEN @IsResubmit = 1 THEN GETDATE() ELSE LastWorkflowActionDate END
    WHERE pk_reqid = @ReqId;

    IF @IsResubmit = 1
        INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
            fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
            approvalLevel, action, approverName, approverRole, workflowStatus
        ) VALUES (
            @ReqId, @UpdatedById, GETDATE(), @NewApprovalLevel,
            CONCAT('Resubmitted after ', @CurrentRejectedByLevel,
                   ' rejection. Resuming at ', @CurrentRejectedByLevel, '.'),
            1, @NewApprovalLevel, 'Resubmitted', @UpdatedBy, 'Site HR', @NewWorkflowStatus
        );

    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @ExistingMrfCode, 'REC_JobRequisition_Mst',
            CASE WHEN @IsResubmit = 1 THEN 'WorkflowResubmit' ELSE 'JobRequisitionUpdate' END,
            CASE WHEN @IsResubmit = 1 THEN CONCAT('Rejected/',@CurrentRejectedByLevel) ELSE 'Multiple Fields' END,
            CASE WHEN @IsResubmit = 1 THEN @NewWorkflowStatus ELSE 'Updated' END,
            @UpdatedBy, GETDATE()
        );
    END TRY BEGIN CATCH END CATCH;

    SELECT
        1 AS Success,
        @ReqId AS reqId,
        @ExistingMrfCode AS mrfCode,
        CASE WHEN @IsResubmit = 1
            THEN CONCAT('MRF resubmitted. Workflow resumed at ', @CurrentRejectedByLevel, ' level.')
            ELSE 'Job Requisition updated successfully.'
        END AS Message,
        @IsResubmit        AS IsResubmit,
        @NewWorkflowStatus AS NewWorkflowStatus;
END;
GO

-- STEP 4: Update usp_REC_GetJobRequisitions to expose isDisapproved & rejection tracking
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitions
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize numeric/prefixed CompanyId
    DECLARE @CleanCompanyId NVARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId NVARCHAR(50) = NULL;

    IF @CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '' AND @CompanyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@CompanyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    SELECT 
        r.pk_reqid AS jobId,
        r.pk_reqid AS reqId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        r.fk_deptid AS fk_deptid,
        r.fk_subdeptid AS fk_subdeptid,
        ISNULL(subdept.description, '') AS subDepartment,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        r.fk_locid AS fk_locid,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        r.fk_desgid AS fk_desgid,
        r.fk_classid AS fk_classid,
        ISNULL(grd.gradedetails, '') AS gradeName,
        r.fk_catid AS fk_catid,
        ISNULL(cat.category, '') AS categoryName,
        r.fk_costcentreid AS fk_costcentreid,
        ISNULL(cc.description, '') AS costCenterName,
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
        r.L1ApproverName,
        r.L1ApproverId,
        r.Interviewers AS interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.dated AS createdDate,
        r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
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
        -- Rejection / Resubmit tracking
        ISNULL(r.isDisapproved, 0) AS isDisapproved,
        r.RejectedByLevel          AS rejectedByLevel,
        r.RejectedByName           AS rejectedByName,
        r.RejectedByDate           AS rejectedByDate,
        r.RejectionRemarks         AS rejectionRemarks,
        r.ResubmittedDate          AS resubmittedDate,
        r.ResubmittedBy            AS resubmittedBy,
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
    LEFT JOIN dbo.Sub_Department_Mst subdept WITH (NOLOCK) ON subdept.pk_subdeptid = r.fk_subdeptid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) ON des.pk_desgid = r.fk_desgid
    LEFT JOIN dbo.SAL_Grade_Mst grd WITH (NOLOCK) ON grd.pk_gradeid = r.fk_classid
    LEFT JOIN dbo.SAL_Category_Mst cat WITH (NOLOCK) ON cat.pk_catid = r.fk_catid
    LEFT JOIN dbo.SAL_Cost_Centre_Mst cc WITH (NOLOCK) ON cc.pk_cost_centre_id = r.fk_costcentreid
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR r.CompanyId = @CompanyId
        OR r.fk_companyId = @CompanyId
        OR r.CompanyId = @CleanCompanyId
        OR r.fk_companyId = @CleanCompanyId
        OR r.CompanyId = @PrefixedCompanyId
        OR r.fk_companyId = @PrefixedCompanyId
        OR NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE CompanyId IN (@CompanyId, @CleanCompanyId, @PrefixedCompanyId) OR fk_companyId IN (@CompanyId, @CleanCompanyId, @PrefixedCompanyId))
    )
    ORDER BY r.pk_reqid DESC;
END;
GO

PRINT 'Migration 41: Rejection-Resubmit workflow completed successfully.';
