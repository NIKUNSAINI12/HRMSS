-- =============================================================================
-- Migration 11: Seed Recruitment Staffing Vendors (100% Company-Specific)
-- Database : HRBook_22
-- Standard : Multi-tenant company scoped
-- =============================================================================

USE HRBook_22;
GO

DECLARE @CompanyCursor CURSOR;
DECLARE @CompId VARCHAR(50);

SET @CompanyCursor = CURSOR FOR
    SELECT DISTINCT fk_companyId 
    FROM dbo.Location_Mst 
    WHERE fk_companyId IS NOT NULL;

OPEN @CompanyCursor;
FETCH NEXT FROM @CompanyCursor INTO @CompId;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Seed Vendor 1: ABC Logistics Manpower Services
    IF NOT EXISTS (SELECT 1 FROM dbo.Inv_Vendor_Mst WHERE name = 'ABC Logistics Manpower Services' AND fk_companyId = @CompId)
    BEGIN
        INSERT INTO dbo.Inv_Vendor_Mst (
            name, VenCode, contactPerson, mobile, emailId, address, Active, fk_companyId, createDate
        ) VALUES (
            'ABC Logistics Manpower Services', 'V001', 'Rajesh Sharma', '9876543210', 'vendor1@abcmanpower.com', 'Transport Nagar Hub', 1, @CompId, GETDATE()
        );
    END

    -- Seed Vendor 2: QuickHire Staffing Solutions
    IF NOT EXISTS (SELECT 1 FROM dbo.Inv_Vendor_Mst WHERE name = 'QuickHire Staffing Solutions' AND fk_companyId = @CompId)
    BEGIN
        INSERT INTO dbo.Inv_Vendor_Mst (
            name, VenCode, contactPerson, mobile, emailId, address, Active, fk_companyId, createDate
        ) VALUES (
            'QuickHire Staffing Solutions', 'V002', 'Vikram Patel', '9811223344', 'contact@quickhire.co.in', 'Expressway Logistic Park', 1, @CompId, GETDATE()
        );
    END

    -- Seed Vendor 3: Elite Fleet & Warehouse Workforce
    IF NOT EXISTS (SELECT 1 FROM dbo.Inv_Vendor_Mst WHERE name = 'Elite Fleet & Warehouse Workforce' AND fk_companyId = @CompId)
    BEGIN
        INSERT INTO dbo.Inv_Vendor_Mst (
            name, VenCode, contactPerson, mobile, emailId, address, Active, fk_companyId, createDate
        ) VALUES (
            'Elite Fleet & Warehouse Workforce', 'V003', 'Sunil Yadav', '9899887766', 'ops@eliteworkforce.com', 'Sector 18 Industrial Zone', 1, @CompId, GETDATE()
        );
    END

    FETCH NEXT FROM @CompanyCursor INTO @CompId;
END

CLOSE @CompanyCursor;
DEALLOCATE @CompanyCursor;
GO

PRINT 'Recruitment staffing vendors seeded company-specifically across all companies.';
