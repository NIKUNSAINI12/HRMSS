-- =========================================================================
-- SCRIPT: 20_CJ_DARCL_Candidate_Audit_Trail_Company_Scoping.sql
-- DESCRIPTION: Fix candidate lifecycle audit retrieval stored procedure
--              to ensure company scoping handles empty string, null, and matches
--              either fk_companyId or CompanyId without returning empty datasets.
-- =========================================================================

USE HRBook_22;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Updating dbo.usp_REC_GetCandidateLifecycleAudit...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidateLifecycleAudit
    @AppId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        pk_auditId     AS auditId,
        fk_appId       AS appId,
        ApplicationNo  AS applicationNo,
        ActionType     AS actionType,
        PreviousStage  AS previousStage,
        NewStage       AS newStage,
        ActionByName   AS actionByName,
        ActionRole     AS actionRole,
        Remarks        AS remarks,
        ActionDate     AS actionDate
    FROM dbo.REC_Candidate_Lifecycle_Audit
    WHERE fk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR fk_companyId = @CompanyId 
          OR CompanyId = @CompanyId
      )
    ORDER BY pk_auditId ASC;
END;
GO

PRINT 'dbo.usp_REC_GetCandidateLifecycleAudit updated successfully.';
GO
