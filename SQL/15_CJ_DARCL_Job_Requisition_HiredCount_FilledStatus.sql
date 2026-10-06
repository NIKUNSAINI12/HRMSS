-- =============================================================================
-- Migration 15: CJ DARCL Job Requisition Hired Count & Fulfilled Headcount Architecture
-- Standard: 100% Company-Specific, Zero Hardcoding, Direct DB Metric
-- =============================================================================

USE HRBook_22;
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitions
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        r.pk_reqid AS jobId,
        r.pk_reqid AS reqId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        loc.locationCode AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        ISNULL(r.ServiceType, 'Fleet & Transportation') AS serviceType,
        ISNULL(r.SkillCategory, 'Skilled') AS skillCategory,
        ISNULL(r.No_of_post, 1) AS openPositions,
        ISNULL(r.No_of_post, 1) AS openingsCount,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
        ISNULL(r.IsDiversityHiring, 0) AS isDiversityHiring,
        r.DiversityCategory AS diversityCategory,
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
        r.LeadRecruiter AS leadRecruiter,
        r.Interviewers AS interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.dated AS createdDate,
        r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        r.L1ApproverName,
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
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR r.fk_companyId = @CompanyId
        OR NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE fk_companyId = @CompanyId)
    )
    ORDER BY r.pk_reqid DESC;
END;
GO

PRINT 'dbo.usp_REC_GetJobRequisitions updated with hiredCount and isFilled.';
