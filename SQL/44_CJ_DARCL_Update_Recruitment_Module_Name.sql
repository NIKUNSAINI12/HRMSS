-- =============================================================================
-- Script  : 44_CJ_DARCL_Update_Recruitment_Module_Name.sql
-- Purpose : Update Module 5 name to clearly reflect ATS Talent Suite in
--           module dropdowns across the portal.
-- DB      : HRBook_22
-- Date    : 2026-10-01
-- =============================================================================

USE HRBook_22;
GO

UPDATE dbo.UM_Module_Mst
SET modulename = 'Recruitment Management (ATS Talent Suite)'
WHERE pk_moduleId = 5;
GO
