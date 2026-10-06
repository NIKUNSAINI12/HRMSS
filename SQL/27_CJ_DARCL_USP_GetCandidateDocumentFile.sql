-- ============================================================================
-- SCRIPT: 27_CJ_DARCL_USP_GetCandidateDocumentFile.sql
-- DESCRIPTION: Stored Procedure to fetch a single candidate document file record
--              by DocId or (AppId + DocTypeCode), eliminating inline SQL in controllers.
-- ============================================================================

USE [HRBook_22]
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidateDocumentFile
    @DocId        BIGINT        = NULL,
    @AppId        BIGINT        = NULL,
    @DocTypeCode  NVARCHAR(50)  = NULL,
    @CompanyId    NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @DocId IS NOT NULL AND @DocId > 0
    BEGIN
        SELECT TOP 1 
            pk_docId   AS docId, 
            fk_appId   AS appId, 
            DocTypeCode, 
            DocTypeName, 
            FileName, 
            FilePath, 
            FileType
        FROM dbo.REC_Candidate_Documents WITH (NOLOCK)
        WHERE pk_docId = @DocId
          AND (@CompanyId IS NULL OR @CompanyId = '' OR CompanyId = @CompanyId OR fk_companyId = @CompanyId);
    END
    ELSE IF @AppId IS NOT NULL AND @DocTypeCode IS NOT NULL AND @DocTypeCode <> ''
    BEGIN
        SELECT TOP 1 
            pk_docId   AS docId, 
            fk_appId   AS appId, 
            DocTypeCode, 
            DocTypeName, 
            FileName, 
            FilePath, 
            FileType
        FROM dbo.REC_Candidate_Documents WITH (NOLOCK)
        WHERE fk_appId = @AppId 
          AND DocTypeCode = @DocTypeCode
          AND (@CompanyId IS NULL OR @CompanyId = '' OR CompanyId = @CompanyId OR fk_companyId = @CompanyId);
    END
END
GO

PRINT 'dbo.usp_REC_GetCandidateDocumentFile created successfully.';
GO
