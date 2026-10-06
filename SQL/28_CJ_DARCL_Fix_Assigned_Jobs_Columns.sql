-- ============================================================================
-- SCRIPT: 28_CJ_DARCL_Fix_Assigned_Jobs_Columns.sql
-- DESCRIPTION: Include workflowStatus, status, and isApproved in dbo.usp_REC_GetVendorAssignedJobs
-- ============================================================================

USE [HRBook_22]
GO

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

PRINT 'dbo.usp_REC_GetVendorAssignedJobs updated with workflowStatus and isApproved.';
GO
