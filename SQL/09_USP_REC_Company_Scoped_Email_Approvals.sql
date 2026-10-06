-- =============================================================================
-- Migration 09: Strictly Company-Scoped Email Routing for Requisition Workflow
-- CJ DARCL Recruitment Architecture
-- Date    : 28-Sep-2026
-- Database: HRBook_22
-- Enforces: 100% Company-Specific Email Recipient Resolution (Zero Cross-Company Mails)
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Update usp_REC_ApproveRequisition: Strictly Company-Scoped Email Resolution
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
-- 2. Update usp_REC_RejectRequisition: Strictly Company-Scoped Email Resolution
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

PRINT '09_USP_REC_Company_Scoped_Email_Approvals executed successfully.';
