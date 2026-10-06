-- =============================================================================
-- SQL MIGRATION SCRIPT #23: CJ DARCL ATS - VENDOR PORTAL APPROVED JOBS ONLY
-- Enforces that Vendors can ONLY see and submit candidates for APPROVED jobs.
-- WorkflowStatus = 'Active' OR status = 'A' OR RequisitionStatus = 'Active'
-- =============================================================================

USE [HRBook_22];
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Update dbo.usp_REC_GetVendorAssignedJobs (ONLY APPROVED REQUISITIONS)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorAssignedJobs
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    SELECT 
        jm.pk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', YEAR(jm.dated), '/', jm.pk_reqid)) AS mrfCode,
        jm.jobtitle                                                      AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
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
        -- Sourced by this vendor for this MRF
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS submittedCount,
        -- Reached 'Selected' from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Selected'
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
        ) AS selectedCount,
        -- Hired from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Hired'
              AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
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
      AND (jm.CompanyId = @CompanyId OR jm.fk_companyId = @CompanyId)
    ORDER BY rvm.AssignedDate DESC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Update dbo.usp_REC_GetVendorPortalMetrics (COUNT APPROVED JOBS ONLY)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPortalMetrics
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    -- 1. Total Assigned MRFs (Active & Approved only)
    DECLARE @AssignedJobsCount INT = 0;
    SELECT @AssignedJobsCount = COUNT(1)
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      -- MANDATORY: Count ONLY APPROVED jobs
      AND (
          jm.WorkflowStatus = 'Active' 
          OR jm.status = 'A' 
          OR jm.RequisitionStatus = 'Active' 
          OR jm.WorkflowStatus = 'Approved'
      )
      AND (jm.CompanyId = @CompanyId OR jm.fk_companyId = @CompanyId);

    -- 2. Total Applications Submitted
    DECLARE @TotalSubmissions INT = 0;
    SELECT @TotalSubmissions = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 3. Candidates in Review / Interviewing
    DECLARE @InReviewCount INT = 0;
    SELECT @InReviewCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage NOT IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Issued', 'Hired')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 4. Selected Candidates (ACTION REQUIRED: Upload Dossier & Documents)
    DECLARE @SelectedCount INT = 0;
    SELECT @SelectedCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Selected'
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    -- 5. Joined / Hired
    DECLARE @HiredCount INT = 0;
    SELECT @HiredCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Hired'
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId);

    SELECT 
        @AssignedJobsCount AS assignedJobsCount,
        @TotalSubmissions  AS totalSubmissions,
        @InReviewCount     AS inReviewCount,
        @SelectedCount     AS selectedCount,
        @HiredCount        AS hiredCount;
END;
GO
