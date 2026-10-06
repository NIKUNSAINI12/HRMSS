-- ============================================================================
-- CJ DARCL Recruitment Architecture: Migration 59
-- Rejection State Tracking & Resolution in MRF Requisitions Directory
-- File: SQL/59_CJ_DARCL_Rejection_State_Tracking_And_Resolution.sql
-- ============================================================================

USE [HRBook_22];
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 1. UPDATE dbo.usp_REC_RejectRequisition
-- Strictly sets isDisapproved = 1, RejectedByLevel, RejectedByName,
-- RejectionRemarks, WorkflowStatus = 'Rejected', RequisitionStatus = 'Rejected',
-- and status = 'R'
-- ────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.usp_REC_RejectRequisition', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_REC_RejectRequisition;
GO

CREATE PROCEDURE dbo.usp_REC_RejectRequisition
    @ReqId         BIGINT,
    @ApprovalLevel INT,
    @ApproverId    NVARCHAR(50),
    @ApproverName  NVARCHAR(150),
    @ApproverRole  NVARCHAR(100) = NULL,
    @Remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStatus NVARCHAR(30);
    DECLARE @JobTitle      NVARCHAR(200);
    DECLARE @MrfCode       NVARCHAR(100);
    DECLARE @SubmittedBy   NVARCHAR(150);
    DECLARE @SubmittedById NVARCHAR(50);
    DECLARE @CompanyId     NVARCHAR(50);
    DECLARE @DeptName      NVARCHAR(150);
    DECLARE @LocName       NVARCHAR(150);
    DECLARE @OpeningsCount INT = 1;

    -- Resolve Requisition Details + Company ID (via Location, Department, or Submitting User)
    SELECT 
        @CurrentStatus = r.WorkflowStatus,
        @JobTitle      = r.jobtitle,
        @MrfCode       = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @SubmittedBy   = r.SubmittedBy,
        @SubmittedById = r.SubmittedById,
        @CompanyId     = COALESCE(r.fk_companyId, loc.fk_companyId, dept.fk_companyId, u.fk_companyId),
        @DeptName      = ISNULL(dept.description, 'Operations'),
        @LocName       = ISNULL(loc.locname, 'Hub Operations'),
        @OpeningsCount = ISNULL(r.No_of_post, 1)
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.UM_Users_Mst u WITH (NOLOCK) ON (u.pk_userId = r.SubmittedById OR u.loginname = r.SubmittedById)
    WHERE r.pk_reqid = @ReqId;

    IF @CurrentStatus IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Check if approver is Admin (Roles 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    WHERE (u.pk_userId = @ApproverId OR u.loginname = @ApproverId)
      AND u.fk_roleId IN (1, 2);

    DECLARE @EffectiveLevel INT = @ApprovalLevel;
    IF @IsAdmin = 1
    BEGIN
        IF @CurrentStatus = 'L1_Pending' SET @EffectiveLevel = 1;
        ELSE IF @CurrentStatus = 'L2_Pending' SET @EffectiveLevel = 2;
        ELSE IF @CurrentStatus = 'L3_Pending' SET @EffectiveLevel = 3;
    END

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @RejLevel NVARCHAR(10) = CONCAT('L', @EffectiveLevel);

    -- Set full Rejection state:
    -- WorkflowStatus = 'Rejected', RequisitionStatus = 'Rejected', status = 'R', isDisapproved = 1
    -- and store who rejected, at what level, when, and reviewer remarks.
    UPDATE dbo.REC_JobRequisition_Mst SET
        WorkflowStatus         = 'Rejected',
        RequisitionStatus      = 'Rejected',
        status                 = 'R',
        CurrentApprovalLevel   = 0,
        isDisapproved          = 1,
        RejectedByLevel        = @RejLevel,
        RejectedByName         = @ApproverName,
        RejectedByDate         = @Now,
        RejectionRemarks       = @Remarks,
        L1Action               = CASE WHEN @EffectiveLevel = 1 THEN 'Rejected' ELSE L1Action END,
        L1ActionDate           = CASE WHEN @EffectiveLevel = 1 THEN @Now ELSE L1ActionDate END,
        L1Remarks              = CASE WHEN @EffectiveLevel = 1 THEN @Remarks ELSE L1Remarks END,
        L1ApproverId           = CASE WHEN @EffectiveLevel = 1 THEN @ApproverId ELSE L1ApproverId END,
        L1ApproverName         = CASE WHEN @EffectiveLevel = 1 THEN @ApproverName ELSE L1ApproverName END,
        L2Action               = CASE WHEN @EffectiveLevel = 2 THEN 'Rejected' ELSE L2Action END,
        L2ActionDate           = CASE WHEN @EffectiveLevel = 2 THEN @Now ELSE L2ActionDate END,
        L2Remarks              = CASE WHEN @EffectiveLevel = 2 THEN @Remarks ELSE L2Remarks END,
        L2ApproverId           = CASE WHEN @EffectiveLevel = 2 THEN @ApproverId ELSE L2ApproverId END,
        L2ApproverName         = CASE WHEN @EffectiveLevel = 2 THEN @ApproverName ELSE L2ApproverName END,
        L3Action               = CASE WHEN @EffectiveLevel = 3 THEN 'Rejected' ELSE L3Action END,
        L3ActionDate           = CASE WHEN @EffectiveLevel = 3 THEN @Now ELSE L3ActionDate END,
        L3Remarks              = CASE WHEN @EffectiveLevel = 3 THEN @Remarks ELSE L3Remarks END,
        L3ApproverId           = CASE WHEN @EffectiveLevel = 3 THEN @ApproverId ELSE L3ApproverId END,
        L3ApproverName         = CASE WHEN @EffectiveLevel = 3 THEN @ApproverName ELSE L3ApproverName END,
        LastWorkflowActionDate = @Now
    WHERE pk_reqid = @ReqId;

    -- Insert into Approval History Log
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @ReqId, @ApproverId, @Now, @EffectiveLevel, @Remarks, 1,
        @EffectiveLevel, 'Rejected', @ApproverName, ISNULL(@ApproverRole, CONCAT('L', @EffectiveLevel, ' Approver')), 'Rejected'
    );

    -- Mandatory Audit Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @MrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            @CurrentStatus, 'Rejected', @ApproverName, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    -- Fetch Site HR Email (Original Requisition Raiser) to notify about rejection
    DECLARE @SiteHrEmail NVARCHAR(200) = '';
    SELECT TOP 1 @SiteHrEmail = COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), ''))
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
    WHERE (u.pk_userId = @SubmittedById OR u.loginname = @SubmittedById OR u.name = @SubmittedBy)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
      AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL;

    -- Return Action Result with full template metadata
    SELECT 
        1 AS Success,
        CONCAT('Requisition rejected at ', @RejLevel, ' — returned to Site HR for revision.') AS Message,
        'Rejected' AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @DeptName AS Department,
        @LocName AS Location,
        @OpeningsCount AS Openings,
        @SubmittedBy AS SubmittedBy,
        @ApproverName AS ApproverName,
        @EffectiveLevel AS EffectiveLevel,
        ISNULL(@Remarks, 'Requisition rejected.') AS Remarks,
        CONVERT(VARCHAR(19), @Now, 120) AS ActionDate,
        ISNULL(@SiteHrEmail, '') AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 2. UPDATE dbo.usp_REC_GetJobRequisitions
-- Ensures status is 'Rejected' whenever isDisapproved = 1, WorkflowStatus = 'Rejected',
-- or status = 'R'
-- ────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.usp_REC_GetJobRequisitions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_REC_GetJobRequisitions;
GO

CREATE PROCEDURE dbo.usp_REC_GetJobRequisitions
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
        CASE 
            WHEN ISNULL(r.isDisapproved, 0) = 1 OR r.WorkflowStatus = 'Rejected' OR r.status = 'R' OR r.RequisitionStatus = 'Rejected' THEN 'Rejected'
            WHEN r.RequisitionStatus IS NOT NULL AND r.RequisitionStatus <> '' THEN r.RequisitionStatus
            WHEN r.status = 'D' THEN 'Draft'
            WHEN r.status = 'B' THEN 'Pending Buffer Approval'
            WHEN r.status = 'P' THEN 'Pending Approval'
            WHEN r.status = 'A' THEN 'Active'
            ELSE 'Active'
        END AS status,
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

-- ────────────────────────────────────────────────────────────────────────────
-- 3. UPDATE dbo.usp_REC_GetJobRequisitionById
-- ────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.usp_REC_GetJobRequisitionById', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_REC_GetJobRequisitionById;
GO

CREATE PROCEDURE dbo.usp_REC_GetJobRequisitionById
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
        CASE 
            WHEN ISNULL(r.isDisapproved, 0) = 1 OR r.WorkflowStatus = 'Rejected' OR r.status = 'R' OR r.RequisitionStatus = 'Rejected' THEN 'Rejected'
            WHEN r.RequisitionStatus IS NOT NULL AND r.RequisitionStatus <> '' THEN r.RequisitionStatus
            WHEN r.status = 'D' THEN 'Draft'
            WHEN r.status = 'B' THEN 'Pending Buffer Approval'
            WHEN r.status = 'P' THEN 'Pending Approval'
            WHEN r.status = 'A' THEN 'Active'
            ELSE 'Active'
        END AS status,
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

-- ────────────────────────────────────────────────────────────────────────────
-- 4. FIX HISTORICAL / CURRENT REJECTED REQUISITIONS IN DATABASE
-- ────────────────────────────────────────────────────────────────────────────
UPDATE r
SET 
    r.WorkflowStatus    = 'Rejected',
    r.RequisitionStatus = 'Rejected',
    r.status            = 'R',
    r.isDisapproved     = 1,
    r.RejectedByLevel   = 'L1',
    r.RejectedByName    = ISNULL(r.L1ApproverName, 'Admin'),
    r.RejectedByDate    = ISNULL(r.L1ActionDate, GETDATE()),
    r.RejectionRemarks  = ISNULL(r.L1Remarks, 'Requisition rejected.')
FROM dbo.REC_JobRequisition_Mst r
WHERE r.L1Action = 'Rejected'
  AND (r.WorkflowStatus <> 'Active' AND ISNULL(r.CurrentApprovalLevel, 0) = 0);

UPDATE r
SET 
    r.WorkflowStatus    = 'Rejected',
    r.RequisitionStatus = 'Rejected',
    r.status            = 'R',
    r.isDisapproved     = 1,
    r.RejectedByLevel   = 'L2',
    r.RejectedByName    = ISNULL(r.L2ApproverName, 'Admin'),
    r.RejectedByDate    = ISNULL(r.L2ActionDate, GETDATE()),
    r.RejectionRemarks  = ISNULL(r.L2Remarks, 'Requisition rejected.')
FROM dbo.REC_JobRequisition_Mst r
WHERE r.L2Action = 'Rejected'
  AND (r.WorkflowStatus <> 'Active' AND ISNULL(r.CurrentApprovalLevel, 0) = 0);

UPDATE r
SET 
    r.WorkflowStatus    = 'Rejected',
    r.RequisitionStatus = 'Rejected',
    r.status            = 'R',
    r.isDisapproved     = 1,
    r.RejectedByLevel   = 'L3',
    r.RejectedByName    = ISNULL(r.L3ApproverName, 'Admin'),
    r.RejectedByDate    = ISNULL(r.L3ActionDate, GETDATE()),
    r.RejectionRemarks  = ISNULL(r.L3Remarks, 'Requisition rejected.')
FROM dbo.REC_JobRequisition_Mst r
WHERE r.L3Action = 'Rejected'
  AND (r.WorkflowStatus <> 'Active' AND ISNULL(r.CurrentApprovalLevel, 0) = 0);
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 5. MENU UPDATE: CONVERT 'Create Job' TO 'Create MRF'
-- ────────────────────────────────────────────────────────────────────────────
UPDATE dbo.UM_WebPage_Mst
SET menucaption = 'Create MRF'
WHERE pk_webpageId = 9010 
   OR (pagepath = 'recruitment/recruitmentdashboard/create-job-wizard' AND menucaption = 'Create Job');
GO

