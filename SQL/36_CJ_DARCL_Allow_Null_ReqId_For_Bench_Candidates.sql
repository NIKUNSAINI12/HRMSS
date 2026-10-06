-- ==============================================================================
-- 36_CJ_DARCL_Allow_Null_ReqId_For_Bench_Candidates.sql
-- Allows fk_reqid to be NULL in dbo.REC_Candidate_Applications so that vendors
-- can pre-register candidate profiles beforehand into the Talent Bench without
-- needing an active/assigned requisition.
-- ==============================================================================

USE [HRBook_22];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'STEP 1: Altering fk_reqid in dbo.REC_Candidate_Applications to allow NULL...';
GO

-- Drop default constraint if any exists on fk_reqid
DECLARE @ConstraintName NVARCHAR(200);
SELECT @ConstraintName = d.name
FROM sys.default_constraints d
JOIN sys.columns c ON c.column_id = d.parent_column_id AND c.object_id = d.parent_object_id
WHERE d.parent_object_id = OBJECT_ID('dbo.REC_Candidate_Applications')
  AND c.name = 'fk_reqid';

IF @ConstraintName IS NOT NULL
BEGIN
    EXEC('ALTER TABLE dbo.REC_Candidate_Applications DROP CONSTRAINT ' + @ConstraintName);
    PRINT 'Dropped default constraint ' + @ConstraintName + ' on fk_reqid.';
END;

ALTER TABLE dbo.REC_Candidate_Applications ALTER COLUMN fk_reqid BIGINT NULL;
PRINT 'dbo.REC_Candidate_Applications.fk_reqid altered to BIGINT NULL successfully.';
GO
