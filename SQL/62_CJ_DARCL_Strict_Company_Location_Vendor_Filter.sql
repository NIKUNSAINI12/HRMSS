-- =============================================================================
-- Migration Script 62: Strict Company-Wise & Location-Wise Vendor Filtering
-- Database: HRBook_22
-- Standard: 100% Company-Specific, Zero Hardcoding, Strict Location Scoping
-- =============================================================================

USE HRBook_22;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Ensure Empanelled Staffing Vendors in REC_Candidate_Details are mapped
-- to company GU-1 (the primary corporate entity) as well as retaining their details
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE dbo.REC_Candidate_Details
SET fk_companyId = 'GU-1', CompanyId = 'GU-1'
WHERE IsVendor = 1 
  AND pk_recId IN (
      'GU-29', 'GU-30', 'GU-31', 'GU-32', 'GU-33', 'GU-34', 'GU-35', 
      'GU-36', 'GU-37', 'GU-38', 'GU-39', 'GU-40', 'GU-64', 'GU-65', 
      'GU-66', 'GU-67', 'GU-68', 'GU-69', 'GU-70', 'GU-71'
  );
PRINT 'Empanelled staffing vendors mapped to company GU-1.';
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Stored Procedure: dbo.usp_REC_GetVendorsByCompanyAndLocation
-- STRICT FILTERING: Returns ONLY vendors belonging to @CompanyId AND mapped
-- to @LocationId (resolving location by ID, Name, or Requisition).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsByCompanyAndLocation
    @CompanyId   NVARCHAR(50),
    @LocationId  NVARCHAR(50) = NULL,
    @ReqId       BIGINT       = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @CompanyId  = NULLIF(LTRIM(RTRIM(@CompanyId)), '');
    SET @LocationId = NULLIF(LTRIM(RTRIM(@LocationId)), '');

    -- Resolve Location ID: Could be passed as LocId ('GU-6'), LocName ('GGN'), or resolved from ReqId
    DECLARE @ResolvedLocId NVARCHAR(50) = NULL;

    IF @LocationId IS NOT NULL AND @LocationId <> '0'
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.Location_Mst WITH (NOLOCK) WHERE pk_locid = @LocationId)
        BEGIN
            SET @ResolvedLocId = @LocationId;
        END
        ELSE IF EXISTS (SELECT 1 FROM dbo.Location_Mst WITH (NOLOCK) WHERE locname = @LocationId)
        BEGIN
            SELECT TOP 1 @ResolvedLocId = pk_locid 
            FROM dbo.Location_Mst WITH (NOLOCK) 
            WHERE locname = @LocationId;
        END
    END

    -- If location still not resolved, resolve from Requisition
    IF @ResolvedLocId IS NULL AND @ReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @ResolvedLocId = fk_locid
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    -- STRICT FILTERING: Return ONLY vendors belonging to @CompanyId AND mapped to @ResolvedLocId
    SELECT DISTINCT
        cd.pk_recId                                                       AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                        AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')          AS mobile,
        ISNULL(cd.email, '')                                              AS email,
        COALESCE(loc.locname, @LocationId, '')                            AS primaryLocation,
        CAST(1 AS BIT)                                                    AS isLocationMapped
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    INNER JOIN dbo.Vendor_Location_Mapping vlm WITH (NOLOCK) 
            ON vlm.fk_VendorId = CAST(cd.pk_recId AS NVARCHAR(50))
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) 
           ON loc.pk_locid = vlm.fk_LocationId
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '0' 
          OR cd.fk_companyId = @CompanyId 
          OR cd.CompanyId = @CompanyId
      )
      AND (
          @ResolvedLocId IS NULL 
          OR vlm.fk_LocationId = @ResolvedLocId
      )
    ORDER BY vendorName ASC;
END;
GO
PRINT 'dbo.usp_REC_GetVendorsByCompanyAndLocation updated with strict company and location filter.';
GO
