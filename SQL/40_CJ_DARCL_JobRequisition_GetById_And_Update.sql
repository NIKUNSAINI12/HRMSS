-- ============================================================================
-- CJ DARCL Recruitment Architecture: Job Requisition GetById and Update
-- Provides:
--   1. Schema update (UpdatedBy, UpdatedById, UpdatedDate)
--   2. dbo.usp_REC_GetJobRequisitionById
--   3. dbo.usp_REC_UpdateJobRequisition
-- ============================================================================

USE [HRBook_22];
GO

-- 1. Ensure Updated audit columns exist on REC_JobRequisition_Mst
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'UpdatedBy')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD UpdatedBy NVARCHAR(150) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'UpdatedById')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD UpdatedById NVARCHAR(50) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.REC_JobRequisition_Mst') AND name = 'UpdatedDate')
    ALTER TABLE dbo.REC_JobRequisition_Mst ADD UpdatedDate DATETIME NULL;
GO

-- 1b. Stored Procedure: dbo.usp_UM_ResolveUserName (Optimized SP to eliminate any inline SQL)
CREATE OR ALTER PROCEDURE dbo.usp_UM_ResolveUserName
    @UserId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 
        COALESCE(e.empname, u.name, u.loginname, 'HR User') AS ResolvedName
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.SAL_Employee_Mst e WITH (NOLOCK) ON e.pk_empid = u.fk_empId
    WHERE u.pk_userId = @UserId 
       OR u.loginname = @UserId 
       OR CAST(u.fk_empId AS NVARCHAR(50)) = @UserId 
       OR e.empcode = @UserId;
END;
GO

-- 2. Stored Procedure: dbo.usp_REC_GetJobRequisitionById
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitionById
    @ReqId BIGINT,
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize company filters
    DECLARE @CleanCompanyId NVARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId NVARCHAR(50) = NULL;

    IF @CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '' AND @CompanyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@CompanyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    SELECT TOP 1
        r.pk_reqid AS reqId,
        r.pk_reqid AS jobId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        r.fk_deptid AS fk_deptid,
        r.fk_subdeptid AS fk_subdeptid,
        ISNULL(subdept.description, '') AS subDepartment,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        r.fk_locid AS fk_locid,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        r.fk_desgid AS fk_desgid,
        r.fk_classid AS fk_classid,
        ISNULL(grd.gradedetails, '') AS gradeName,
        r.fk_catid AS fk_catid,
        ISNULL(cat.category, '') AS categoryName,
        r.fk_costcentreid AS fk_costcentreid,
        ISNULL(cc.description, '') AS costCenterName,
        r.fk_zoneId AS fk_zoneId,
        r.fk_cityid AS fk_cityid,
        ISNULL(r.BusinessVertical, '') AS businessVertical,
        ISNULL(r.ServiceType, 'Fleet & Transportation') AS serviceType,
        ISNULL(r.SkillCategory, 'Skilled') AS skillCategory,
        ISNULL(r.No_of_post, 1) AS openPositions,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
        r.ReplacedEmpName AS replacedEmpName,
        r.Reason_of_Replacement AS replacementReason,
        r.IsDiversityHiring AS isDiversityHiring,
        r.DiversityCategory AS diversityCategory,
        COALESCE(r.CompanyId, r.fk_companyId) AS companyId,
        COALESCE(r.fk_companyId, r.CompanyId) AS fk_companyId,
        ISNULL(r.WorkplaceType, 'On-Site') AS workplaceType,
        ISNULL(r.EmploymentType, 'Full-Time') AS employmentType,
        ISNULL(r.Priority, 'Medium') AS priority,
        ISNULL(r.Currency, 'INR') AS currency,
        r.Experience_From AS experienceMin,
        r.Experience_To AS experienceMax,
        r.CTC_From AS ctcMin,
        r.CTC_To AS ctcMax,
        r.TargetStartDate AS targetStartDate,
        r.EducationLevel AS educationLevel,
        r.PrimarySkills AS primarySkills,
        r.SecondarySkills AS secondarySkills,
        r.NoticePeriodMaxDays AS noticePeriodMaxDays,
        r.Industry AS industry,
        r.JobDescription AS jobDescription,
        r.Roles_Responsibilities AS responsibilities,
        r.quali AS qualifications,
        r.Benefits AS benefits,
        r.HiringManager AS hiringManager,
        r.HiringManagerId AS hiringManagerId,
        r.LeadRecruiter AS leadRecruiter,
        r.LeadRecruiterId AS leadRecruiterId,
        r.L1ApproverName,
        r.L1ApproverId,
        r.Interviewers AS interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.SubmittedById AS submittedById,
        r.UpdatedBy AS updatedBy,
        r.UpdatedById AS updatedById,
        r.UpdatedDate AS updatedDate,
        r.dated AS createdDate,
        r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        ISNULL(r.RequisitionStatus, 
            CASE 
                WHEN r.status = 'D' THEN 'Draft'
                WHEN r.status = 'B' THEN 'Pending Buffer Approval'
                WHEN r.status = 'P' THEN 'Pending Approval'
                WHEN r.status = 'A' THEN 'Active'
                ELSE 'Active'
            END
        ) AS status,
        -- Total applicants count
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) WHERE ca.fk_reqid = r.pk_reqid) AS applicantsCount,
        -- Total candidates successfully hired
        ISNULL((
            SELECT COUNT(1) 
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
            WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'
        ), 0) AS hiredCount
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) 
        ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.Sub_Department_Mst subdept WITH (NOLOCK) 
        ON subdept.pk_subdeptid = r.fk_subdeptid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) 
        ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) 
        ON des.pk_desgid = r.fk_desgid
    LEFT JOIN dbo.SAL_Grade_Mst grd WITH (NOLOCK) 
        ON grd.pk_gradeid = r.fk_classid
    LEFT JOIN dbo.SAL_Category_Mst cat WITH (NOLOCK) 
        ON cat.pk_catid = r.fk_catid
    LEFT JOIN dbo.SAL_Cost_Centre_Mst cc WITH (NOLOCK) 
        ON cc.pk_cost_centre_id = r.fk_costcentreid
    WHERE r.pk_reqid = @ReqId
      AND (
          @CleanCompanyId IS NULL 
          OR r.CompanyId = @CleanCompanyId 
          OR r.CompanyId = @PrefixedCompanyId
          OR r.fk_companyId = @CleanCompanyId
          OR r.fk_companyId = @PrefixedCompanyId
          OR r.CompanyId IS NULL
      );
END;
GO

-- 3. Stored Procedure: dbo.usp_REC_UpdateJobRequisition
-- Updates an existing MRF without modifying its MRF Code
CREATE OR ALTER PROCEDURE dbo.usp_REC_UpdateJobRequisition
    @ReqId               BIGINT,
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100),
    @Designation         NVARCHAR(150),
    @SkillCategory       NVARCHAR(100),
    @OpenPositions       INT,
    @Location            NVARCHAR(150),
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @ReplacedEmpName     NVARCHAR(150) = NULL,
    @ReplacementReason   NVARCHAR(500) = NULL,
    @IsDiversityHiring   BIT           = NULL,
    @DiversityCategory   NVARCHAR(100) = NULL,
    @WorkplaceType       NVARCHAR(50)  = 'On-Site',
    @EmploymentType      NVARCHAR(50)  = 'Full-Time',
    @ExperienceMin       DECIMAL(4,1)  = NULL,
    @ExperienceMax       DECIMAL(4,1)  = NULL,
    @CtcMin              DECIMAL(18,2) = NULL,
    @CtcMax              DECIMAL(18,2) = NULL,
    @Currency            NVARCHAR(10)  = 'INR',
    @Priority            NVARCHAR(50)  = 'Medium',
    @TargetStartDate     NVARCHAR(50)  = NULL,
    @EducationLevel      NVARCHAR(100) = NULL,
    @PrimarySkills       NVARCHAR(500) = NULL,
    @SecondarySkills     NVARCHAR(500) = NULL,
    @NoticePeriodMaxDays INT           = NULL,
    @Industry            NVARCHAR(150) = NULL,
    @JobDescription      NVARCHAR(MAX) = NULL,
    @Responsibilities    NVARCHAR(MAX) = NULL,
    @Qualifications      NVARCHAR(MAX) = NULL,
    @Benefits            NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @UpdatedBy           NVARCHAR(150) = 'HR User',
    @UpdatedById         NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL,
    @fk_locid            NVARCHAR(50)  = NULL,
    @fk_deptid           NVARCHAR(50)  = NULL,
    @fk_subdeptid        NVARCHAR(50)  = NULL,
    @fk_desgid           NVARCHAR(50)  = NULL,
    @fk_classid          NVARCHAR(50)  = NULL,
    @fk_catid            NVARCHAR(50)  = NULL,
    @fk_costcentreid     BIGINT        = NULL,
    @fk_zoneId           NVARCHAR(50)  = NULL,
    @fk_cityid           NVARCHAR(50)  = NULL,
    @BusinessVertical    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify Record Exists
    IF NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    BEGIN
        SELECT 0 AS Success, @ReqId AS reqId, '' AS mrfCode, 'Job Requisition not found.' AS Message;
        RETURN;
    END;

    -- Normalize IDs
    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;

    -- Lookup Location if missing
    IF @fk_locid IS NULL OR @fk_locid = ''
    BEGIN
        SELECT TOP 1 @fk_locid = pk_locid 
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;
    END;

    -- Lookup Designation if missing
    IF @fk_desgid IS NULL OR @fk_desgid = ''
    BEGIN
        SELECT TOP 1 @fk_desgid = pk_desgid 
        FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;
    END;

    -- Lookup Department if missing
    IF @fk_deptid IS NULL OR @fk_deptid = ''
    BEGIN
        SELECT TOP 1 @fk_deptid = pk_deptid 
        FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;
    END;

    DECLARE @CurrentStatus CHAR(1);
    DECLARE @ExistingMrfCode NVARCHAR(100);
    SELECT @CurrentStatus = status, @ExistingMrfCode = Mrfcode 
    FROM dbo.REC_JobRequisition_Mst 
    WHERE pk_reqid = @ReqId;

    DECLARE @statusChar CHAR(1) = CASE 
        WHEN @IsDraft = 1 THEN 'D' 
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'P'
        WHEN @CurrentStatus IN ('P', 'B') AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus IN ('P', 'B') AND @IsBufferUtilized = 0 THEN 'P'
        ELSE @CurrentStatus 
    END;

    DECLARE @requisitionStatus NVARCHAR(50) = CASE 
        WHEN @IsDraft = 1 THEN 'Draft' 
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' 
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'Pending Approval' 
        WHEN @CurrentStatus IN ('P', 'B') AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval'
        WHEN @CurrentStatus IN ('P', 'B') AND @IsBufferUtilized = 0 THEN 'Pending Approval'
        ELSE (SELECT ISNULL(RequisitionStatus, 'Active') FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    END;

    -- Update Requisition without touching Mrfcode or creation dates
    UPDATE dbo.REC_JobRequisition_Mst
    SET 
        jobtitle                  = @JobTitle,
        fk_locid                  = COALESCE(@fk_locid, fk_locid),
        fk_deptid                 = COALESCE(@fk_deptid, fk_deptid),
        fk_subdeptid              = COALESCE(@fk_subdeptid, fk_subdeptid),
        fk_desgid                 = COALESCE(@fk_desgid, fk_desgid),
        fk_classid                = COALESCE(@fk_classid, fk_classid),
        fk_catid                  = COALESCE(@fk_catid, fk_catid),
        fk_costcentreid           = COALESCE(@fk_costcentreid, fk_costcentreid),
        fk_zoneId                 = COALESCE(@fk_zoneId, fk_zoneId),
        fk_cityid                 = COALESCE(@fk_cityid, fk_cityid),
        BusinessVertical          = @BusinessVertical,
        No_of_post                = @OpenPositions,
        Reason_of_Requirement     = @HiringType,
        ReplacedEmpName           = @ReplacedEmpName,
        Reason_of_Replacement     = @ReplacementReason,
        ServiceType               = @ServiceType,
        SkillCategory             = @SkillCategory,
        IsDiversityHiring         = @IsDiversityHiring,
        DiversityCategory         = @DiversityCategory,
        WorkplaceType             = @WorkplaceType,
        EmploymentType            = @EmploymentType,
        Experience_From           = @ExperienceMin,
        Experience_To             = @ExperienceMax,
        CTC_From                  = @CtcMin,
        CTC_To                    = @CtcMax,
        Currency                  = @Currency,
        Priority                  = @Priority,
        TargetStartDate           = @TargetStartDate,
        EducationLevel            = @EducationLevel,
        PrimarySkills             = @PrimarySkills,
        SecondarySkills           = @SecondarySkills,
        NoticePeriodMaxDays       = @NoticePeriodMaxDays,
        Industry                  = @Industry,
        JobDescription            = @JobDescription,
        Justification_of_Position = @JobDescription,
        Roles_Responsibilities    = @Responsibilities,
        quali                     = @Qualifications,
        Benefits                  = @Benefits,
        IsBufferUtilized          = @IsBufferUtilized,
        BufferHeadsUtilized       = @BufferHeadsUtilized,
        status                    = @statusChar,
        RequisitionStatus         = @requisitionStatus,
        UpdatedBy                 = @UpdatedBy,
        UpdatedById               = @UpdatedById,
        UpdatedDate               = GETDATE()
    WHERE pk_reqid = @ReqId;

    -- Audit Logging in CL_UpdateAudit_Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @ExistingMrfCode, 'REC_JobRequisition_Mst', 'JobRequisitionUpdate',
            'Multiple Fields', 'Updated', @UpdatedBy, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    SELECT 
        1 AS Success,
        @ReqId AS reqId,
        @ExistingMrfCode AS mrfCode,
        'Job Requisition updated successfully.' AS Message;
END;
GO
