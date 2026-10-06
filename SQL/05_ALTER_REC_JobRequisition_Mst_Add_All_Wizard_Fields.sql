-- ============================================================================
-- CJ DARCL Recruitment Architecture: Step 2 - Manpower Requisition Full Schema
-- Table: REC_JobRequisition_Mst
-- Purpose: Add all remaining wizard fields to ensure 100% field persistence
-- ============================================================================

USE [HRBook_22];
GO

-- 1. Workplace & Employment Mode
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'WorkplaceType')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD WorkplaceType VARCHAR(50) NULL;
    PRINT 'Added WorkplaceType column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'EmploymentType')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD EmploymentType VARCHAR(50) NULL;
    PRINT 'Added EmploymentType column';
END
GO

-- 2. Priority, Currency, Target Dates
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'Priority')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD Priority VARCHAR(30) NULL CONSTRAINT DF_REC_Req_Priority DEFAULT 'Medium';
    PRINT 'Added Priority column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'Currency')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD Currency VARCHAR(10) NULL CONSTRAINT DF_REC_Req_Currency DEFAULT 'INR';
    PRINT 'Added Currency column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'TargetStartDate')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD TargetStartDate VARCHAR(50) NULL;
    PRINT 'Added TargetStartDate column';
END
GO

-- 3. Skills, Education & Industry
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'EducationLevel')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD EducationLevel VARCHAR(100) NULL;
    PRINT 'Added EducationLevel column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'PrimarySkills')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD PrimarySkills NVARCHAR(MAX) NULL;
    PRINT 'Added PrimarySkills column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'SecondarySkills')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD SecondarySkills NVARCHAR(MAX) NULL;
    PRINT 'Added SecondarySkills column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'NoticePeriodMaxDays')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD NoticePeriodMaxDays INT NULL;
    PRINT 'Added NoticePeriodMaxDays column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'Industry')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD Industry VARCHAR(150) NULL CONSTRAINT DF_REC_Req_Industry DEFAULT 'Logistics & Supply Chain';
    PRINT 'Added Industry column';
END
GO

-- 4. Text Descriptions (Max capacity)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'JobDescription')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD JobDescription NVARCHAR(MAX) NULL;
    PRINT 'Added JobDescription column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'Benefits')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD Benefits NVARCHAR(MAX) NULL;
    PRINT 'Added Benefits column';
END
GO

-- Expand existing columns if restricted to 255 chars
BEGIN TRY
    ALTER TABLE dbo.REC_JobRequisition_Mst ALTER COLUMN Roles_Responsibilities NVARCHAR(MAX) NULL;
    ALTER TABLE dbo.REC_JobRequisition_Mst ALTER COLUMN quali NVARCHAR(MAX) NULL;
    PRINT 'Expanded Roles_Responsibilities and quali to NVARCHAR(MAX)';
END TRY
BEGIN CATCH
    PRINT 'Could not alter Roles_Responsibilities/quali size (may have index/constraint)';
END CATCH
GO

-- 5. Hiring Stakeholders
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'HiringManager')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD HiringManager VARCHAR(150) NULL;
    PRINT 'Added HiringManager column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'LeadRecruiter')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD LeadRecruiter VARCHAR(150) NULL;
    PRINT 'Added LeadRecruiter column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'Interviewers')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD Interviewers NVARCHAR(MAX) NULL;
    PRINT 'Added Interviewers column';
END
GO

-- 6. Buffer Headcount Metrics & Submitter Audit
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'IsBufferUtilized')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD IsBufferUtilized BIT NOT NULL CONSTRAINT DF_REC_Req_IsBufferUtilized DEFAULT 0;
    PRINT 'Added IsBufferUtilized column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'BufferHeadsUtilized')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD BufferHeadsUtilized INT NOT NULL CONSTRAINT DF_REC_Req_BufferHeadsUtilized DEFAULT 0;
    PRINT 'Added BufferHeadsUtilized column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'SubmittedBy')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD SubmittedBy VARCHAR(150) NULL;
    PRINT 'Added SubmittedBy column';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'SubmittedById')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD SubmittedById VARCHAR(50) NULL;
    PRINT 'Added SubmittedById column';
END
GO

-- 7. Full Status String ('Pending Approval', 'Pending Buffer Approval', 'Draft', 'Active')
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'RequisitionStatus')
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD RequisitionStatus VARCHAR(50) NULL CONSTRAINT DF_REC_Req_RequisitionStatus DEFAULT 'Pending Approval';
    PRINT 'Added RequisitionStatus column';
END
GO
