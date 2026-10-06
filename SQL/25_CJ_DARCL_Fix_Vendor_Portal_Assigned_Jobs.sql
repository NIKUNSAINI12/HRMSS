-- =========================================================================================
-- Script Name: 25_CJ_DARCL_Fix_Vendor_Portal_Assigned_Jobs.sql
-- Description:
--   1. Fixes dbo.usp_REC_GetVendorAssignedJobs to return all active approved jobs 
--      assigned to @VendorId regardless of whether Requisition was created in GU-1 or GU-8
--   2. Fixes dbo.usp_REC_GetVendorPortalMetrics to accurately count metrics for @VendorId
--   3. Fixes dbo.usp_REC_GetVendorListForPortal to include vendors across CJ DARCL / HRBOOK
--   4. Maps Requisition 1 and Requisition 6 to GU-39 in REC_Requisition_Vendor_Mapping
-- =========================================================================================

USE [HRBook_22];
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Ensure REC_Requisition_Vendor_Mapping has Job 1 and Job 6 mapped to GU-39
-- ─────────────────────────────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping WHERE fk_reqid = 6 AND fk_vendorId = 'GU-39')
BEGIN
    INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
        fk_reqid, fk_vendorId, VendorName, VendorCode, AllocatedQuota, CommissionTerms, 
        IsActive, AssignedBy, AssignedDate, fk_companyId, VendorType, CompanyId
    )
    VALUES (
        6, 'GU-39', 'ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED', 'V011', 10, 'Standard (8.33%)',
        1, 'Admin', GETDATE(), 'GU-1', 'Supply Vendors', 'GU-1'
    );
    PRINT 'Mapped Req 6 to GU-39';
END
ELSE
BEGIN
    UPDATE dbo.REC_Requisition_Vendor_Mapping
    SET IsActive = 1
    WHERE fk_reqid = 6 AND fk_vendorId = 'GU-39';
    PRINT 'Ensured Req 6 mapping active for GU-39';
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping WHERE fk_reqid = 1 AND fk_vendorId = 'GU-39')
BEGIN
    INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
        fk_reqid, fk_vendorId, VendorName, VendorCode, AllocatedQuota, CommissionTerms, 
        IsActive, AssignedBy, AssignedDate, fk_companyId, VendorType, CompanyId
    )
    VALUES (
        1, 'GU-39', 'ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED', 'V011', 15, 'Standard (8.33%)',
        1, 'Admin', GETDATE(), 'GU-1', 'Supply Vendors', 'GU-1'
    );
    PRINT 'Mapped Req 1 to GU-39';
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Update dbo.usp_REC_GetVendorAssignedJobs
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
        ) AS submittedCount,
        -- Reached 'Selected' from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Selected'
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Update dbo.usp_REC_GetVendorPortalMetrics
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPortalMetrics
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Total Assigned MRFs (Active & Approved only)
    DECLARE @AssignedJobsCount INT = 0;
    SELECT @AssignedJobsCount = COUNT(1)
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

    -- 2. Total Applications Submitted
    DECLARE @TotalSubmissions INT = 0;
    SELECT @TotalSubmissions = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId;

    -- 3. Candidates in Review / Interviewing
    DECLARE @InReviewCount INT = 0;
    SELECT @InReviewCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage NOT IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Issued', 'Hired')
      AND ISNULL(ca.IsRejected, 0) = 0;

    -- 4. Selected Candidates (ACTION REQUIRED: Upload Dossier & Documents)
    DECLARE @SelectedCount INT = 0;
    SELECT @SelectedCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Selected'
      AND ISNULL(ca.IsRejected, 0) = 0;

    -- 5. Joined / Hired
    DECLARE @HiredCount INT = 0;
    SELECT @HiredCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Hired';

    SELECT 
        @AssignedJobsCount AS assignedJobsCount,
        @TotalSubmissions  AS totalSubmissions,
        @InReviewCount     AS inReviewCount,
        @SelectedCount     AS selectedCount,
        @HiredCount        AS hiredCount;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Update dbo.usp_REC_GetVendorListForPortal
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorListForPortal
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS contactNo,
        ISNULL(cd.email, '')                                           AS email,
        -- Total Active MRFs Assigned to this vendor
        (
            SELECT COUNT(DISTINCT rvm.fk_reqid)
            FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
            INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
            WHERE rvm.fk_vendorId = cd.pk_recId
              AND rvm.IsActive = 1
              AND (jm.RequisitionStatus = 'Active' OR jm.WorkflowStatus = 'Active' OR jm.status = 'A')
        ) AS assignedJobsCount,
        -- Total Candidates Sourced by this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_vendorId = cd.pk_recId
        ) AS totalCandidatesSourced
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK) ON rvm.fk_vendorId = cd.pk_recId
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL OR @CompanyId = '' 
          OR cd.CompanyId = @CompanyId 
          OR cd.fk_companyId = @CompanyId
          OR rvm.CompanyId = @CompanyId
          OR rvm.fk_companyId = @CompanyId
          OR @CompanyId IN ('GU-1', 'GU-8')
      )
    ORDER BY vendorName ASC;
END;
GO
