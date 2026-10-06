-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture (Step 1 Master)
-- File: 02_SP_Location_Update_Manpower_Buffer.sql
-- Purpose: Stored Procedure to Update Manpower Demand & Buffer on Location_Mst with Audit Logging
-- Created: 2026-09-22
-- ============================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE [dbo].[Location_Update_Manpower_Buffer]
(
    @pk_locid VARCHAR(50),
    @BaseDemand INT,
    @BufferPercent DECIMAL(5,2),
    @ModifiedBy VARCHAR(50) = 'Admin'
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BufferHeads INT = CEILING(@BaseDemand * (@BufferPercent / 100.0));
    DECLARE @TargetCapacity INT = @BaseDemand + @BufferHeads;

    -- Validate or resolve fk_updUserID against UM_Users_Mst to satisfy Foreign Key constraint FK_Location_Mst_UM_Users_Mst1
    DECLARE @ValidUserId VARCHAR(50) = NULL;

    SELECT TOP 1 @ValidUserId = pk_userId
    FROM dbo.UM_Users_Mst WITH (NOLOCK)
    WHERE pk_userId = @ModifiedBy OR loginName = @ModifiedBy;

    -- Retrieve old values for audit logging
    DECLARE @OldBaseDemand INT = 0, @OldBufferPercent DECIMAL(5,2) = 0.00;
    SELECT TOP 1 @OldBaseDemand = ISNULL(BaseDemand, 0), @OldBufferPercent = ISNULL(BufferPercent, 0.00)
    FROM dbo.Location_Mst WITH (NOLOCK)
    WHERE pk_locid = @pk_locid OR locationCode = @pk_locid OR code = @pk_locid;

    -- Update existing Location_Mst record
    UPDATE dbo.Location_Mst
    SET BaseDemand = @BaseDemand,
        BufferPercent = @BufferPercent,
        BufferHeads = @BufferHeads,
        TargetCapacity = @TargetCapacity,
        fk_updUserID = ISNULL(@ValidUserId, fk_updUserID)
    WHERE pk_locid = @pk_locid OR locationCode = @pk_locid OR code = @pk_locid;

    -- Record in existing CL_UpdateAudit_Log table (wrapped in TRY-CATCH to ensure update transaction completes)
    BEGIN TRY
        IF (@OldBufferPercent <> @BufferPercent)
        BEGIN
            INSERT INTO dbo.CL_UpdateAudit_Log
            (
                DocumentId, DocumentCode, DocumentName, FieldName, 
                PreviousValue, CurrentValue, EntryBy, EntryDate
            )
            VALUES
            (
                0, @pk_locid, 'Location_Mst_Buffer', 'BufferPercent',
                CAST(@OldBufferPercent AS VARCHAR(50)), CAST(@BufferPercent AS VARCHAR(50)),
                @ModifiedBy, GETDATE()
            );
        END

        IF (@OldBaseDemand <> @BaseDemand)
        BEGIN
            INSERT INTO dbo.CL_UpdateAudit_Log
            (
                DocumentId, DocumentCode, DocumentName, FieldName, 
                PreviousValue, CurrentValue, EntryBy, EntryDate
            )
            VALUES
            (
                0, @pk_locid, 'Location_Mst_Buffer', 'BaseDemand',
                CAST(@OldBaseDemand AS VARCHAR(50)), CAST(@BaseDemand AS VARCHAR(50)),
                @ModifiedBy, GETDATE()
            );
        END
    END TRY
    BEGIN CATCH
    END CATCH;

    SELECT 1 AS Status, 'Location manpower and buffer updated successfully.' AS Message;
END
GO
