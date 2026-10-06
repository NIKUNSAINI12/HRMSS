-- ============================================================================
-- CJ DARCL Recruitment Architecture: Step 2 - Manpower Requisition Schema
-- Table: REC_JobRequisition_Mst
-- Purpose: Add ServiceType, SkillCategory, DiversityHiring, and Replacement fields
-- ============================================================================

USE [HRBook_22];
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') 
      AND name = 'ServiceType'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD ServiceType VARCHAR(100) NULL;
    PRINT 'Added ServiceType column to REC_JobRequisition_Mst';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') 
      AND name = 'SkillCategory'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD SkillCategory VARCHAR(100) NULL;
    PRINT 'Added SkillCategory column to REC_JobRequisition_Mst';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') 
      AND name = 'IsDiversityHiring'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD IsDiversityHiring BIT NOT NULL CONSTRAINT DF_REC_JobRequisition_IsDiversityHiring DEFAULT 0;
    PRINT 'Added IsDiversityHiring column to REC_JobRequisition_Mst';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') 
      AND name = 'DiversityCategory'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD DiversityCategory VARCHAR(100) NULL;
    PRINT 'Added DiversityCategory column to REC_JobRequisition_Mst';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') 
      AND name = 'ReplacedEmpName'
)
BEGIN
    ALTER TABLE dbo.REC_JobRequisition_Mst
    ADD ReplacedEmpName VARCHAR(150) NULL;
    PRINT 'Added ReplacedEmpName column to REC_JobRequisition_Mst';
END
GO
