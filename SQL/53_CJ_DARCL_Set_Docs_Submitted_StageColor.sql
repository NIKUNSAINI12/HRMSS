-- =============================================================================
-- Migration 53: Set Docs_Submitted StageColor to Vibrant High-Contrast Amber
-- Standard: 100% Company-Specific, Zero Hardcoding
-- =============================================================================

USE HRBook_22;
GO

UPDATE dbo.REC_Pipeline_Stage_Config
SET StageColor = '#d97706',
    ModifiedAt = GETDATE(),
    ModifiedBy = 'System'
WHERE StageCode = 'Docs_Submitted';
GO
