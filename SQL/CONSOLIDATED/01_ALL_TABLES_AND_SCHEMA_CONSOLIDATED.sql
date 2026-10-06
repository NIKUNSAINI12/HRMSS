-- ==========================================================================================
-- CJ DARCL RECRUITMENT & ONBOARDING LIFECYCLE (STEPS 1 - 16)
-- CONSOLIDATED MASTER TABLES, SCHEMA ALTERATIONS & INDEXES
-- Idempotent script: Safe to run multiple times on any SQL Server database
-- ==========================================================================================

USE [HRMS]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ------------------------------------------------------------------------------------------
-- 1. LOCATION_MST: Add Manpower & Buffer Columns
-- ------------------------------------------------------------------------------------------
IF COL_LENGTH('dbo.LOCATION_MST', 'BudgetedManpower') IS NULL
BEGIN
    ALTER TABLE dbo.LOCATION_MST ADD BudgetedManpower INT NULL CONSTRAINT DF_LOCATION_MST_BudgetedManpower DEFAULT 0;
END
GO
IF COL_LENGTH('dbo.LOCATION_MST', 'BufferManpower') IS NULL
BEGIN
    ALTER TABLE dbo.LOCATION_MST ADD BufferManpower INT NULL CONSTRAINT DF_LOCATION_MST_BufferManpower DEFAULT 0;
END
GO
IF COL_LENGTH('dbo.LOCATION_MST', 'BufferRemarks') IS NULL
BEGIN
    ALTER TABLE dbo.LOCATION_MST ADD BufferRemarks NVARCHAR(500) NULL;
END
GO

-- ------------------------------------------------------------------------------------------
-- 2. REC_JOBREQUISITION_MST: Add All Wizard, Workflow & Approval Columns
-- ------------------------------------------------------------------------------------------
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'CompanyId') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD CompanyId NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'fk_companyId') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD fk_companyId NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'WorkplaceType') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD WorkplaceType NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'EmploymentType') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD EmploymentType NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'Department') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD Department NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'MinExperience') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD MinExperience DECIMAL(4,1) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'MaxExperience') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD MaxExperience DECIMAL(4,1) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'MinSalary') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD MinSalary DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'MaxSalary') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD MaxSalary DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'Currency') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD Currency NVARCHAR(10) NULL CONSTRAINT DF_REC_JOBREQUISITION_MST_Curr DEFAULT 'INR';
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'IsSalaryNegotiable') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD IsSalaryNegotiable BIT NULL CONSTRAINT DF_REC_JOBREQUISITION_MST_Neg DEFAULT 1;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'Skills') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD Skills NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'JobDescription') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD JobDescription NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'RolesAndResponsibilities') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD RolesAndResponsibilities NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'RequirementsAndQualifications') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD RequirementsAndQualifications NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'TargetHiringDate') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD TargetHiringDate DATETIME NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'HiringManagerId') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD HiringManagerId NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'RecruiterId') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD RecruiterId NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'ApproverId') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD ApproverId NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'ApprovalStatus') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD ApprovalStatus NVARCHAR(50) NULL CONSTRAINT DF_REC_JOBREQUISITION_MST_Appr DEFAULT 'Pending';
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'ApprovalLevel') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD ApprovalLevel INT NULL CONSTRAINT DF_REC_JOBREQUISITION_MST_Lvl DEFAULT 1;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'HiredCount') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD HiredCount INT NULL CONSTRAINT DF_REC_JOBREQUISITION_MST_Hired DEFAULT 0;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'FilledDate') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD FilledDate DATETIME NULL;
GO
IF COL_LENGTH('dbo.REC_JOBREQUISITION_MST', 'RejectionRemarks') IS NULL
    ALTER TABLE dbo.REC_JOBREQUISITION_MST ADD RejectionRemarks NVARCHAR(MAX) NULL;
GO

-- ------------------------------------------------------------------------------------------
-- 3. REC_APPROVALLEVEL_CONFIG: Multi-tier Approval Config Table
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_APPROVALLEVEL_CONFIG')
BEGIN
    CREATE TABLE dbo.REC_APPROVALLEVEL_CONFIG (
        ConfigId INT IDENTITY(1,1) PRIMARY KEY,
        CompanyId NVARCHAR(50) NOT NULL,
        LevelNumber INT NOT NULL,
        LevelName NVARCHAR(100) NOT NULL,
        ApproverRole NVARCHAR(100) NOT NULL,
        ApproverUserId NVARCHAR(50) NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

-- ------------------------------------------------------------------------------------------
-- 4. REC_PIPELINE_STAGE_CONFIG: 16-Step Pipeline Visual Board Config
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_PIPELINE_STAGE_CONFIG')
BEGIN
    CREATE TABLE dbo.REC_PIPELINE_STAGE_CONFIG (
        StageId INT IDENTITY(1,1) PRIMARY KEY,
        CompanyId NVARCHAR(50) NOT NULL,
        StageKey NVARCHAR(100) NOT NULL,
        StageName NVARCHAR(150) NOT NULL,
        StageColor NVARCHAR(20) NOT NULL DEFAULT '#3080e8',
        StageOrder INT NOT NULL DEFAULT 1,
        IsActive BIT NOT NULL DEFAULT 1,
        IsSystemStage BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

-- ------------------------------------------------------------------------------------------
-- 5. REC_REQUISITION_VENDOR_MAPPING: External Vendor Allocations
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_REQUISITION_VENDOR_MAPPING')
BEGIN
    CREATE TABLE dbo.REC_REQUISITION_VENDOR_MAPPING (
        MappingId INT IDENTITY(1,1) PRIMARY KEY,
        CompanyId NVARCHAR(50) NOT NULL,
        ReqId NVARCHAR(50) NOT NULL,
        VendorId NVARCHAR(50) NOT NULL,
        VendorType NVARCHAR(50) NULL DEFAULT 'EXTERNAL',
        AllocatedCount INT NOT NULL DEFAULT 0,
        AssignedDate DATETIME NOT NULL DEFAULT GETDATE(),
        IsActive BIT NOT NULL DEFAULT 1
    );
END
GO

-- ------------------------------------------------------------------------------------------
-- 6. REC_CANDIDATE_APPLICATIONS: Primary Candidate Dossier & Application Records
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_CANDIDATE_APPLICATIONS')
BEGIN
    CREATE TABLE dbo.REC_CANDIDATE_APPLICATIONS (
        AppId INT IDENTITY(1,1) PRIMARY KEY,
        CandidateCode NVARCHAR(50) NULL,
        ReqId NVARCHAR(50) NULL,
        CompanyId NVARCHAR(50) NOT NULL,
        FullName NVARCHAR(200) NOT NULL,
        Email NVARCHAR(150) NULL,
        MobileNo NVARCHAR(20) NOT NULL,
        AadhaarNo NVARCHAR(20) NULL,
        CurrentStage NVARCHAR(100) NOT NULL DEFAULT 'SOURCED',
        CandidateSource NVARCHAR(50) NOT NULL DEFAULT 'INTERNAL',
        VendorId NVARCHAR(50) NULL,
        IsHold BIT NOT NULL DEFAULT 0,
        IsRejected BIT NOT NULL DEFAULT 0,
        RejectionReason NVARCHAR(500) NULL,
        RejectionDate DATETIME NULL,
        IsHired BIT NOT NULL DEFAULT 0,
        HiredDate DATETIME NULL,
        DocumentsVerified BIT NOT NULL DEFAULT 0,
        DocumentsVerificationDate DATETIME NULL,
        DocumentsVerifiedBy NVARCHAR(50) NULL,
        CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
        CreatedBy NVARCHAR(50) NULL
    );
END
GO
-- Add missing columns if table already existed prior to CJ DARCL additions
IF COL_LENGTH('dbo.REC_CANDIDATE_APPLICATIONS', 'DocumentsVerified') IS NULL
    ALTER TABLE dbo.REC_CANDIDATE_APPLICATIONS ADD DocumentsVerified BIT NOT NULL DEFAULT 0;
GO
IF COL_LENGTH('dbo.REC_CANDIDATE_APPLICATIONS', 'DocumentsVerificationDate') IS NULL
    ALTER TABLE dbo.REC_CANDIDATE_APPLICATIONS ADD DocumentsVerificationDate DATETIME NULL;
GO
IF COL_LENGTH('dbo.REC_CANDIDATE_APPLICATIONS', 'DocumentsVerifiedBy') IS NULL
    ALTER TABLE dbo.REC_CANDIDATE_APPLICATIONS ADD DocumentsVerifiedBy NVARCHAR(50) NULL;
GO

-- ------------------------------------------------------------------------------------------
-- 7. REC_CANDIDATE_DOCUMENTS: Document Checklist, Review & Verification
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_CANDIDATE_DOCUMENTS')
BEGIN
    CREATE TABLE dbo.REC_CANDIDATE_DOCUMENTS (
        DocId INT IDENTITY(1,1) PRIMARY KEY,
        AppId INT NOT NULL,
        CompanyId NVARCHAR(50) NOT NULL,
        DocumentType NVARCHAR(100) NOT NULL,
        FileName NVARCHAR(300) NULL,
        FilePath NVARCHAR(500) NULL,
        IsUploaded BIT NOT NULL DEFAULT 0,
        UploadedDate DATETIME NULL,
        IsVerified BIT NOT NULL DEFAULT 0,
        VerificationStatus NVARCHAR(50) NOT NULL DEFAULT 'PENDING',
        Remarks NVARCHAR(500) NULL,
        VerifiedBy NVARCHAR(50) NULL,
        VerifiedDate DATETIME NULL
    );
END
GO

-- ------------------------------------------------------------------------------------------
-- 8. REC_CANDIDATE_LIFECYCLE_AUDIT: Comprehensive User & Transition Audit Trail
-- ------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'REC_CANDIDATE_LIFECYCLE_AUDIT')
BEGIN
    CREATE TABLE dbo.REC_CANDIDATE_LIFECYCLE_AUDIT (
        AuditId INT IDENTITY(1,1) PRIMARY KEY,
        AppId INT NOT NULL,
        CompanyId NVARCHAR(50) NOT NULL,
        PreviousStage NVARCHAR(100) NULL,
        NewStage NVARCHAR(100) NOT NULL,
        ActionTaken NVARCHAR(100) NOT NULL,
        Comments NVARCHAR(MAX) NULL,
        ActionBy NVARCHAR(50) NOT NULL,
        ActionDate DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

-- ------------------------------------------------------------------------------------------
-- 9. UM_USERS_MST: Add Vendor Portal Links
-- ------------------------------------------------------------------------------------------
IF COL_LENGTH('dbo.UM_USERS_MST', 'IsVendor') IS NULL
    ALTER TABLE dbo.UM_USERS_MST ADD IsVendor BIT NULL CONSTRAINT DF_UM_USERS_MST_IsVendor DEFAULT 0;
GO
IF COL_LENGTH('dbo.UM_USERS_MST', 'VendorId') IS NULL
    ALTER TABLE dbo.UM_USERS_MST ADD VendorId NVARCHAR(50) NULL;
GO

-- ------------------------------------------------------------------------------------------
-- 10. UM_USERPAGERIGHTS: Add L1, L2, L3 Permission Flags
-- ------------------------------------------------------------------------------------------
IF COL_LENGTH('dbo.UM_USERPAGERIGHTS', 'IsL1') IS NULL
    ALTER TABLE dbo.UM_USERPAGERIGHTS ADD IsL1 BIT NULL CONSTRAINT DF_UM_USERPAGERIGHTS_IsL1 DEFAULT 0;
GO
IF COL_LENGTH('dbo.UM_USERPAGERIGHTS', 'IsL2') IS NULL
    ALTER TABLE dbo.UM_USERPAGERIGHTS ADD IsL2 BIT NULL CONSTRAINT DF_UM_USERPAGERIGHTS_IsL2 DEFAULT 0;
GO
IF COL_LENGTH('dbo.UM_USERPAGERIGHTS', 'IsL3') IS NULL
    ALTER TABLE dbo.UM_USERPAGERIGHTS ADD IsL3 BIT NULL CONSTRAINT DF_UM_USERPAGERIGHTS_IsL3 DEFAULT 0;
GO

PRINT '======================================================================';
PRINT 'All CJ DARCL Tables and Schema Alterations completed successfully!';
PRINT '======================================================================';
