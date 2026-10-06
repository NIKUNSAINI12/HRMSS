-- =============================================================================
-- Migration 58: CJ DARCL - Resolve Approval Notifications and Emails via Page Rights (L1, L2, L3)
-- Standards: 100% Company-Specific, Zero Hardcoding, Page Rights Architecture
-- Purpose:
--   1. Update dbo.usp_REC_ApproveRequisition to resolve L1/L2/L3 approvers
--      from UM_UserPageRights (L1_Access, L2_Access, L3_Access = 1).
--   2. Update dbo.usp_REC_RejectRequisition to resolve Site HR email and return
--      full template metadata for HTML email notifications.
--   3. Return rich metadata (MrfCode, JobTitle, Department, Location, Openings,
--      ApproverName, Remarks, ActionDate) to render editable HTML email templates.
-- =============================================================================

USE HRBook_22;
GO

PRINT 'Starting Migration 58: Page Rights (L1, L2, L3) Email and Notification Resolution...';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. UPDATE dbo.usp_REC_ApproveRequisition
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

    -- Effective action level: if admin, act at current level or specified level
    DECLARE @EffectiveLevel INT = @ApprovalLevel;
    IF @IsAdmin = 1
    BEGIN
        IF @CurrentStatus = 'L1_Pending' AND @ApprovalLevel <= 1 SET @EffectiveLevel = 1;
        ELSE IF @CurrentStatus = 'L2_Pending' AND @ApprovalLevel <= 2 SET @EffectiveLevel = 2;
        ELSE IF @ApprovalLevel >= 3 OR @CurrentStatus = 'L3_Pending' SET @EffectiveLevel = 3;
    END
    ELSE
    BEGIN
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
    -- NOTIFICATION & EMAIL RESOLUTION ACCORDING TO PAGE RIGHTS (L1, L2, L3)
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @NextLevelEmails NVARCHAR(MAX) = '';

    -- If approved at L1 (moving to L2_Pending) -> Fetch users with L2_Access = 1 in UM_UserPageRights
    IF @EffectiveLevel = 1
    BEGIN
        SELECT @NextLevelEmails = STRING_AGG(Email, ',')
        FROM (
            SELECT DISTINCT COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) AS Email
            FROM dbo.UM_Users_Mst u WITH (NOLOCK)
            INNER JOIN dbo.UM_UserPageRights upr WITH (NOLOCK) ON upr.fk_userId = u.pk_userId
            LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
            WHERE upr.L2_Access = 1
              AND u.active = 1
              AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
              AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL
        ) src;
    END

    -- If approved at L2 (moving to L3_Pending) -> Fetch users with L3_Access = 1 in UM_UserPageRights
    ELSE IF @EffectiveLevel = 2
    BEGIN
        SELECT @NextLevelEmails = STRING_AGG(Email, ',')
        FROM (
            SELECT DISTINCT COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) AS Email
            FROM dbo.UM_Users_Mst u WITH (NOLOCK)
            INNER JOIN dbo.UM_UserPageRights upr WITH (NOLOCK) ON upr.fk_userId = u.pk_userId
            LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
            WHERE upr.L3_Access = 1
              AND u.active = 1
              AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
              AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL
        ) src;
    END

    -- Fetch Site HR Email (Original Requisition Raiser) from the SAME COMPANY
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
        CASE WHEN @EffectiveLevel = 3 
             THEN 'Requisition approved — Hiring is now OPEN!' 
             ELSE CONCAT('Requisition approved at L', @EffectiveLevel, ' — forwarded to L', @EffectiveLevel + 1, ' approver.') 
        END AS Message,
        @NextStatus AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @DeptName AS Department,
        @LocName AS Location,
        @OpeningsCount AS Openings,
        @SubmittedBy AS SubmittedBy,
        @ApproverName AS ApproverName,
        @EffectiveLevel AS EffectiveLevel,
        ISNULL(@Remarks, 'Approved') AS Remarks,
        CONVERT(VARCHAR(19), @Now, 120) AS ActionDate,
        ISNULL(@NextLevelEmails, '') AS NextLevelEmails,
        ISNULL(@SiteHrEmail, '') AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. UPDATE dbo.usp_REC_RejectRequisition
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
            LastWorkflowActionDate = @Now
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
            LastWorkflowActionDate = @Now
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
            LastWorkflowActionDate = @Now
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
            @CurrentStatus, 'Submitted', @ApproverName, GETDATE()
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
        CONCAT('Requisition rejected at L', @EffectiveLevel, ' — returned to Submitted status.') AS Message,
        'Submitted' AS NewStatus,
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

PRINT 'Migration 58 completed: dbo.usp_REC_ApproveRequisition and dbo.usp_REC_RejectRequisition updated to resolve approver emails via Page Rights (L1/L2/L3).';
GO
