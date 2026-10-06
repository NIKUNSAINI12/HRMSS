-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture (Step 1 Master)
-- File: 01_ALTER_Location_Mst_Add_Manpower_Buffer.sql
-- Purpose: Add Location-Wise Manpower Headcount & Buffer columns to existing Location_Mst table
-- Created: 2026-09-22
-- ============================================================================

USE [HRBook_22];
GO

-- 1. Add BaseDemand if not exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Location_Mst' AND COLUMN_NAME = 'BaseDemand'
)
BEGIN
    ALTER TABLE [dbo].[Location_Mst]
    ADD [BaseDemand] INT NOT NULL CONSTRAINT DF_LocMst_BaseDemand DEFAULT 0;
    PRINT 'Added BaseDemand column to Location_Mst.';
END
GO

-- 2. Add BufferPercent if not exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Location_Mst' AND COLUMN_NAME = 'BufferPercent'
)
BEGIN
    ALTER TABLE [dbo].[Location_Mst]
    ADD [BufferPercent] DECIMAL(5,2) NOT NULL CONSTRAINT DF_LocMst_BufferPercent DEFAULT 0.00;
    PRINT 'Added BufferPercent column to Location_Mst.';
END
GO

-- 3. Add BufferHeads if not exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Location_Mst' AND COLUMN_NAME = 'BufferHeads'
)
BEGIN
    ALTER TABLE [dbo].[Location_Mst]
    ADD [BufferHeads] INT NOT NULL CONSTRAINT DF_LocMst_BufferHeads DEFAULT 0;
    PRINT 'Added BufferHeads column to Location_Mst.';
END
GO

-- 4. Add TargetCapacity if not exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'Location_Mst' AND COLUMN_NAME = 'TargetCapacity'
)
BEGIN
    ALTER TABLE [dbo].[Location_Mst]
    ADD [TargetCapacity] INT NOT NULL CONSTRAINT DF_LocMst_TargetCapacity DEFAULT 0;
    PRINT 'Added TargetCapacity column to Location_Mst.';
END
GO
