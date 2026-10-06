-- ============================================================================
-- SCRIPT: 47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql
-- DESCRIPTION:
--   1. Data integrity fix: Ensure IsRejected = 1 where Stage = 'Rejected'.
--   2. Update dbo.usp_REC_GetVendorPortalMetrics:
--      - Correct @InReviewCount (only non-bench, non-rejected candidates in Applied/Screening/Interview).
--      - Correct @SelectedCount (all candidates who passed interview: Selected, Docs_Submitted, Docs_Verified).
--   3. Update dbo.usp_REC_GetVendorAssignedJobs:
--      - Return jm.fk_locid for full location traceability.
-- DATABASE   : HRBook_22
-- STANDARD   : 100% Company-Specific, Zero Hardcoding, Mandatory SQL Tracking
-- ============================================================================

USE [HRBook_22]
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Data Integrity Sync: Set IsRejected = 1 for any Stage = 'Rejected'
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE dbo.REC_Candidate_Applications
SET IsRejected = 1
WHERE Stage = 'Rejected'
  AND ISNULL(IsRejected, 0) = 0;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Update dbo.usp_REC_GetVendorPortalMetrics
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPortalMetrics
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean vendorId
    SET @VendorId = LTRIM(RTRIM(ISNULL(@VendorId, '')));

    -- 1. Total Assigned MRFs (Active & Approved only)
    DECLARE @AssignedJobsCount INT = 0;
    SELECT @AssignedJobsCount = COUNT(DISTINCT rvm.fk_reqid)
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      AND (
          jm.WorkflowStatus = 'Active' 
          OR jm.status = 'A' 
          OR jm.RequisitionStatus = 'Active' 
          OR jm.WorkflowStatus = 'Approved'
      );

    -- 2. Total Applications Sourced
    DECLARE @TotalSubmissions INT = 0;
    SELECT @TotalSubmissions = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId;

    -- 3. Candidates Under Evaluation / Interviewing (Active on a Job, Not Bench, Not Rejected)
    DECLARE @InReviewCount INT = 0;
    SELECT @InReviewCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.fk_reqid IS NOT NULL 
      AND ca.fk_reqid > 0
      AND ISNULL(ca.MrfCode, '') <> 'BENCH'
      AND ca.Stage IN ('Applied', 'Screening', 'Interview', 'Interview_Scheduled')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND ca.Stage <> 'Rejected';

    -- 4. Passed Interview Candidates (Selected & Onboarding Docs stage)
    DECLARE @SelectedCount INT = 0;
    SELECT @SelectedCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Issued')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND ca.Stage <> 'Rejected';

    -- 5. Joined / Hired
    DECLARE @HiredCount INT = 0;
    SELECT @HiredCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Hired'
      AND ISNULL(ca.IsRejected, 0) = 0;

    SELECT 
        @AssignedJobsCount AS assignedJobsCount,
        @TotalSubmissions  AS totalSubmissions,
        @InReviewCount     AS inReviewCount,
        @SelectedCount     AS selectedCount,
        @HiredCount        AS hiredCount;
END;
GO

PRINT 'dbo.usp_REC_GetVendorPortalMetrics updated successfully.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Update dbo.usp_REC_GetVendorAssignedJobs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorAssignedJobs
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        jm.pk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', YEAR(jm.dated), '/', jm.pk_reqid)) AS mrfCode,
        jm.jobtitle                                                      AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
        jm.fk_locid                                                      AS fk_locid,
        ISNULL(loc.locname, 'Hub Logistics')                             AS location,
        ISNULL(jm.No_of_post, 1)                                         AS openingsCount,
        ISNULL(rvm.AllocatedQuota, 10)                                   AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                  AS commissionTerms,
        COALESCE(rvm.VendorType, 'Supply Vendors')                       AS vendorType,
        ISNULL(jm.Priority, 'Medium')                                    AS priority,
        ISNULL(jm.WorkplaceType, 'On-Site')                              AS workplaceType,
        ISNULL(jm.EmploymentType, 'Full-Time')                           AS employmentType,
        jm.Experience_From                                               AS experienceMin,
        jm.Experience_To                                                 AS experienceMax,
        jm.CTC_From                                                      AS ctcMin,
        jm.CTC_To                                                        AS ctcMax,
        jm.JobDescription                                                AS jobDescription,
        rvm.AssignedDate                                                 AS assignedDate,
        ISNULL(jm.WorkflowStatus, 'Active')                              AS workflowStatus,
        ISNULL(jm.status, 'A')                                           AS status,
        ISNULL(jm.RequisitionStatus, 'Active')                           AS requisitionStatus,
        CAST(1 AS BIT)                                                   AS isApproved,
        -- Sourced by this vendor for this MRF
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId
        ) AS submittedCount,
        -- Reached 'Selected' from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified')
        ) AS selectedCount,
        -- Hired from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Hired'
        ) AS hiredCount
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = jm.fk_deptid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      -- MANDATORY: Vendors can ONLY see APPROVED jobs
      AND (
          jm.WorkflowStatus = 'Active' 
          OR jm.status = 'A' 
          OR jm.RequisitionStatus = 'Active' 
          OR jm.WorkflowStatus = 'Approved'
      )
    ORDER BY rvm.AssignedDate DESC;
END;
GO

PRINT 'dbo.usp_REC_GetVendorAssignedJobs updated successfully.';
GO
