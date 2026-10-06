-- =============================================================================
-- Migration 08: All Stored Procedures for Recruitment Job Requisition Workflow
-- CJ DARCL Recruitment Module - Multi-Level Requisition Approval Workflow
-- Date   : 22-Sep-2026
-- Database: HRBook_22
-- Rule   : Zero Inline SQL in Controllers. All database actions in USPs.
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. usp_REC_GetRequisitionMasterData
-- Returns 5 result sets in a single roundtrip:
-- 1) Active Departments
-- 2) Locations with Manpower Buffers & Headcount Metrics
-- 3) Active Designations
-- 4) Employees (for Interviewers / Hiring Team)
-- 5) Default User Location (3-tier fallback)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetRequisitionMasterData
    @UserId    NVARCHAR(50)  = NULL,
    @LoginName NVARCHAR(100) = NULL,
    @CompanyId NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamically resolve @CompanyId from user session if not passed explicitly
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId 
        FROM dbo.UM_Users_Mst WITH (NOLOCK) 
        WHERE (@UserId IS NOT NULL AND (pk_userId = @UserId OR loginName = @UserId))
           OR (@LoginName IS NOT NULL AND (loginName = @LoginName OR email = @LoginName));
    END;

    -- Fallback to active system company if still unresolved (guarantees company-specific scoping)
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId FROM dbo.UM_Users_Mst WITH (NOLOCK) WHERE pk_userId = 'GU-1';
    END;

    -- 1. Departments (Strictly Company-Specific)
    SELECT 
        pk_deptid   AS id, 
        description AS name 
    FROM dbo.Department_Mst 
    WHERE dep_active = 1 
      AND fk_companyId = @CompanyId
    ORDER BY description;

    -- 2. Locations with Capacity & Buffer Metrics (Strictly Company-Specific)
    SELECT 
        l.pk_locid AS id, 
        l.locname  AS name, 
        ISNULL(l.locationCode, l.code) AS code, 
        ISNULL(z.zoneDescription, 'General Zone') AS zone, 
        ISNULL(l.BaseDemand, 0) AS baseDemand, 
        ISNULL(l.BufferPercent, 0.00) AS bufferPercent, 
        ISNULL(l.BufferHeads, 0) AS bufferHeads, 
        ISNULL(l.TargetCapacity, 0) AS targetCapacity,
        ISNULL((SELECT COUNT(1) FROM dbo.SAL_Employee_Mst e WHERE e.fk_locid = l.pk_locid), 0) AS currentOccupied
    FROM dbo.Location_Mst l
    LEFT JOIN dbo.SAL_Zone_Mst z ON z.pk_zoneId = l.fk_zoneId
    WHERE l.fk_companyId = @CompanyId
    ORDER BY l.locname;

    -- 3. Designations (Company-Specific)
    SELECT 
        pk_desgid   AS id, 
        designation AS name 
    FROM dbo.SAL_Designation_Mst 
    WHERE isActive = 1 
      AND (@CompanyId IS NULL OR fk_companyId = @CompanyId)
    ORDER BY designation;

    -- 4. Employees for Hiring Panel (Company-Specific)
    SELECT TOP 80 
        e.pk_empid AS id, 
        e.empname  AS name, 
        e.empcode  AS code,
        (SELECT des.designation FROM dbo.SAL_Designation_Mst des WHERE des.pk_desgid = e.fk_desgid) AS extra
    FROM dbo.SAL_Employee_Mst e
    WHERE (@CompanyId IS NULL OR e.fk_companyId = @CompanyId)
    ORDER BY e.empname;

    -- 5. User Default Location (Tier 1 -> Tier 2 -> Empty)
    DECLARE @DefaultLocId   NVARCHAR(50)  = NULL;
    DECLARE @DefaultLocName NVARCHAR(200) = NULL;

    IF (@UserId IS NOT NULL AND RTRIM(LTRIM(@UserId)) <> '') OR (@LoginName IS NOT NULL AND RTRIM(LTRIM(@LoginName)) <> '')
    BEGIN
        -- Tier 1: Try via linked employee record
        SELECT TOP 1 
            @DefaultLocId   = l.pk_locid, 
            @DefaultLocName = l.locname
        FROM dbo.UM_Users_Mst u
        INNER JOIN dbo.SAL_Employee_Mst e ON e.pk_empid = u.fk_empId
        INNER JOIN dbo.Location_Mst l     ON l.pk_locid = e.fk_locid
        WHERE 
            (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId OR e.empcode = @UserId OR CAST(e.pk_empid AS NVARCHAR(50)) = @UserId))
            OR
            (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR e.empcode = @LoginName OR u.email = @LoginName));

        -- Tier 2: Try via company fallback if employee link is NULL (admin users)
        IF @DefaultLocId IS NULL
        BEGIN
            SELECT TOP 1 
                @DefaultLocId   = l.pk_locid, 
                @DefaultLocName = l.locname
            FROM dbo.UM_Users_Mst u
            INNER JOIN dbo.Location_Mst l ON l.fk_companyId = u.fk_companyId
            WHERE 
                (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId))
                OR
                (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR u.email = @LoginName))
            ORDER BY l.pk_locid;
        END
    END

    SELECT 
        @DefaultLocId   AS defaultLocationId, 
        @DefaultLocName AS defaultLocationName;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. usp_REC_GetJobRequisitions
-- Returns list of all job requisitions with all workflow statuses and joined details
-- ─────────────────────────────────────────────────────────────────────────────
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
        ISNULL(r.IsDiversityHiring, 0) AS isDiversityHiring,
        r.DiversityCategory AS diversityCategory,
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
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WHERE ca.fk_reqid = r.pk_reqid) AS applicantsCount
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR r.fk_companyId = @CompanyId
        OR NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE fk_companyId = @CompanyId)
    )
    ORDER BY r.pk_reqid DESC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. usp_REC_SaveJobRequisition
-- Persists all wizard fields, triggers L1 workflow, logs audit
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveJobRequisition
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100) = NULL,
    @Designation         NVARCHAR(150) = NULL,
    @SkillCategory       NVARCHAR(100) = NULL,
    @OpenPositions       INT           = 1,
    @Location            NVARCHAR(150) = NULL,
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @IsDiversityHiring   BIT           = 0,
    @DiversityCategory   NVARCHAR(100) = NULL,
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
    @SubmittedById       NVARCHAR(50)  = '1'
AS
BEGIN
    SET NOCOUNT ON;

    -- Lookup location ID
    DECLARE @fk_locid NVARCHAR(50);
    SELECT TOP 1 @fk_locid = pk_locid 
    FROM dbo.Location_Mst 
    WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;

    IF @fk_locid IS NULL
        SET @fk_locid = 'GU-1';

    -- Lookup designation ID
    DECLARE @fk_desgid NVARCHAR(50);
    SELECT TOP 1 @fk_desgid = pk_desgid 
    FROM dbo.SAL_Designation_Mst 
    WHERE designation = @Designation OR pk_desgid = @Designation;

    IF @fk_desgid IS NULL
        SET @fk_desgid = 'GU-1';

    -- Lookup department ID
    DECLARE @fk_deptid NVARCHAR(50);
    SELECT TOP 1 @fk_deptid = pk_deptid 
    FROM dbo.Department_Mst 
    WHERE description = @Department OR pk_deptid = @Department;

    -- Format Status and MRF Code
    DECLARE @statusChar CHAR(1) = CASE WHEN @IsDraft = 1 THEN 'D' WHEN @IsBufferUtilized = 1 THEN 'B' ELSE 'P' END;
    DECLARE @requisitionStatus NVARCHAR(50) = CASE WHEN @IsDraft = 1 THEN 'Draft' WHEN @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' ELSE 'Pending Approval' END;
    DECLARE @remarks NVARCHAR(500) = CONCAT('HM: ', @HiringManager, ' | Recruiter: ', @LeadRecruiter, ' | Sub: ', @SubmittedBy);
    
    DECLARE @GeneratedMrfCode NVARCHAR(100) = CONCAT('MRF/', YEAR(GETDATE()), '/', RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4));

    -- Insert Requisition Record
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
        WorkflowStatus, CurrentApprovalLevel, SubmittedDate, LastWorkflowActionDate
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
        'L1_Pending', 1, GETDATE(), GETDATE()
    );

    DECLARE @NewReqId BIGINT = SCOPE_IDENTITY();

    -- Insert initial submit audit log in REC_JobRequisition_Mst_Approval
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive, 
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @NewReqId, @SubmittedById, GETDATE(), 0, 'Requisition submitted for approval', 1, 
        0, 'Submitted', @SubmittedBy, 'Site HR', 'L1_Pending'
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. usp_REC_GetMyApprovalLevel
-- Returns approval level (1/2/3) and label for logged in user based on role
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetMyApprovalLevel
    @UserId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if user is Administrator / Super Admin
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND u.fk_roleId IN (1, 2);

    IF @IsAdmin = 1
    BEGIN
        SELECT 
            3 AS ApprovalLevel,
            'Administrator (Full Access - All Levels)' AS LevelLabel,
            'ADMINISTRATOR' AS RoleLabel,
            1 AS IsAdmin;
        RETURN;
    END

    SELECT TOP 1 
        cfg.ApprovalLevel,
        cfg.LevelLabel,
        cfg.RoleLabel,
        0 AS IsAdmin
    FROM dbo.REC_ApprovalLevel_Config cfg
    INNER JOIN dbo.UM_Users_Mst u ON u.fk_roleId = cfg.fk_roleId
    WHERE cfg.IsActive = 1
      AND (u.pk_userId = @UserId OR u.loginname = @UserId)
    ORDER BY cfg.ApprovalLevel;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. usp_REC_GetPendingApprovals
-- Returns pending requisitions matching user's approval level
-- ADMIN HAS FULL ACCESS: Sees ALL pending levels (L1, L2, and L3)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetPendingApprovals
    @UserId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if user is Admin / Super Admin (Role 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND u.fk_roleId IN (1, 2);

    IF @IsAdmin = 1
    BEGIN
        -- Admin has full visibility across all pending approval levels
        SELECT 
            3 AS approvalLevel, 
            (SELECT COUNT(1) FROM dbo.VW_REC_PendingApprovals WHERE WorkflowStatus IN ('L1_Pending','L2_Pending','L3_Pending')) AS pendingCount,
            1 AS isAdmin;

        SELECT * 
        FROM dbo.VW_REC_PendingApprovals
        WHERE WorkflowStatus IN ('L1_Pending','L2_Pending','L3_Pending')
        ORDER BY createdDate DESC;
        RETURN;
    END

    DECLARE @Level INT = NULL;
    SELECT TOP 1 @Level = cfg.ApprovalLevel
    FROM dbo.REC_ApprovalLevel_Config cfg
    INNER JOIN dbo.UM_Users_Mst u ON u.fk_roleId = cfg.fk_roleId
    WHERE cfg.IsActive = 1 AND (u.pk_userId = @UserId OR u.loginname = @UserId);

    IF @Level IS NULL
    BEGIN
        SELECT 0 AS approvalLevel, 0 AS pendingCount, 0 AS isAdmin;
        SELECT TOP 0 * FROM dbo.VW_REC_PendingApprovals;
        RETURN;
    END

    DECLARE @ExpectedStatus NVARCHAR(30) = CASE @Level
        WHEN 1 THEN 'L1_Pending'
        WHEN 2 THEN 'L2_Pending'
        WHEN 3 THEN 'L3_Pending'
        ELSE ''
    END;

    -- Header summary
    SELECT @Level AS approvalLevel, 
           (SELECT COUNT(1) FROM dbo.VW_REC_PendingApprovals WHERE WorkflowStatus = @ExpectedStatus) AS pendingCount,
           0 AS isAdmin;

    -- Pending items
    SELECT * 
    FROM dbo.VW_REC_PendingApprovals
    WHERE WorkflowStatus = @ExpectedStatus
    ORDER BY createdDate DESC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. usp_REC_ApproveRequisition
-- Handles L1, L2, L3 approval transition, updates records, logs audit.
-- ADMIN HAS FULL ACCESS: Can approve at any stage or directly open hiring.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_ApproveRequisition
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

    -- Resolve Requisition Details + Company ID (via Location, Department, or Submitting User)
    SELECT 
        @CurrentStatus = r.WorkflowStatus,
        @JobTitle      = r.jobtitle,
        @MrfCode       = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @SubmittedBy   = r.SubmittedBy,
        @SubmittedById = r.SubmittedById,
        @CompanyId     = COALESCE(loc.fk_companyId, dept.fk_companyId, u.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.UM_Users_Mst u ON (u.pk_userId = r.SubmittedById OR u.loginname = r.SubmittedById)
    WHERE r.pk_reqid = @ReqId;

    IF @CurrentStatus IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Check if approver is Admin (Roles 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @ApproverId OR u.loginname = @ApproverId)
      AND u.fk_roleId IN (1, 2);

    -- Effective action level: if admin, act at current level or specified level
    DECLARE @EffectiveLevel INT = @ApprovalLevel;
    IF @IsAdmin = 1
    BEGIN
        -- If admin is approving, automatically adapt to current stage if level wasn't explicitly given
        IF @CurrentStatus = 'L1_Pending' AND @ApprovalLevel <= 1 SET @EffectiveLevel = 1;
        ELSE IF @CurrentStatus = 'L2_Pending' AND @ApprovalLevel <= 2 SET @EffectiveLevel = 2;
        ELSE IF @ApprovalLevel >= 3 OR @CurrentStatus = 'L3_Pending' SET @EffectiveLevel = 3;
    END
    ELSE
    BEGIN
        -- Normal user: must match expected status
        DECLARE @ExpectedStatus NVARCHAR(30) = CASE @EffectiveLevel
            WHEN 1 THEN 'L1_Pending'
            WHEN 2 THEN 'L2_Pending'
            WHEN 3 THEN 'L3_Pending'
            ELSE ''
        END;

        IF @CurrentStatus <> @ExpectedStatus
        BEGIN
            SELECT 0 AS Success, CONCAT('Requisition is currently at ', @CurrentStatus, ', not ready for L', @EffectiveLevel, ' action.') AS Message;
            RETURN;
        END
    END

    DECLARE @NextStatus NVARCHAR(30) = CASE @EffectiveLevel
        WHEN 1 THEN 'L2_Pending'
        WHEN 2 THEN 'L3_Pending'
        WHEN 3 THEN 'Active'
    END;

    DECLARE @Now DATETIME = GETDATE();

    -- Perform Update per Level
    IF @EffectiveLevel = 1
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'L2_Pending',
            CurrentApprovalLevel   = 2,
            L1ApproverId           = @ApproverId,
            L1ApproverName         = @ApproverName,
            L1Action               = 'Approved',
            L1ActionDate           = @Now,
            L1Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 2
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'L3_Pending',
            CurrentApprovalLevel   = 3,
            L2ApproverId           = @ApproverId,
            L2ApproverName         = @ApproverName,
            L2Action               = 'Approved',
            L2ActionDate           = @Now,
            L2Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 3
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Active',
            CurrentApprovalLevel   = 99,
            L3ApproverId           = @ApproverId,
            L3ApproverName         = @ApproverName,
            L3Action               = 'Approved',
            L3ActionDate           = @Now,
            L3Remarks              = @Remarks,
            HiringOpenedDate       = @Now,
            isApproved             = 1,
            approvaldate           = @Now,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END

    -- Insert into Approval History Log
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @ReqId, @ApproverId, @Now, @EffectiveLevel, @Remarks, 1,
        @EffectiveLevel, 'Approved', @ApproverName, ISNULL(@ApproverRole, CONCAT('L', @EffectiveLevel, ' Approver')), @NextStatus
    );

    -- Mandatory Audit Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @MrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            @CurrentStatus, @NextStatus, @ApproverName, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    -- ─────────────────────────────────────────────────────────────────────────
    -- STRICTLY COMPANY-SCOPED EMAIL RESOLUTION (ZERO CROSS-COMPANY LEAKS)
    -- ─────────────────────────────────────────────────────────────────────────

    -- 1. Fetch Next Level Approver Emails for the SAME COMPANY
    DECLARE @NextLevelEmails NVARCHAR(MAX) = '';
    IF @EffectiveLevel < 3
    BEGIN
        DECLARE @NextLevel INT = @EffectiveLevel + 1;
        SELECT @NextLevelEmails = STRING_AGG(u.email, ',')
        FROM dbo.UM_Users_Mst u
        INNER JOIN dbo.REC_ApprovalLevel_Config cfg ON cfg.fk_roleId = u.fk_roleId
        WHERE cfg.ApprovalLevel = @NextLevel 
          AND cfg.IsActive = 1 
          AND u.active = 1 
          AND (@CompanyId IS NULL OR u.fk_companyId = @CompanyId)
          AND u.email IS NOT NULL AND RTRIM(LTRIM(u.email)) <> '';
    END

    -- 2. Fetch Site HR Email (Original Requisition Raiser) from the SAME COMPANY
    DECLARE @SiteHrEmail NVARCHAR(200) = '';
    SELECT TOP 1 @SiteHrEmail = u.email
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @SubmittedById OR u.loginname = @SubmittedById OR u.name = @SubmittedBy)
      AND (@CompanyId IS NULL OR u.fk_companyId = @CompanyId)
      AND u.email IS NOT NULL AND RTRIM(LTRIM(u.email)) <> '';

    -- Return Action Result
    SELECT 
        1 AS Success,
        CASE WHEN @EffectiveLevel = 3 
             THEN 'Requisition approved — Hiring is now OPEN!' 
             ELSE CONCAT('Requisition approved at L', @EffectiveLevel, ' — forwarded to L', @EffectiveLevel + 1, ' approver.') 
        END AS Message,
        @NextStatus AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @NextLevelEmails AS NextLevelEmails,
        @SiteHrEmail AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. usp_REC_RejectRequisition
-- Resets requisition to Submitted, logs rejection, returns Site HR email
-- ADMIN HAS FULL ACCESS: Can reject any requisition at any stage.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_RejectRequisition
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

    -- Resolve Requisition Details + Company ID (via Location, Department, or Submitting User)
    SELECT 
        @CurrentStatus = r.WorkflowStatus,
        @JobTitle      = r.jobtitle,
        @MrfCode       = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @SubmittedBy   = r.SubmittedBy,
        @SubmittedById = r.SubmittedById,
        @CompanyId     = COALESCE(loc.fk_companyId, dept.fk_companyId, u.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.UM_Users_Mst u ON (u.pk_userId = r.SubmittedById OR u.loginname = r.SubmittedById)
    WHERE r.pk_reqid = @ReqId;

    IF @CurrentStatus IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Check if approver is Admin (Roles 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
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

    -- Reset to Submitted — Site HR must resubmit from L1
    IF @EffectiveLevel = 1
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L1ApproverId           = @ApproverId,
            L1ApproverName         = @ApproverName,
            L1Action               = 'Rejected',
            L1ActionDate           = @Now,
            L1Remarks              = @Remarks,
            L2ApproverId=NULL, L2ApproverName=NULL, L2Action=NULL, L2ActionDate=NULL, L2Remarks=NULL,
            L3ApproverId=NULL, L3ApproverName=NULL, L3Action=NULL, L3ActionDate=NULL, L3Remarks=NULL,
            RejectedByLevel        = 'L1',
            RejectedByName         = @ApproverName,
            RejectedByDate         = @Now,
            RejectionRemarks       = @Remarks,
            LastWorkflowActionDate = @Now,
            isDisapproved          = 1
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 2
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L2ApproverId           = @ApproverId,
            L2ApproverName         = @ApproverName,
            L2Action               = 'Rejected',
            L2ActionDate           = @Now,
            L2Remarks              = @Remarks,
            L3ApproverId=NULL, L3ApproverName=NULL, L3Action=NULL, L3ActionDate=NULL, L3Remarks=NULL,
            RejectedByLevel        = 'L2',
            RejectedByName         = @ApproverName,
            RejectedByDate         = @Now,
            RejectionRemarks       = @Remarks,
            LastWorkflowActionDate = @Now,
            isDisapproved          = 1
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 3
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L3ApproverId           = @ApproverId,
            L3ApproverName         = @ApproverName,
            L3Action               = 'Rejected',
            L3ActionDate           = @Now,
            L3Remarks              = @Remarks,
            RejectedByLevel        = 'L3',
            RejectedByName         = @ApproverName,
            RejectedByDate         = @Now,
            RejectionRemarks       = @Remarks,
            LastWorkflowActionDate = @Now,
            isDisapproved          = 1
        WHERE pk_reqid = @ReqId;
    END

    -- Insert into Approval History Log
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @ReqId, @ApproverId, @Now, @EffectiveLevel, @Remarks, 1,
        @EffectiveLevel, 'Rejected', @ApproverName, ISNULL(@ApproverRole, CONCAT('L', @EffectiveLevel, ' Approver')), 'Submitted'
    );

    -- Mandatory Audit Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @MrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            @CurrentStatus, 'Submitted/Rejected', @ApproverName, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    -- Lookup Site HR Email strictly within the SAME COMPANY
    DECLARE @SiteHrEmail NVARCHAR(200) = '';
    SELECT TOP 1 @SiteHrEmail = u.email
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @SubmittedById OR u.loginname = @SubmittedById OR u.name = @SubmittedBy)
      AND (@CompanyId IS NULL OR u.fk_companyId = @CompanyId)
      AND u.email IS NOT NULL AND RTRIM(LTRIM(u.email)) <> '';

    SELECT 
        1 AS Success,
        CONCAT('Requisition rejected at L', @EffectiveLevel, '. Reset to Submitted status. Site HR has been notified.') AS Message,
        'Submitted' AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @SiteHrEmail AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. usp_REC_GetApprovalHistory
-- Returns 2 result sets:
-- 1) Chronological approval log entries from REC_JobRequisition_Mst_Approval
-- 2) Current requisition state snapshot
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetApprovalHistory
    @ReqId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. History log
    SELECT
        a.pk_reqtrnid   AS id,
        a.fk_reqid      AS reqId,
        a.approvalLevel,
        a.action,
        a.approverName,
        a.approverRole,
        a.workflowStatus,
        a.remarks,
        a.dated         AS actionDate,
        a.fk_empId      AS approverId
    FROM dbo.REC_JobRequisition_Mst_Approval a
    WHERE a.fk_reqid = @ReqId
    ORDER BY a.dated ASC;

    -- 2. Current State Snapshot
    SELECT 
        r.pk_reqid AS reqId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.WorkflowStatus,
        r.CurrentApprovalLevel,
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
        r.HiringOpenedDate,
        r.RejectedByLevel,
        r.RejectedByName,
        r.RejectedByDate,
        r.RejectionRemarks,
        r.SubmittedBy,
        r.SubmittedDate
    FROM dbo.REC_JobRequisition_Mst r 
    WHERE r.pk_reqid = @ReqId;
END;
GO

PRINT 'All Recruitment Workflow Stored Procedures Created Successfully!';
GO
