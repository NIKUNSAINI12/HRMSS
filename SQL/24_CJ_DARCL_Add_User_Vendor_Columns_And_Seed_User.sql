-- =========================================================================================
-- Script Name: 24_CJ_DARCL_Add_User_Vendor_Columns_And_Seed_User.sql
-- Description: 
--   1. Adds 'isVendor' (BIT NULL) and 'fk_vendorId' (VARCHAR(50) NULL) columns to UM_Users_Mst
--   2. Seeds/Creates active user accounts for Vendor 'ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED'
--      - Vendor Code: V011
--      - Mobile: 8010436123
--      - REC_Candidate_Details ID: GU-39
--      - Password: '123456'
--      - isVendor: 1
--      - fk_vendorId: 'GU-39'
--      - Accounts created for both CJ Darcl (GU-8 / CJDarcl) and HRBook (GU-1 / HRBOOK)
--      - Supporting login via both Vendor Code ('V011') and Mobile ('8010436123')
--      - Populates UM_UserModuleDetails so the login pipeline validates locations & modules
-- =========================================================================================

USE [HRBook_22];
GO

-- 1. Add columns to UM_Users_Mst if not already present
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.UM_Users_Mst') AND name = 'isVendor')
BEGIN
    ALTER TABLE dbo.UM_Users_Mst ADD isVendor BIT NULL CONSTRAINT DF_UM_Users_Mst_isVendor DEFAULT (0);
    PRINT 'Added column isVendor to dbo.UM_Users_Mst';
END
ELSE
BEGIN
    PRINT 'Column isVendor already exists in dbo.UM_Users_Mst';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.UM_Users_Mst') AND name = 'fk_vendorId')
BEGIN
    ALTER TABLE dbo.UM_Users_Mst ADD fk_vendorId VARCHAR(50) NULL;
    PRINT 'Added column fk_vendorId to dbo.UM_Users_Mst';
END
ELSE
BEGIN
    PRINT 'Column fk_vendorId already exists in dbo.UM_Users_Mst';
END
GO

-- 2. Seed Vendor Users for ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED (V011 / GU-39)
DECLARE @vendorId VARCHAR(50) = 'GU-39';
DECLARE @vendorName VARCHAR(100) = 'ADVANCED GLOBAL ENTERPRISES PRIVATE LIMITED';
DECLARE @vendorCode VARCHAR(50) = 'V011';
DECLARE @vendorPhone VARCHAR(50) = '8010436123';
DECLARE @defaultPassword VARCHAR(50) = '123456';

-- Table variable of user configurations to ensure
DECLARE @UsersToCreate TABLE (
    LoginName VARCHAR(50),
    CompanyId VARCHAR(15),
    UserRole TINYINT,
    ReferenceAdminUser VARCHAR(15)
);

INSERT INTO @UsersToCreate (LoginName, CompanyId, UserRole, ReferenceAdminUser)
VALUES 
    (@vendorCode,  'GU-8', 2, 'GU-18'), -- CJDarcl login with V011
    (@vendorPhone, 'GU-8', 2, 'GU-18'), -- CJDarcl login with 8010436123
    (@vendorCode,  'GU-1', 1, 'GU-1'),  -- HRBOOK login with V011
    (@vendorPhone, 'GU-1', 1, 'GU-1');  -- HRBOOK login with 8010436123

DECLARE @curLogin VARCHAR(50), @curCompany VARCHAR(15), @curRole TINYINT, @curRefUser VARCHAR(15);
DECLARE @newUserId VARCHAR(15);
DECLARE @maxId INT;

DECLARE user_cursor CURSOR FOR 
SELECT LoginName, CompanyId, UserRole, ReferenceAdminUser FROM @UsersToCreate;

OPEN user_cursor;
FETCH NEXT FROM user_cursor INTO @curLogin, @curCompany, @curRole, @curRefUser;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Check if user already exists for this login and company
    IF NOT EXISTS (SELECT 1 FROM dbo.UM_Users_Mst WHERE loginname = @curLogin AND fk_companyId = @curCompany)
    BEGIN
        -- Calculate next GU- ID
        SELECT @maxId = ISNULL(MAX(CAST(CASE WHEN pk_userId LIKE 'GU-%' THEN SUBSTRING(pk_userId, 4, 10) ELSE pk_userId END AS INT)), 0) + 1 
        FROM dbo.UM_Users_Mst;
        
        SET @newUserId = 'GU-' + CAST(@maxId AS VARCHAR(10));

        INSERT INTO dbo.UM_Users_Mst (
            pk_userId,
            fk_roleId,
            fk_empId,
            loginname,
            password,
            active,
            name,
            remarks,
            fk_insUserID,
            fk_companyId,
            IsOTPRequired,
            isVendor,
            fk_vendorId
        )
        VALUES (
            @newUserId,
            @curRole,
            NULL,
            @curLogin,
            @defaultPassword,
            1,
            @vendorName,
            'Vendor Portal User - ' + @vendorName + ' (' + @curLogin + ')',
            'GU-1',
            @curCompany,
            0, -- No OTP friction for vendor portal
            1, -- isVendor = 1
            @vendorId -- fk_vendorId = 'GU-39'
        );

        PRINT 'Created User ' + @newUserId + ' with login ' + @curLogin + ' for company ' + @curCompany + ' (fk_vendorId: ' + @vendorId + ')';

        -- Clone Module and Location rights from reference admin user
        IF EXISTS (SELECT 1 FROM dbo.UM_UserModuleDetails WHERE fk_userId = @curRefUser)
        BEGIN
            INSERT INTO dbo.UM_UserModuleDetails (fk_userId, fk_locid, fk_moduleId)
            SELECT DISTINCT @newUserId, fk_locid, fk_moduleId 
            FROM dbo.UM_UserModuleDetails 
            WHERE fk_userId = @curRefUser;

            PRINT 'Mapped module & location rights to user ' + @newUserId + ' from ' + @curRefUser;
        END
    END
    ELSE
    BEGIN
        -- Update existing user to ensure vendor flags and vendorId are set
        UPDATE dbo.UM_Users_Mst
        SET isVendor = 1,
            fk_vendorId = @vendorId,
            name = @vendorName,
            password = @defaultPassword,
            active = 1,
            IsOTPRequired = 0
        WHERE loginname = @curLogin AND fk_companyId = @curCompany;

        PRINT 'Updated existing User for login ' + @curLogin + ' at company ' + @curCompany + ' with isVendor = 1 and fk_vendorId = ' + @vendorId;
    END

    FETCH NEXT FROM user_cursor INTO @curLogin, @curCompany, @curRole, @curRefUser;
END

CLOSE user_cursor;
DEALLOCATE user_cursor;
GO

-- 3. Match reference screenshot for existing user GU-4
UPDATE dbo.UM_Users_Mst
SET isVendor = 1, fk_vendorId = 'GU-4'
WHERE pk_userId = 'GU-4';
GO

-- 4. Verify Newly Created / Updated Users
SELECT 
    pk_userId,
    fk_roleId,
    loginname,
    password,
    active,
    name,
    fk_companyId,
    IsOTPRequired,
    isVendor,
    fk_vendorId
FROM dbo.UM_Users_Mst
WHERE isVendor = 1 OR fk_vendorId IS NOT NULL;
GO
