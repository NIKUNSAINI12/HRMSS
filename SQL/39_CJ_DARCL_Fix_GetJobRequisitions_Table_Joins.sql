-- ============================================================================
-- CJ DARCL Recruitment Architecture: Fix Table Names in usp_REC_GetJobRequisitions
-- Fixes: Sub_Department_Mst, SAL_Grade_Mst, SAL_Category_Mst, SAL_Cost_Centre_Mst
-- ============================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitions
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize numeric/prefixed CompanyId
    DECLARE @CleanCompanyId NVARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId NVARCHAR(50) = NULL;

    IF @CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '' AND @CompanyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@CompanyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    SELECT 
        r.pk_reqid AS jobId,
        r.pk_reqid AS reqId,
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
        ISNULL(r.No_of_post, 1) AS openingsCount,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
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
        r.dated AS createdDate,
        r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        r.L1Action,
        r.L1ActionDate,
        r.L1Remarks,
        r.L2ApproverName,
        r.L2Action,
        r.L2ActionDate,
        r.L2Remarks,
        r.L3ApproverName,
        r.L3Action,
        r.L3ActionDate,
        r.L3Remarks,
        r.RejectedByLevel,
        r.RejectedByName,
        r.RejectedByDate,
        r.RejectionRemarks,
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
        -- Total candidates successfully hired/onboarded (Step 13)
        ISNULL((
            SELECT COUNT(1) 
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
            WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'
        ), 0) AS hiredCount,
        -- Whether all required headcount positions are 100% fulfilled
        CASE 
            WHEN ISNULL((
                SELECT COUNT(1) 
                FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
                WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'
            ), 0) >= ISNULL(r.No_of_post, 1) 
            THEN 1 
            ELSE 0 
        END AS isFilled
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.Sub_Department_Mst subdept WITH (NOLOCK) ON subdept.pk_subdeptid = r.fk_subdeptid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) ON des.pk_desgid = r.fk_desgid
    LEFT JOIN dbo.SAL_Grade_Mst grd WITH (NOLOCK) ON grd.pk_gradeid = r.fk_classid
    LEFT JOIN dbo.SAL_Category_Mst cat WITH (NOLOCK) ON cat.pk_catid = r.fk_catid
    LEFT JOIN dbo.SAL_Cost_Centre_Mst cc WITH (NOLOCK) ON cc.pk_cost_centre_id = r.fk_costcentreid
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR r.CompanyId = @CompanyId
        OR r.fk_companyId = @CompanyId
        OR r.CompanyId = @CleanCompanyId
        OR r.fk_companyId = @CleanCompanyId
        OR r.CompanyId = @PrefixedCompanyId
        OR r.fk_companyId = @PrefixedCompanyId
        OR NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE CompanyId IN (@CompanyId, @CleanCompanyId, @PrefixedCompanyId) OR fk_companyId IN (@CompanyId, @CleanCompanyId, @PrefixedCompanyId))
    )
    ORDER BY r.pk_reqid DESC;
END;
GO
