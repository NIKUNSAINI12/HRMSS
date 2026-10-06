-- =============================================================================
-- Script  : 42_CJ_DARCL_L1L2L3_Rights_Schema.sql
-- Purpose : Add L1/L2/L3 approval access, Raise Requisition right, and
--           Edit Manpower right as BIT columns to dbo.UM_UserPageRights.
--           Locations are already in dbo.UM_UserModuleDetails — no new table.
-- DB      : HRBook_22
-- Date    : 2026-10-01
-- =============================================================================

USE HRBook_22;
GO

ALTER TABLE dbo.UM_UserPageRights
ADD
    L1_Access           BIT NOT NULL DEFAULT 0,
    L2_Access           BIT NOT NULL DEFAULT 0,
    L3_Access           BIT NOT NULL DEFAULT 0,
    CanRaiseRequisition BIT NOT NULL DEFAULT 0,
    CanEditManpower     BIT NOT NULL DEFAULT 0;
GO
