-- =============================================================================
-- Migration 07: Approval Workflow - Log Extension + Config Master
-- CJ DARCL Recruitment Module - Multi-Level Requisition Approval Workflow
-- Date   : 22-Sep-2026
-- Tables : REC_JobRequisition_Mst_Approval (extend), REC_ApprovalLevel_Config (new)
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: Extend existing REC_JobRequisition_Mst_Approval audit log
-- ─────────────────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst_Approval' AND COLUMN_NAME = 'approvalLevel')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst_Approval
    ADD
        approvalLevel   INT             NOT NULL DEFAULT 1,   -- 0=Submit, 1=L1, 2=L2, 3=L3
        action          NVARCHAR(20)    NULL,                 -- Submitted | Approved | Rejected
        approverName    NVARCHAR(200)   NULL,
        approverRole    NVARCHAR(100)   NULL,
        workflowStatus  NVARCHAR(30)    NULL;                 -- snapshot of status at time of action

    PRINT 'Approval log columns extended.';
END
ELSE
BEGIN
    PRINT 'Approval log columns already exist - skipped.';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: Create REC_ApprovalLevel_Config master table
-- Maps UM_Role_Mst role -> Approval Level (L1/L2/L3)
-- Configured by Administrator; no code change needed to change role mapping
-- ─────────────────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'REC_ApprovalLevel_Config')
BEGIN
    CREATE TABLE dbo.REC_ApprovalLevel_Config (
        pk_id           INT             IDENTITY(1,1)   PRIMARY KEY,
        ApprovalLevel   INT             NOT NULL,        -- 1, 2, or 3
        LevelLabel      NVARCHAR(50)    NOT NULL,        -- 'L1 - Operations Team' etc.
        fk_roleId       INT             NOT NULL,        -- FK to UM_Role_Mst.pk_roleId
        RoleLabel       NVARCHAR(100)   NULL,            -- display name (denormalized for speed)
        EmailsToNotify  NVARCHAR(500)   NULL,            -- comma-sep fallback emails if no user found
        IsActive        BIT             NOT NULL DEFAULT 1,
        fk_insUserID    NVARCHAR(50)    NULL,
        fk_insDateID    DATETIME        NOT NULL DEFAULT GETDATE()
    );

    PRINT 'REC_ApprovalLevel_Config table created.';

    -- Seed initial config
    -- IMPORTANT: Update fk_roleId values to match your actual UM_Role_Mst.pk_roleId
    -- Lookup: SELECT pk_roleId, roleName FROM dbo.UM_Role_Mst
    INSERT INTO dbo.REC_ApprovalLevel_Config (ApprovalLevel, LevelLabel, fk_roleId, RoleLabel, IsActive)
    VALUES
        (1, 'L1 - Operations Team',    7, 'HR Manager',    1),
        (2, 'L2 - Corporate HR',       2, 'SUPER ADMIN',   1),
        (3, 'L3 - HOD',                1, 'ADMINISTRATOR', 1);

    PRINT 'Default L1/L2/L3 role seed inserted. Update fk_roleId values as needed.';
END
ELSE
BEGIN
    PRINT 'REC_ApprovalLevel_Config already exists - skipped.';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 3: Helper view — pending approvals by level (used by GetPendingApprovals API)
-- ─────────────────────────────────────────────────────────────────────────────

IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'VW_REC_PendingApprovals')
    DROP VIEW dbo.VW_REC_PendingApprovals;
GO

CREATE VIEW dbo.VW_REC_PendingApprovals AS
SELECT
    r.pk_reqid          AS reqId,
    ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
    r.jobtitle          AS jobTitle,
    r.WorkflowStatus,
    r.CurrentApprovalLevel,
    r.SubmittedBy,
    r.SubmittedDate,
    r.LastWorkflowActionDate,
    r.IsBufferUtilized,
    r.BufferHeadsUtilized,
    ISNULL(loc.locname, '') AS location,
    ISNULL(dept.description, '') AS department,
    ISNULL(des.designation, '') AS designation,
    r.No_of_post        AS openPositions,
    r.dated             AS createdDate
FROM dbo.REC_JobRequisition_Mst r
LEFT JOIN dbo.Location_Mst loc   ON loc.pk_locid   = r.fk_locid
LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
WHERE r.WorkflowStatus IN ('L1_Pending','L2_Pending','L3_Pending');
GO

PRINT 'VW_REC_PendingApprovals view created.';
GO
