-- =============================================================================
-- Migration 06: Add Approval Workflow Columns to REC_JobRequisition_Mst
-- CJ DARCL Recruitment Module - Multi-Level Requisition Approval Workflow
-- Date   : 22-Sep-2026
-- Workflow: Site HR -> L1 (Operations) -> L2 (Corporate HR) -> L3 (HOD) -> Active
-- =============================================================================

USE HRBook_22;
GO

-- WorkflowStatus values:
--   Submitted  : Submitted by Site HR, awaiting L1 action
--   L1_Pending : Waiting for L1 (Operations) approval
--   L1_Rejected: L1 rejected - back to Site HR for resubmit
--   L2_Pending : Waiting for L2 (Corporate HR) approval
--   L2_Rejected: L2 rejected - back to Site HR for resubmit
--   L3_Pending : Waiting for L3 (HOD) approval
--   L3_Rejected: L3 rejected - back to Site HR for resubmit
--   Active     : All 3 levels approved - Hiring is OPEN
--   Closed     : Fulfilled or cancelled

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'REC_JobRequisition_Mst' AND COLUMN_NAME = 'WorkflowStatus')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD
        -- Workflow State
        WorkflowStatus          NVARCHAR(30)   NOT NULL CONSTRAINT DF_Req_WorkflowStatus    DEFAULT 'Submitted',
        CurrentApprovalLevel    INT            NOT NULL CONSTRAINT DF_Req_CurrApprovalLevel DEFAULT 1,
        -- 1=L1 pending, 2=L2 pending, 3=L3 pending, 99=Active, 0=Rejected

        -- L1 Approval (Operations Team)
        L1ApproverId            NVARCHAR(50)   NULL,
        L1ApproverName          NVARCHAR(200)  NULL,
        L1Action                NVARCHAR(20)   NULL,
        L1ActionDate            DATETIME       NULL,
        L1Remarks               NVARCHAR(500)  NULL,

        -- L2 Approval (Corporate HR)
        L2ApproverId            NVARCHAR(50)   NULL,
        L2ApproverName          NVARCHAR(200)  NULL,
        L2Action                NVARCHAR(20)   NULL,
        L2ActionDate            DATETIME       NULL,
        L2Remarks               NVARCHAR(500)  NULL,

        -- L3 Approval (HOD / Regional Head)
        L3ApproverId            NVARCHAR(50)   NULL,
        L3ApproverName          NVARCHAR(200)  NULL,
        L3Action                NVARCHAR(20)   NULL,
        L3ActionDate            DATETIME       NULL,
        L3Remarks               NVARCHAR(500)  NULL,

        -- Outcome
        HiringOpenedDate        DATETIME       NULL,
        RejectedByLevel         NVARCHAR(10)   NULL,
        RejectedByName          NVARCHAR(200)  NULL,
        RejectedByDate          DATETIME       NULL,
        RejectionRemarks        NVARCHAR(500)  NULL,

        -- Submit Tracking
        SubmittedDate           DATETIME       NULL,
        LastWorkflowActionDate  DATETIME       NULL;

    PRINT 'Workflow columns added to REC_JobRequisition_Mst';
END
ELSE
BEGIN
    PRINT 'Workflow columns already exist - skipped.';
END
GO

-- Backfill: mark existing approved records as Active
UPDATE dbo.REC_JobRequisition_Mst
SET    WorkflowStatus       = 'Active',
       CurrentApprovalLevel = 99,
       HiringOpenedDate     = approvaldate
WHERE  WorkflowStatus = 'Submitted'
  AND  (isApproved = 1 OR final_approval IS NOT NULL);

PRINT 'Existing approved records set to Active.';
GO
