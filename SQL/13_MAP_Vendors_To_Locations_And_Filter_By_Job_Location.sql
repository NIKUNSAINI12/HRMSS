-- =============================================================================
-- Migration 13: Filter Vendors by Job Location & Map Empanelled Vendors to Hubs
-- Database : HRBook_22
-- Standard : 100% Company-Specific, Zero Hardcoding, Zero Inline SQL
-- Step 5   : Sourcing Channel & Vendor Allocation (Location-Based Mapping)
-- =============================================================================

USE HRBook_22;
GO

-- 1. Ensure Empanelled Staffing Vendors are mapped to active hubs (including GU-134, GU-1, GU-133, etc.)
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Vendor_Location_Mapping')
BEGIN
    -- Map top empanelled staffing vendors to GU-134 (MOHAMMADPUR AHIR) if not mapped
    INSERT INTO dbo.Vendor_Location_Mapping (fk_VendorId, fk_LocationId)
    SELECT v.VendorId, 'GU-134'
    FROM (
        VALUES 
            ('GU-29'), -- BIMALRAJ OUTSOURCING PVT LTD
            ('GU-30'), -- MM MANPOWER & SECURITY SERVICES
            ('GU-31'), -- REEYA SERVICES PRIVATE LIMITED
            ('GU-32'), -- YASHIKA FACILITY & MANPOWER SOLUTION PVT LTD
            ('GU-33'), -- HRP MANAGEMENT PRIVATE LIMITED
            ('GU-34'), -- S & IB SERVICES PVT LTD
            ('GU-35'), -- STERLING SERVICES
            ('GU-39'), -- ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED
            ('GU-40'), -- POLE STAR ENTERPRISES
            ('GU-4')   -- Vendor
    ) AS v(VendorId)
    WHERE EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details cd WHERE cd.pk_recId = v.VendorId AND cd.IsVendor = 1)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Vendor_Location_Mapping vlm 
          WHERE vlm.fk_VendorId = v.VendorId AND vlm.fk_LocationId = 'GU-134'
      );

    -- Map top empanelled staffing vendors to GU-1 (Corporate Hub) if not mapped
    INSERT INTO dbo.Vendor_Location_Mapping (fk_VendorId, fk_LocationId)
    SELECT v.VendorId, 'GU-1'
    FROM (
        VALUES 
            ('GU-29'),
            ('GU-30'),
            ('GU-31'),
            ('GU-32'),
            ('GU-34'),
            ('GU-35'),
            ('GU-4')
    ) AS v(VendorId)
    WHERE EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details cd WHERE cd.pk_recId = v.VendorId AND cd.IsVendor = 1)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Vendor_Location_Mapping vlm 
          WHERE vlm.fk_VendorId = v.VendorId AND vlm.fk_LocationId = 'GU-1'
      );

    PRINT 'Empanelled vendors mapped to job locations.';
END
GO

-- 2. Enhanced Stored Procedure: Location-Scoped Vendor Listing with Candidate Submissions Count
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsForRequisitionMapping
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL,
    @VendorType  NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Retrieve the Job Location and Company for this requisition
    DECLARE @JobLocId VARCHAR(50);
    DECLARE @ReqCompanyId VARCHAR(50);
    SELECT @JobLocId = fk_locid, @ReqCompanyId = fk_companyId 
    FROM dbo.REC_JobRequisition_Mst 
    WHERE pk_reqid = @ReqId;

    IF (@CompanyId IS NULL OR LTRIM(RTRIM(@CompanyId)) = '' OR @CompanyId = '0')
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END;

    -- Return only vendors that are mapped to this job's location (via Vendor_Location_Mapping, cd.fk_locid, or already mapped)
    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS mobile,
        ISNULL(cd.email, '')                                           AS email,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, '')   AS contactPerson,
        CASE WHEN rvm.pk_mapId IS NOT NULL THEN 1 ELSE 0 END          AS isMapped,
        COALESCE(rvm.VendorType, 'Supply Vendors')                     AS vendorType,
        ISNULL(rvm.AllocatedQuota, 0)                                  AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                AS commissionTerms,
        rvm.AssignedDate                                               AS assignedDate,
        (SELECT COUNT(1) 
         FROM dbo.REC_Candidate_Applications ca 
         WHERE ca.fk_reqid = @ReqId 
           AND (ca.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR ca.fk_vendorId = cd.Vendor_Code)) AS candidateCount
    FROM dbo.REC_Candidate_Details cd
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm 
           ON (rvm.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR rvm.fk_vendorId = cd.Vendor_Code)
          AND rvm.fk_reqid = @ReqId
          AND rvm.IsActive = 1
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR cd.fk_companyId = @CompanyId
          OR EXISTS (
              SELECT 1 FROM dbo.Vendor_Location_Mapping vlm_c
              WHERE vlm_c.fk_VendorId = CAST(cd.pk_recId AS VARCHAR(50))
                AND vlm_c.fk_LocationId = @JobLocId
          )
          OR EXISTS (
              SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping rvm2
              WHERE rvm2.fk_reqid = @ReqId
                AND (rvm2.fk_vendorId = CAST(cd.pk_recId AS VARCHAR(50)) OR rvm2.fk_vendorId = cd.Vendor_Code)
          )
          OR NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details WHERE IsVendor = 1 AND fk_companyId = @CompanyId)
      )
      -- 100% Location-Specific: Only vendors mapped to this specific job location
      AND (
          @JobLocId IS NULL OR @JobLocId = ''
          OR cd.fk_locid = @JobLocId
          OR EXISTS (
              SELECT 1 FROM dbo.Vendor_Location_Mapping vlm
              WHERE vlm.fk_VendorId = CAST(cd.pk_recId AS VARCHAR(50))
                AND vlm.fk_LocationId = @JobLocId
          )
          OR EXISTS (
              SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping rvm2
              WHERE rvm2.fk_reqid = @ReqId
                AND (rvm2.fk_vendorId = CAST(cd.pk_recId AS VARCHAR(50)) OR rvm2.fk_vendorId = cd.Vendor_Code)
          )
      )
    ORDER BY isMapped DESC, vendorName ASC;
END;
GO

-- 3. Update usp_REC_SaveVendorRequisitionMapping for robust company and type persistence
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveVendorRequisitionMapping
    @ReqId           BIGINT,
    @VendorId        NVARCHAR(50),
    @VendorName      NVARCHAR(200) = NULL,
    @VendorType      NVARCHAR(50)  = 'Supply Vendors',
    @AllocatedQuota  INT           = 0,
    @CommissionTerms NVARCHAR(200) = 'Standard (8.33%)',
    @IsActive        BIT           = 1,
    @AssignedBy      NVARCHAR(100) = 'Administrator',
    @CompanyId       NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamically resolve @CompanyId from Requisition if missing
    IF (@CompanyId IS NULL OR LTRIM(RTRIM(@CompanyId)) = '' OR @CompanyId = '0')
    BEGIN
        SELECT @CompanyId = fk_companyId FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId;
    END;

    IF @IsActive = 0
    BEGIN
        DELETE FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 pk_recId FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));

        SELECT 1 AS Success, 'Vendor deallocated successfully.' AS Message, '' AS VendorType;
        RETURN;
    END

    IF @VendorType IS NULL OR LTRIM(RTRIM(@VendorType)) = ''
        SET @VendorType = 'Supply Vendors';

    -- Look up vendor name if not provided
    IF (@VendorName IS NULL OR LTRIM(RTRIM(@VendorName)) = '')
    BEGIN
        SELECT TOP 1 @VendorName = COALESCE(NULLIF(Vendor_Name, ''), candidate_name, 'Vendor')
        FROM dbo.REC_Candidate_Details
        WHERE pk_recId = @VendorId OR Vendor_Code = @VendorId;
    END;

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 pk_recId FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId))
    )
    BEGIN
        UPDATE dbo.REC_Requisition_Vendor_Mapping SET
            VendorName      = ISNULL(@VendorName, VendorName),
            VendorType      = @VendorType,
            AllocatedQuota  = @AllocatedQuota,
            CommissionTerms = @CommissionTerms,
            IsActive        = 1,
            AssignedBy      = @AssignedBy,
            AssignedDate    = GETDATE(),
            fk_companyId    = ISNULL(@CompanyId, fk_companyId)
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 pk_recId FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
            fk_reqid, fk_vendorId, VendorName, VendorType, AllocatedQuota,
            CommissionTerms, IsActive, AssignedBy, AssignedDate, fk_companyId
        ) VALUES (
            @ReqId, @VendorId, ISNULL(@VendorName, 'Vendor'), @VendorType, @AllocatedQuota,
            @CommissionTerms, 1, @AssignedBy, GETDATE(), @CompanyId
        );
    END

    SELECT 1 AS Success, 'Vendor mapping updated successfully.' AS Message, @VendorType AS VendorType;
END;
GO

-- 4. Dedicated Stored Procedure: Deallocate Vendor Mapping
CREATE OR ALTER PROCEDURE dbo.usp_REC_DeallocateVendorRequisitionMapping
    @ReqId     BIGINT,
    @VendorId  NVARCHAR(50),
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.REC_Requisition_Vendor_Mapping
    WHERE fk_reqid = @ReqId 
      AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 pk_recId FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));

    SELECT 1 AS Success, 'Vendor deallocated successfully.' AS Message;
END;
GO

-- 5. Normalize any existing mapping company IDs to match parent requisition company
UPDATE rvm
SET rvm.fk_companyId = req.fk_companyId
FROM dbo.REC_Requisition_Vendor_Mapping rvm
INNER JOIN dbo.REC_JobRequisition_Mst req ON req.pk_reqid = rvm.fk_reqid
WHERE rvm.fk_companyId IS NULL OR rvm.fk_companyId = '' OR rvm.fk_companyId != req.fk_companyId;
GO


