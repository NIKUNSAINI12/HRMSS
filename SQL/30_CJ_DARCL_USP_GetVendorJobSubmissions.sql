-- ============================================================================
-- SCRIPT: 30_CJ_DARCL_USP_GetVendorJobSubmissions.sql
-- DESCRIPTION: Stored procedure to fetch all candidates submitted by a vendor
--              for a specific Job Requisition (MRF), including current stage,
--              status, Aadhaar, Phone, and submission date.
-- ============================================================================

USE [HRBook_22]
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorJobSubmissions
    @VendorId    NVARCHAR(50),
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ISNULL(ca.Stage, 'Applied')                                      AS stage,
        ISNULL(ca.InterviewStatus, 'Pending')                            AS interviewStatus,
        ISNULL(ca.SkillClassification, 'Semi-Skilled')                   AS skillClassification,
        ca.CurrentLocation                                               AS location,
        ISNULL(ca.IsRejected, 0)                                         AS isRejected,
        ca.RejectionReason                                               AS rejectionReason,
        ca.CreatedDate                                                   AS submittedDate,
        ca.LastUpdatedDate                                               AS lastUpdatedDate
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.fk_reqid = @ReqId
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
    ORDER BY ca.CreatedDate DESC;
END;
GO

PRINT 'dbo.usp_REC_GetVendorJobSubmissions created successfully.';
GO
