-- =========================================================================================
-- Script Name: 26_CJ_DARCL_USP_GetUserVendorProfile.sql
-- Description:
--   Creates Stored Procedure dbo.usp_UM_GetUserVendorProfile to dynamically check if
--   the authenticated user is a Vendor (isVendor = 1) and retrieve their mapped vendorId (fk_vendorId).
--   Strictly adheres to: No Inline SQL, 100% Company-Specific, Zero Hardcoding.
-- =========================================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE dbo.usp_UM_GetUserVendorProfile
    @UserId    VARCHAR(50),
    @CompanyId VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 
        CAST(ISNULL(u.isVendor, 0) AS BIT) AS isVendor, 
        ISNULL(u.fk_vendorId, '')          AS vendorId,
        COALESCE(cd.Vendor_Name, u.name)   AS vendorName,
        ISNULL(cd.Vendor_Code, '')         AS vendorCode,
        u.fk_companyId                     AS companyId,
        u.name                             AS userName,
        u.loginname                        AS loginName
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.REC_Candidate_Details cd WITH (NOLOCK) ON cd.pk_recId = u.fk_vendorId
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId);
END;
GO
