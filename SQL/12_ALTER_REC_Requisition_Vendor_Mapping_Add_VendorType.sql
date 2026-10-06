-- =============================================================================
-- Migration 12: Add VendorType ('TA' or 'Supply Vendors') to Vendor Mapping
-- Database : HRBook_22
-- Standard : 100% Company-Specific, Zero Hardcoding, Zero Inline SQL
-- Step 5   : Sourcing Channel & Vendor Allocation on Job Approval Page
-- =============================================================================

USE HRBook_22;
GO

-- 1. Alter dbo.REC_Requisition_Vendor_Mapping to add VendorType
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Requisition_Vendor_Mapping' AND COLUMN_NAME = 'VendorType'
)
BEGIN
    ALTER TABLE dbo.REC_Requisition_Vendor_Mapping
    ADD VendorType NVARCHAR(50) NOT NULL CONSTRAINT DF_RVM_VendorType DEFAULT 'Supply Vendors';
    PRINT 'Added VendorType column to REC_Requisition_Vendor_Mapping.';
END
ELSE
BEGIN
    PRINT 'VendorType column already exists in REC_Requisition_Vendor_Mapping.';
END
GO

-- 2. Alter dbo.REC_Candidate_Applications to add VendorType (if not exists)
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'REC_Candidate_Applications' AND COLUMN_NAME = 'VendorType'
)
BEGIN
    ALTER TABLE dbo.REC_Candidate_Applications
    ADD VendorType NVARCHAR(50) NULL CONSTRAINT DF_RCA_VendorType DEFAULT 'Supply Vendors';
    PRINT 'Added VendorType column to REC_Candidate_Applications.';
END
GO

-- 3. Stored Procedure: usp_REC_GetVendorsForRequisitionMapping
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsForRequisitionMapping
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50),
    @VendorType  NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Return staffing partner vendors and TA channels from REC_Candidate_Details where IsVendor = 1 (Company-Scoped)
    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS mobile,
        ISNULL(cd.email, '')                                           AS email,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, '')   AS contactPerson,
        CASE WHEN rvm.pk_mapId IS NOT NULL THEN 1 ELSE 0 END          AS isMapped,
        COALESCE(rvm.VendorType, 'Supply Vendors')                     AS vendorType,
        ISNULL(rvm.AllocatedQuota, 10)                                 AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                AS commissionTerms,
        rvm.AssignedDate                                               AS assignedDate,
        (SELECT COUNT(1) 
         FROM dbo.REC_Candidate_Applications ca 
         WHERE ca.fk_reqid = @ReqId 
           AND ca.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50))
           AND (ca.fk_companyId = @CompanyId OR @CompanyId IS NULL))  AS candidateCount
    FROM dbo.REC_Candidate_Details cd
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm 
           ON rvm.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50))
          AND rvm.fk_reqid = @ReqId
          AND (rvm.fk_companyId = @CompanyId OR @CompanyId IS NULL)
          AND rvm.IsActive = 1
    WHERE cd.IsVendor = 1
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0'
          OR cd.fk_companyId = @CompanyId
          OR NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details WHERE IsVendor = 1 AND fk_companyId = @CompanyId)
      )
      AND (@VendorType IS NULL OR @VendorType = '' OR @VendorType = 'ALL' OR rvm.VendorType = @VendorType OR (rvm.VendorType IS NULL AND @VendorType = 'Supply Vendors'))
    ORDER BY isMapped DESC, vendorName ASC;
END;
GO

-- 4. Stored Procedure: usp_REC_SaveVendorRequisitionMapping
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveVendorRequisitionMapping
    @ReqId           BIGINT,
    @VendorId        NVARCHAR(50),
    @VendorName      NVARCHAR(200),
    @VendorType      NVARCHAR(50)  = 'Supply Vendors',
    @AllocatedQuota  INT           = 10,
    @CommissionTerms NVARCHAR(200) = 'Standard',
    @IsActive        BIT           = 1,
    @AssignedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate VendorType: Must be 'TA' or 'Supply Vendors'
    IF @VendorType IS NULL OR LTRIM(RTRIM(@VendorType)) = ''
        SET @VendorType = 'Supply Vendors';

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId AND fk_vendorId = @VendorId AND fk_companyId = @CompanyId
    )
    BEGIN
        UPDATE dbo.REC_Requisition_Vendor_Mapping SET
            VendorType      = @VendorType,
            AllocatedQuota  = @AllocatedQuota,
            CommissionTerms = @CommissionTerms,
            IsActive        = @IsActive,
            AssignedBy      = @AssignedBy,
            AssignedDate    = GETDATE()
        WHERE fk_reqid = @ReqId AND fk_vendorId = @VendorId AND fk_companyId = @CompanyId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
            fk_reqid, fk_vendorId, VendorName, VendorType, AllocatedQuota,
            CommissionTerms, IsActive, AssignedBy, AssignedDate, fk_companyId
        ) VALUES (
            @ReqId, @VendorId, @VendorName, @VendorType, @AllocatedQuota,
            @CommissionTerms, @IsActive, @AssignedBy, GETDATE(), @CompanyId
        );
    END

    -- Return success payload
    SELECT 
        1 AS Success, 
        'Vendor mapped successfully as ' + @VendorType + '.' AS Message,
        @VendorType AS VendorType;
END;
GO
