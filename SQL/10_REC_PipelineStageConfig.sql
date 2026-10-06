-- =============================================================================
-- FILE   : 10_REC_PipelineStageConfig.sql
-- MODULE : Recruitment → Candidate Pipeline
-- PURPOSE: Company-wise enable/disable of recruitment lifecycle stages.
--          Allows each company to control which pipeline stages are active
--          without touching global config or code.
-- RULES  : 100% CompanyId-scoped. Zero hardcoding.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Create Table REC_Pipeline_Stage_Config
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_NAME = 'REC_Pipeline_Stage_Config'
)
BEGIN
    CREATE TABLE dbo.REC_Pipeline_Stage_Config (
        pk_StageConfigId  BIGINT IDENTITY(1,1) PRIMARY KEY,
        fk_CompanyId      NVARCHAR(50)    NOT NULL,
        StageCode         NVARCHAR(50)    NOT NULL,   -- e.g. 'Applied', 'Interview_Scheduled'
        StageLabel        NVARCHAR(100)   NOT NULL,   -- Display label e.g. '1. Applied'
        StageIcon         NVARCHAR(50)    NOT NULL DEFAULT 'bi-circle',
        StageColor        NVARCHAR(20)    NOT NULL DEFAULT '#64748b',
        StageOrder        INT             NOT NULL DEFAULT 1,
        IsEnabled         BIT             NOT NULL DEFAULT 1,
        CreatedBy         NVARCHAR(150)   NULL,
        CreatedAt         DATETIME        NOT NULL DEFAULT GETDATE(),
        ModifiedBy        NVARCHAR(150)   NULL,
        ModifiedAt        DATETIME        NULL,

        -- Unique per company per stage code
        CONSTRAINT UQ_REC_PipelineStage_Company UNIQUE (fk_CompanyId, StageCode)
    );

    PRINT 'Created table: REC_Pipeline_Stage_Config';
END
ELSE
BEGIN
    PRINT 'Table already exists: REC_Pipeline_Stage_Config';
END
GO

-- -----------------------------------------------------------------------------
-- STEP 2: Seed default stages for all existing companies
--         (Inserts only if company+stageCode combo doesn't already exist)
-- -----------------------------------------------------------------------------
DECLARE @DefaultStages TABLE (
    StageCode   NVARCHAR(50),
    StageLabel  NVARCHAR(100),
    StageIcon   NVARCHAR(50),
    StageColor  NVARCHAR(20),
    StageOrder  INT
);

INSERT INTO @DefaultStages VALUES
('Applied',              '1. Applied',           'bi-inbox',             '#64748b', 1),
('Interview_Scheduled',  '2. Interview',          'bi-calendar-event',    '#0ea5e9', 2),
('Selected',             '3. Selected',           'bi-check-circle',      '#8b5cf6', 3),
('Docs_Submitted',       '4. Docs Review',        'bi-file-earmark-check','#f59e0b', 4),
('Offer_Issued',         '5. Offer Sent',         'bi-award',             '#10b981', 5),
('Hired',                '6. Hired & Onboarded',  'bi-person-check-fill', '#0051d5', 6);

-- Get all distinct companies that have any requisition activity
DECLARE @Companies TABLE (CompanyId NVARCHAR(50));
INSERT INTO @Companies
    SELECT DISTINCT fk_CompanyId FROM dbo.REC_JobRequisition_Mst WHERE fk_CompanyId IS NOT NULL;

-- Cross-join and insert missing configs
INSERT INTO dbo.REC_Pipeline_Stage_Config
    (fk_CompanyId, StageCode, StageLabel, StageIcon, StageColor, StageOrder, IsEnabled, CreatedBy)
SELECT
    c.CompanyId,
    s.StageCode,
    s.StageLabel,
    s.StageIcon,
    s.StageColor,
    s.StageOrder,
    1,  -- All enabled by default
    'SYSTEM_SEED'
FROM @Companies c
CROSS JOIN @DefaultStages s
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.REC_Pipeline_Stage_Config x
    WHERE x.fk_CompanyId = c.CompanyId AND x.StageCode = s.StageCode
);

PRINT 'Seeded default pipeline stages for existing companies.';
GO

-- -----------------------------------------------------------------------------
-- STEP 3: USP — Get Pipeline Stage Config for a Company
--         Returns all stages (enabled + disabled) ordered by StageOrder.
--         Frontend uses IsEnabled to drive the kanban columns.
--         If company has no rows, returns the global 6-stage defaults.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_REC_GetPipelineStageConfig', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_REC_GetPipelineStageConfig;
GO

CREATE PROCEDURE dbo.usp_REC_GetPipelineStageConfig
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- If company has config rows, return them
    IF EXISTS (SELECT 1 FROM dbo.REC_Pipeline_Stage_Config WHERE fk_CompanyId = @CompanyId)
    BEGIN
        SELECT
            pk_StageConfigId    AS StageConfigId,
            fk_CompanyId        AS CompanyId,
            StageCode,
            StageLabel,
            StageIcon,
            StageColor,
            StageOrder,
            IsEnabled,
            ModifiedBy,
            ModifiedAt
        FROM dbo.REC_Pipeline_Stage_Config
        WHERE fk_CompanyId = @CompanyId
        ORDER BY StageOrder ASC;
    END
    ELSE
    BEGIN
        -- Fallback: return global defaults as virtual rows (not persisted)
        SELECT
            CAST(0 AS BIGINT)       AS StageConfigId,
            @CompanyId              AS CompanyId,
            StageCode,
            StageLabel,
            StageIcon,
            StageColor,
            StageOrder,
            CAST(1 AS BIT)          AS IsEnabled,
            CAST(NULL AS NVARCHAR(150)) AS ModifiedBy,
            CAST(NULL AS DATETIME)  AS ModifiedAt
        FROM (VALUES
            ('Applied',             '1. Applied',           'bi-inbox',              '#64748b', 1),
            ('Interview_Scheduled', '2. Interview',          'bi-calendar-event',     '#0ea5e9', 2),
            ('Selected',            '3. Selected',           'bi-check-circle',       '#8b5cf6', 3),
            ('Docs_Submitted',      '4. Docs Review',        'bi-file-earmark-check', '#f59e0b', 4),
            ('Offer_Issued',        '5. Offer Sent',         'bi-award',              '#10b981', 5),
            ('Hired',               '6. Hired & Onboarded',  'bi-person-check-fill',  '#0051d5', 6)
        ) AS Defaults(StageCode, StageLabel, StageIcon, StageColor, StageOrder)
        ORDER BY StageOrder ASC;
    END
END
GO

PRINT 'Created USP: usp_REC_GetPipelineStageConfig';
GO

-- -----------------------------------------------------------------------------
-- STEP 4: USP — Toggle / Upsert a single stage's IsEnabled flag
--         Called from admin UI when HR Admin enables/disables a stage.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_REC_UpsertPipelineStageConfig', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_REC_UpsertPipelineStageConfig;
GO

CREATE PROCEDURE dbo.usp_REC_UpsertPipelineStageConfig
    @CompanyId   NVARCHAR(50),
    @StageCode   NVARCHAR(50),
    @StageLabel  NVARCHAR(100),
    @StageIcon   NVARCHAR(50),
    @StageColor  NVARCHAR(20),
    @StageOrder  INT,
    @IsEnabled   BIT,
    @ModifiedBy  NVARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Pipeline_Stage_Config
        WHERE fk_CompanyId = @CompanyId AND StageCode = @StageCode
    )
    BEGIN
        -- UPDATE existing row
        UPDATE dbo.REC_Pipeline_Stage_Config
        SET
            IsEnabled  = @IsEnabled,
            StageLabel = @StageLabel,
            StageIcon  = @StageIcon,
            StageColor = @StageColor,
            StageOrder = @StageOrder,
            ModifiedBy = @ModifiedBy,
            ModifiedAt = GETDATE()
        WHERE fk_CompanyId = @CompanyId AND StageCode = @StageCode;

        SELECT 'UPDATED' AS Result,
               pk_StageConfigId AS StageConfigId
        FROM dbo.REC_Pipeline_Stage_Config
        WHERE fk_CompanyId = @CompanyId AND StageCode = @StageCode;
    END
    ELSE
    BEGIN
        -- INSERT new row
        INSERT INTO dbo.REC_Pipeline_Stage_Config
            (fk_CompanyId, StageCode, StageLabel, StageIcon, StageColor, StageOrder, IsEnabled, CreatedBy)
        VALUES
            (@CompanyId, @StageCode, @StageLabel, @StageIcon, @StageColor, @StageOrder, @IsEnabled, @ModifiedBy);

        SELECT 'INSERTED' AS Result,
               CAST(SCOPE_IDENTITY() AS BIGINT) AS StageConfigId;
    END
END
GO

PRINT 'Created USP: usp_REC_UpsertPipelineStageConfig';
GO

-- =============================================================================
-- END OF SCRIPT
-- Verify:
--   EXEC dbo.usp_REC_GetPipelineStageConfig @CompanyId = 'GU-1'
--   EXEC dbo.usp_REC_UpsertPipelineStageConfig
--        @CompanyId='GU-1', @StageCode='Docs_Submitted', @StageLabel='4. Docs Review',
--        @StageIcon='bi-file-earmark-check', @StageColor='#f59e0b', @StageOrder=4,
--        @IsEnabled=0, @ModifiedBy='Admin'
-- =============================================================================
