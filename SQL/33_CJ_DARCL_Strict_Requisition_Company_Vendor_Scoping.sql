-- =========================================================================================
-- Script Name: 33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql
-- Description:
--   Enforces that vendor allocation for an approved job requisition strictly loads ONLY
--   those vendors who are assigned to THAT specific requisition's company.
--   Prevents session/token company overrides from causing cross-company vendor mismatches.
-- =========================================================================================

USE [HRBook_22];
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Update dbo.usp_REC_GetVendorsForRequisitionMapping
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsForRequisitionMapping
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL,
    @VendorType  NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Determine Job Location and Company for this requisition
    DECLARE @JobLocId VARCHAR(50);
    DECLARE @ReqCompanyId VARCHAR(50);

    SELECT 
        @JobLocId = fk_locid, 
        @ReqCompanyId = COALESCE(NULLIF(fk_companyId, ''), NULLIF(CompanyId, ''))
    FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
    WHERE pk_reqid = @ReqId;

    -- The requisition's company is the authoritative tenant boundary for vendor allocation.
    -- If the requisition has a company assigned, vendors must belong to THAT company.
    IF (@ReqCompanyId IS NOT NULL AND LTRIM(RTRIM(@ReqCompanyId)) <> '' AND @ReqCompanyId <> '0')
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END;

    -- 2. Return ONLY vendors strictly assigned to @CompanyId
    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS mobile,
        ISNULL(cd.email, '')                                           AS email,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, '')   AS contactPerson,
        CASE WHEN rvm.pk_mapId IS NOT NULL AND rvm.IsActive = 1 THEN 1 ELSE 0 END AS isMapped,
        COALESCE(rvm.VendorType, @VendorType, 'Supply Vendors')        AS vendorType,
        ISNULL(rvm.AllocatedQuota, 0)                                  AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                AS commissionTerms,
        rvm.AssignedDate                                               AS assignedDate,
        (
            SELECT COUNT(1) 
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = @ReqId 
              AND (ca.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR ca.fk_vendorId = cd.Vendor_Code)
        ) AS candidateCount
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
           ON (rvm.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR rvm.fk_vendorId = cd.Vendor_Code)
          AND rvm.fk_reqid = @ReqId
          AND rvm.IsActive = 1
    WHERE cd.IsVendor = 1
      -- MANDATORY 100% COMPANY SCOPING: Must belong to the requisition's company
      AND (
          cd.fk_companyId = @CompanyId 
          OR cd.CompanyId = @CompanyId
      )
    ORDER BY isMapped DESC, vendorName ASC;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Update dbo.usp_REC_SaveVendorRequisitionMapping
-- ─────────────────────────────────────────────────────────────────────────────
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

    -- Authoritative Requisition Company resolution
    DECLARE @ReqCompanyId VARCHAR(50);
    SELECT @ReqCompanyId = COALESCE(NULLIF(fk_companyId, ''), NULLIF(CompanyId, '')) 
    FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK) 
    WHERE pk_reqid = @ReqId;

    IF (@ReqCompanyId IS NOT NULL AND LTRIM(RTRIM(@ReqCompanyId)) <> '' AND @ReqCompanyId <> '0')
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END;

    IF @IsActive = 0
    BEGIN
        DELETE FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));

        SELECT 1 AS Success, 'Vendor deallocated successfully.' AS Message, '' AS VendorType;
        RETURN;
    END;

    IF @VendorType IS NULL OR LTRIM(RTRIM(@VendorType)) = ''
        SET @VendorType = 'Supply Vendors';

    -- Look up vendor name if not provided
    IF (@VendorName IS NULL OR LTRIM(RTRIM(@VendorName)) = '')
    BEGIN
        SELECT TOP 1 @VendorName = COALESCE(NULLIF(Vendor_Name, ''), candidate_name, 'Vendor')
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId OR Vendor_Code = @VendorId;
    END;

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId))
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
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));
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
    END;

    SELECT 1 AS Success, 'Vendor mapping updated successfully.' AS Message, @VendorType AS VendorType;
END;
GO
