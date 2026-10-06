--GO
/****** Object:  StoredProcedure [dbo].[USP_Report_Master_Data_Get]    Script Date: 03-10-2026 12:04:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[USP_Report_Master_Data_Get]
(
    @fk_companyId VARCHAR(50) = ''
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Resultset 1: Vendors
    SELECT DISTINCT 
        ISNULL(v.Vendor_Code, v.pk_recId) AS Value, 
        ISNULL(v.Vendor_Name, 'Vendor') + ' (' + ISNULL(v.Vendor_Code, v.pk_recId) + ')' AS Label 
    FROM REC_Candidate_Details v
    WHERE (v.IsVendor = 1 OR v.Vendor_Code IS NOT NULL) 
      AND (@fk_companyId = '' OR v.fk_companyId = @fk_companyId)
    ORDER BY Label;

    -- Resultset 2: Locations
    SELECT DISTINCT 
        loc.pk_locid AS Value, 
        loc.locname AS Label 
    FROM Location_Mst loc
    WHERE loc.locname IS NOT NULL AND loc.locname <> '' 
      AND (@fk_companyId = '' OR loc.fk_companyId = @fk_companyId)
    ORDER BY loc.locname;

    -- Resultset 3: Departments
    SELECT DISTINCT 
        dept.pk_deptid AS Value, 
        dept.description AS Label 
    FROM Department_Mst dept
    WHERE dept.description IS NOT NULL AND dept.description <> '' 
      AND (@fk_companyId = '' OR dept.fk_companyId = @fk_companyId)
    ORDER BY dept.description;

    -- Resultset 4: Jobs / Requisitions
    SELECT DISTINCT 
        CAST(j.pk_reqid AS VARCHAR(50)) AS Value,
        ISNULL(j.Mrfcode + ' - ', '') + ISNULL(j.jobtitle, 'Job #' + CAST(j.pk_reqid AS VARCHAR(20))) AS Label
    FROM REC_JobRequisition_Mst j
    WHERE (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
    ORDER BY Label;

    -- Resultset 5: Candidate Sources
    SELECT DISTINCT 
        c.source AS Value,
        c.source AS Label
    FROM REC_Candidate_Details c
    WHERE c.source IS NOT NULL AND c.source <> ''
      AND (c.IsVendor IS NULL OR c.IsVendor = 0)
    ORDER BY c.source;
END;
