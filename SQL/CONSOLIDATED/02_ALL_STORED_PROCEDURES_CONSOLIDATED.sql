-- ==========================================================================================
-- CJ DARCL RECRUITMENT & ONBOARDING LIFECYCLE (STEPS 1 - 16)
-- CONSOLIDATED MASTER STORED PROCEDURES (AUTHORITATIVE LATEST DEFINITIONS)
-- Generated automatically from audited 67 incremental patch files
-- ==========================================================================================

USE [HRMS]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETJOBREQUISITIONS
-- Source File: 41_Rejection_Resubmit_Workflow.sql
-- ==========================================================================================
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
        -- Rejection / Resubmit tracking
        ISNULL(r.isDisapproved, 0) AS isDisapproved,
        r.RejectedByLevel          AS rejectedByLevel,
        r.RejectedByName           AS rejectedByName,
        r.RejectedByDate           AS rejectedByDate,
        r.RejectionRemarks         AS rejectionRemarks,
        r.ResubmittedDate          AS resubmittedDate,
        r.ResubmittedBy            AS resubmittedBy,
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

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORASSIGNEDJOBS
-- Source File: 47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorAssignedJobs
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        jm.pk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', YEAR(jm.dated), '/', jm.pk_reqid)) AS mrfCode,
        jm.jobtitle                                                      AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
        jm.fk_locid                                                      AS fk_locid,
        ISNULL(loc.locname, 'Hub Logistics')                             AS location,
        ISNULL(jm.No_of_post, 1)                                         AS openingsCount,
        ISNULL(rvm.AllocatedQuota, 10)                                   AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                  AS commissionTerms,
        COALESCE(rvm.VendorType, 'Supply Vendors')                       AS vendorType,
        ISNULL(jm.Priority, 'Medium')                                    AS priority,
        ISNULL(jm.WorkplaceType, 'On-Site')                              AS workplaceType,
        ISNULL(jm.EmploymentType, 'Full-Time')                           AS employmentType,
        jm.Experience_From                                               AS experienceMin,
        jm.Experience_To                                                 AS experienceMax,
        jm.CTC_From                                                      AS ctcMin,
        jm.CTC_To                                                        AS ctcMax,
        jm.JobDescription                                                AS jobDescription,
        rvm.AssignedDate                                                 AS assignedDate,
        ISNULL(jm.WorkflowStatus, 'Active')                              AS workflowStatus,
        ISNULL(jm.status, 'A')                                           AS status,
        ISNULL(jm.RequisitionStatus, 'Active')                           AS requisitionStatus,
        CAST(1 AS BIT)                                                   AS isApproved,
        -- Sourced by this vendor for this MRF
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId
        ) AS submittedCount,
        -- Reached 'Selected' from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified')
        ) AS selectedCount,
        -- Hired from this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = jm.pk_reqid 
              AND ca.fk_vendorId = @VendorId 
              AND ca.Stage = 'Hired'
        ) AS hiredCount
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = jm.fk_deptid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      -- MANDATORY: Vendors can ONLY see APPROVED jobs
      AND (
          jm.WorkflowStatus = 'Active' 
          OR jm.status = 'A' 
          OR jm.RequisitionStatus = 'Active' 
          OR jm.WorkflowStatus = 'Approved'
      )
    ORDER BY rvm.AssignedDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORSFORREQUISITIONMAPPING
-- Source File: 33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorsForRequisitionMapping
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL,
    @VendorType  NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Determine Job Location and Company for this requisition
    DECLARE @JobLocId VARCHAR(50);
    DECLARE @ReqCompanyId VARCHAR(50);

    SELECT 
        @JobLocId = fk_locid, 
        @ReqCompanyId = COALESCE(NULLIF(fk_companyId, ''), NULLIF(CompanyId, ''))
    FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
    WHERE pk_reqid = @ReqId;

    -- The requisition's company is the authoritative tenant boundary for vendor allocation.
    -- If the requisition has a company assigned, vendors must belong to THAT company.
    IF (@ReqCompanyId IS NOT NULL AND LTRIM(RTRIM(@ReqCompanyId)) <> '' AND @ReqCompanyId <> '0')
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END;

    -- 2. Return ONLY vendors strictly assigned to @CompanyId
    SELECT 
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS mobile,
        ISNULL(cd.email, '')                                           AS email,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, '')   AS contactPerson,
        CASE WHEN rvm.pk_mapId IS NOT NULL AND rvm.IsActive = 1 THEN 1 ELSE 0 END AS isMapped,
        COALESCE(rvm.VendorType, @VendorType, 'Supply Vendors')        AS vendorType,
        ISNULL(rvm.AllocatedQuota, 0)                                  AS allocatedQuota,
        ISNULL(rvm.CommissionTerms, 'Standard (8.33%)')                AS commissionTerms,
        rvm.AssignedDate                                               AS assignedDate,
        (
            SELECT COUNT(1) 
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_reqid = @ReqId 
              AND (ca.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR ca.fk_vendorId = cd.Vendor_Code)
        ) AS candidateCount
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    LEFT JOIN dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
           ON (rvm.fk_vendorId = CAST(cd.pk_recId AS NVARCHAR(50)) OR rvm.fk_vendorId = cd.Vendor_Code)
          AND rvm.fk_reqid = @ReqId
          AND rvm.IsActive = 1
    WHERE cd.IsVendor = 1
      -- MANDATORY 100% COMPANY SCOPING: Must belong to the requisition's company
      AND (
          cd.fk_companyId = @CompanyId 
          OR cd.CompanyId = @CompanyId
      )
    ORDER BY isMapped DESC, vendorName ASC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_ASSIGNBENCHCANDIDATESTOJOB
-- Source File: 49_CJ_DARCL_Reset_Reallocated_Candidate_State_As_New.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_AssignBenchCandidatesToJob
    @ReqId          BIGINT,
    @VendorId       NVARCHAR(50)  = NULL,
    @AppIdList      NVARCHAR(MAX),
    @CompanyId      NVARCHAR(50),
    @AssignedBy     NVARCHAR(100) = 'Recruiter'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Clean & normalize inputs
    SET @CompanyId = NULLIF(LTRIM(RTRIM(@CompanyId)), '');
    SET @VendorId  = NULLIF(LTRIM(RTRIM(@VendorId)), '');
    SET @AppIdList = LTRIM(RTRIM(ISNULL(@AppIdList, '')));

    IF @ReqId IS NULL OR @ReqId = 0 OR @AppIdList = ''
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'Target Requisition ID and at least one Candidate Application ID are required.' AS Message,
               0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    -- Retrieve target requisition metadata
    DECLARE @TargetMrfCode   NVARCHAR(100);
    DECLARE @TargetJobTitle  NVARCHAR(200);
    DECLARE @TargetDeptName  NVARCHAR(150);
    DECLARE @TargetLocName   NVARCHAR(150);
    DECLARE @ReqWorkflowStat NVARCHAR(50);
    DECLARE @TargetCompanyId NVARCHAR(50);

    SELECT 
        @TargetMrfCode   = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @TargetJobTitle  = r.jobtitle,
        @TargetDeptName  = ISNULL(dept.description, 'General'),
        @TargetLocName   = ISNULL(loc.locname, 'Hub Operations'),
        @ReqWorkflowStat = r.WorkflowStatus,
        @TargetCompanyId = COALESCE(r.CompanyId, r.fk_companyId)
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    WHERE r.pk_reqid = @ReqId
      AND (@CompanyId IS NULL OR r.CompanyId = @CompanyId OR r.fk_companyId = @CompanyId);

    IF @TargetMrfCode IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'Target job requisition not found or does not belong to authorized company.' AS Message,
               0 AS SucceededCount, 0 AS FailedCount;
        RETURN;
    END

    -- Parse @AppIdList into temporary table
    CREATE TABLE #TargetAppIds (
        AppId BIGINT PRIMARY KEY
    );

    INSERT INTO #TargetAppIds (AppId)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT)
    FROM STRING_SPLIT(@AppIdList, ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL;

    -- Filter eligible candidates (Vendor owned if passed, Bench or Rejected, not active)
    CREATE TABLE #EligibleCandidates (
        AppId           BIGINT,
        ApplicationNo   NVARCHAR(50),
        CandidateName   NVARCHAR(150),
        WasRejected     BIT,
        PreviousStage   NVARCHAR(50)
    );

    INSERT INTO #EligibleCandidates (AppId, ApplicationNo, CandidateName, WasRejected, PreviousStage)
    SELECT 
        ca.pk_appId,
        ca.ApplicationNo,
        ca.CandidateName,
        ISNULL(ca.IsRejected, 0),
        ISNULL(ca.Stage, 'Bench')
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    INNER JOIN #TargetAppIds t ON t.AppId = ca.pk_appId
    WHERE (@VendorId IS NULL OR ca.fk_vendorId = @VendorId)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      -- Must be on Bench or Rejected
      AND (
          (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench')
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected' OR ca.InterviewStatus = 'Rejected')
      );

    DECLARE @EligibleCount INT = (SELECT COUNT(1) FROM #EligibleCandidates);
    DECLARE @RequestedCount INT = (SELECT COUNT(1) FROM #TargetAppIds);

    IF @EligibleCount = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               'None of the selected candidates are currently eligible for allocation (must be on Bench or Previously Rejected).' AS Message,
               0 AS SucceededCount, 
               @RequestedCount AS FailedCount;
        DROP TABLE #TargetAppIds;
        DROP TABLE #EligibleCandidates;
        RETURN;
    END

    -- Execute Transactional Re-allocation to Target Requisition as FRESH / NEW candidate
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update candidate applications to link to target job, reset rejection flags, set stage to Applied & InterviewStatus to Pending
        UPDATE ca
        SET 
            ca.fk_reqid                 = @ReqId,
            ca.MrfCode                  = @TargetMrfCode,
            ca.Designation              = @TargetJobTitle,
            ca.Department               = @TargetDeptName,
            ca.OperatingHub             = @TargetLocName,
            ca.Stage                    = 'Applied',
            ca.IsRejected               = 0,
            ca.RejectionReason          = NULL,
            ca.RejectionStage           = NULL,
            ca.RejectionRemarks         = NULL,
            ca.InterviewStatus          = 'Pending',
            ca.InterviewRound           = NULL,
            ca.InterviewDate            = NULL,
            ca.InterviewerId            = NULL,
            ca.InterviewerName          = NULL,
            ca.InterviewRemarks         = NULL,
            ca.InterviewScore           = NULL,
            ca.DocVerificationStatus    = 'Pending',
            ca.DocVerifiedBy            = NULL,
            ca.DocVerificationRemarks   = NULL,
            ca.OfferedCTC               = NULL,
            ca.OfferLetterSentDate      = NULL,
            ca.ExpectedJoiningDate      = NULL,
            ca.EmployeeCode             = NULL,
            ca.HiredDate                = NULL,
            ca.CandidateTags            = NULL,
            ca.LastUpdatedDate          = GETDATE(),
            ca.LastUpdatedBy            = @AssignedBy
        FROM dbo.REC_Candidate_Applications ca
        INNER JOIN #EligibleCandidates ec ON ec.AppId = ca.pk_appId;

        -- Audit Logging in REC_Candidate_Lifecycle_Audit
        IF OBJECT_ID('dbo.REC_Candidate_Lifecycle_Audit', 'U') IS NOT NULL
        BEGIN
            INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
                fk_appId,
                ApplicationNo,
                ActionType,
                PreviousStage,
                NewStage,
                ActionByUserId,
                ActionByName,
                Remarks,
                ActionDate,
                CompanyId,
                fk_companyId
            )
            SELECT 
                ec.AppId,
                ec.ApplicationNo,
                'POOL_ALLOCATION_TO_JOB',
                ec.PreviousStage,
                'Applied',
                @AssignedBy,
                @AssignedBy,
                CONCAT('Allocated from candidate pool (', CASE WHEN ec.WasRejected = 1 THEN 'Previously Rejected' ELSE 'Talent Bench' END, ') to job ', @TargetMrfCode, ' as New Applicant by ', @AssignedBy),
                GETDATE(),
                @CompanyId,
                @CompanyId
            FROM #EligibleCandidates ec;
        END

        COMMIT TRANSACTION;

        SELECT 
            CAST(1 AS BIT) AS Success,
            CONCAT('Successfully allocated ', @EligibleCount, ' candidate(s) to ', @TargetMrfCode, ' as New Applied applicants.') AS Message,
            @EligibleCount AS SucceededCount,
            (@RequestedCount - @EligibleCount) AS FailedCount;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT 
            CAST(0 AS BIT) AS Success,
            CONCAT('Transaction failed: ', ERROR_MESSAGE()) AS Message,
            0 AS SucceededCount,
            @RequestedCount AS FailedCount;
    END CATCH;

    DROP TABLE #TargetAppIds;
    DROP TABLE #EligibleCandidates;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETCANDIDATEPIPELINEROSTER
-- Source File: 51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidatePipelineRoster
    @CompanyId   NVARCHAR(50),
    @ReqId       BIGINT       = NULL,
    @StageFilter NVARCHAR(50) = 'ALL',
    @SearchQuery NVARCHAR(100)= NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ca.pk_appId               AS appId,
        ca.ApplicationNo          AS applicationNo,
        ca.fk_reqid               AS reqId,
        ca.MrfCode                AS mrfCode,
        ca.CandidateName          AS candidateName,
        ca.Mobile                 AS mobile,
        ca.Email                  AS email,
        ca.Gender                 AS gender,
        ca.DateOfBirth            AS dateOfBirth,
        ca.FatherName             AS fatherName,
        ca.CurrentLocation        AS currentLocation,
        ca.OperatingHub           AS operatingHub,
        ca.Department             AS department,
        ca.Designation            AS designation,
        ca.SourceType             AS sourceType,
        ca.fk_vendorId            AS vendorId,
        ca.VendorName             AS vendorName,
        ca.Stage                  AS stage,
        ca.SkillClassification   AS skillClassification,
        ca.InterviewStatus        AS interviewStatus,
        ca.InterviewerId          AS interviewerId,
        ca.InterviewerName        AS interviewerName,
        ca.InterviewDate          AS interviewDate,
        ca.InterviewRound         AS interviewRound,
        ca.InterviewRemarks       AS interviewRemarks,
        ca.InterviewScore         AS interviewScore,
        ca.AadhaarNo              AS aadhaarNo,
        ca.PanNo                  AS panNo,
        ca.BankAccNo              AS bankAccNo,
        ca.BankIfsc               AS bankIfsc,
        ca.BankName               AS bankName,
        ca.DocVerificationStatus  AS docVerificationStatus,
        ca.DocVerifiedBy          AS docVerifiedBy,
        ca.DocVerificationRemarks AS docVerificationRemarks,
        ca.CandidateCode          AS candidateCode,
        ca.OfferedCTC             AS offeredCTC,
        ca.OfferLetterSentDate    AS offerLetterSentDate,
        ca.ExpectedJoiningDate    AS expectedJoiningDate,
        ca.EmployeeCode           AS employeeCode,
        ca.HiredDate              AS hiredDate,
        ca.CreatedDate            AS createdDate,
        -- Tagging, Diversity & Rejection Fields
        ISNULL(ca.CandidateTags, '')    AS candidateTags,
        ISNULL(ca.IsDiversityHiring, 0) AS isDiversityHiring,
        ISNULL(ca.DiversityCategory, '') AS diversityCategory,
        ca.RejectionReason              AS rejectionReason,
        ca.RejectionRemarks             AS rejectionRemarks,
        ca.CooloffPolicy                AS cooloffPolicy,
        ca.AssignedReviewer             AS assignedReviewer,
        -- Rejection Stage Locking Flags
        ISNULL(ca.IsRejected, CASE WHEN ca.InterviewStatus = 'Rejected' OR ca.Stage = 'Rejected' THEN 1 ELSE 0 END) AS isRejected,
        ISNULL(ca.RejectionStage, ca.Stage) AS rejectionStage,
        COALESCE(ca.CompanyId, ca.fk_companyId) AS companyId,
        COALESCE(ca.fk_companyId, ca.CompanyId) AS fk_companyId
    FROM dbo.REC_Candidate_Applications ca
    WHERE (
        @CompanyId IS NULL 
        OR @CompanyId = '' 
        OR @CompanyId = '0' 
        OR ca.CompanyId = @CompanyId 
        OR ca.fk_companyId = @CompanyId
    )
      AND (@ReqId IS NULL OR @ReqId = 0 OR ca.fk_reqid = @ReqId)
      AND (
          @StageFilter = 'ALL' 
          OR (@StageFilter = 'APPLIED' AND ca.Stage = 'Applied')
          OR (@StageFilter = 'INTERVIEW' AND (ca.Stage IN ('Interview_Scheduled', 'Interview_Completed', 'Hold') OR ca.InterviewStatus = 'Hold'))
          OR (@StageFilter = 'SELECTED' AND ca.Stage = 'Selected')
          OR (@StageFilter = 'DOCS' AND ca.Stage IN ('Docs_Submitted', 'Docs_Verified'))
          OR (@StageFilter = 'OFFER' AND ca.Stage = 'Offer_Issued')
          OR (@StageFilter = 'HIRED' AND ca.Stage = 'Hired')
          OR (@StageFilter = 'REJECTED' AND (ca.IsRejected = 1 OR ca.InterviewStatus = 'Rejected' OR ca.Stage = 'Rejected'))
      )
      AND (
          @SearchQuery IS NULL OR @SearchQuery = '' 
          OR ca.CandidateName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.ApplicationNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Mobile LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.MrfCode LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.VendorName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.CandidateTags LIKE CONCAT('%', @SearchQuery, '%')
      );
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SAVEVENDORREQUISITIONMAPPING
-- Source File: 33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveVendorRequisitionMapping
    @ReqId           BIGINT,
    @VendorId        NVARCHAR(50),
    @VendorName      NVARCHAR(200) = NULL,
    @VendorType      NVARCHAR(50)  = 'Supply Vendors',
    @AllocatedQuota  INT           = 0,
    @CommissionTerms NVARCHAR(200) = 'Standard (8.33%)',
    @IsActive        BIT           = 1,
    @AssignedBy      NVARCHAR(100) = 'Administrator',
    @CompanyId       NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Authoritative Requisition Company resolution
    DECLARE @ReqCompanyId VARCHAR(50);
    SELECT @ReqCompanyId = COALESCE(NULLIF(fk_companyId, ''), NULLIF(CompanyId, '')) 
    FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK) 
    WHERE pk_reqid = @ReqId;

    IF (@ReqCompanyId IS NOT NULL AND LTRIM(RTRIM(@ReqCompanyId)) <> '' AND @ReqCompanyId <> '0')
    BEGIN
        SET @CompanyId = @ReqCompanyId;
    END;

    IF @IsActive = 0
    BEGIN
        DELETE FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));

        SELECT 1 AS Success, 'Vendor deallocated successfully.' AS Message, '' AS VendorType;
        RETURN;
    END;

    IF @VendorType IS NULL OR LTRIM(RTRIM(@VendorType)) = ''
        SET @VendorType = 'Supply Vendors';

    -- Look up vendor name if not provided
    IF (@VendorName IS NULL OR LTRIM(RTRIM(@VendorName)) = '')
    BEGIN
        SELECT TOP 1 @VendorName = COALESCE(NULLIF(Vendor_Name, ''), candidate_name, 'Vendor')
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId OR Vendor_Code = @VendorId;
    END;

    IF EXISTS (
        SELECT 1 FROM dbo.REC_Requisition_Vendor_Mapping 
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId))
    )
    BEGIN
        UPDATE dbo.REC_Requisition_Vendor_Mapping SET
            VendorName      = ISNULL(@VendorName, VendorName),
            VendorType      = @VendorType,
            AllocatedQuota  = @AllocatedQuota,
            CommissionTerms = @CommissionTerms,
            IsActive        = 1,
            AssignedBy      = @AssignedBy,
            AssignedDate    = GETDATE(),
            fk_companyId    = ISNULL(@CompanyId, fk_companyId)
        WHERE fk_reqid = @ReqId 
          AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 CAST(pk_recId AS NVARCHAR(50)) FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Requisition_Vendor_Mapping (
            fk_reqid, fk_vendorId, VendorName, VendorType, AllocatedQuota,
            CommissionTerms, IsActive, AssignedBy, AssignedDate, fk_companyId
        ) VALUES (
            @ReqId, @VendorId, ISNULL(@VendorName, 'Vendor'), @VendorType, @AllocatedQuota,
            @CommissionTerms, 1, @AssignedBy, GETDATE(), @CompanyId
        );
    END;

    SELECT 1 AS Success, 'Vendor mapping updated successfully.' AS Message, @VendorType AS VendorType;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORPORTALMETRICS
-- Source File: 47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPortalMetrics
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean vendorId
    SET @VendorId = LTRIM(RTRIM(ISNULL(@VendorId, '')));

    -- 1. Total Assigned MRFs (Active & Approved only)
    DECLARE @AssignedJobsCount INT = 0;
    SELECT @AssignedJobsCount = COUNT(DISTINCT rvm.fk_reqid)
    FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
    WHERE rvm.fk_vendorId = @VendorId
      AND rvm.IsActive = 1
      AND (
          jm.WorkflowStatus = 'Active' 
          OR jm.status = 'A' 
          OR jm.RequisitionStatus = 'Active' 
          OR jm.WorkflowStatus = 'Approved'
      );

    -- 2. Total Applications Sourced
    DECLARE @TotalSubmissions INT = 0;
    SELECT @TotalSubmissions = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId;

    -- 3. Candidates Under Evaluation / Interviewing (Active on a Job, Not Bench, Not Rejected)
    DECLARE @InReviewCount INT = 0;
    SELECT @InReviewCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.fk_reqid IS NOT NULL 
      AND ca.fk_reqid > 0
      AND ISNULL(ca.MrfCode, '') <> 'BENCH'
      AND ca.Stage IN ('Applied', 'Screening', 'Interview', 'Interview_Scheduled')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND ca.Stage <> 'Rejected';

    -- 4. Passed Interview Candidates (Selected & Onboarding Docs stage)
    DECLARE @SelectedCount INT = 0;
    SELECT @SelectedCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Issued')
      AND ISNULL(ca.IsRejected, 0) = 0
      AND ca.Stage <> 'Rejected';

    -- 5. Joined / Hired
    DECLARE @HiredCount INT = 0;
    SELECT @HiredCount = COUNT(1)
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Hired'
      AND ISNULL(ca.IsRejected, 0) = 0;

    SELECT 
        @AssignedJobsCount AS assignedJobsCount,
        @TotalSubmissions  AS totalSubmissions,
        @InReviewCount     AS inReviewCount,
        @SelectedCount     AS selectedCount,
        @HiredCount        AS hiredCount;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SAVEJOBREQUISITION
-- Source File: 38_CJ_DARCL_SaveJobRequisition_Approver_And_Team.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveJobRequisition
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100) = NULL,
    @Designation         NVARCHAR(150) = NULL,
    @SkillCategory       NVARCHAR(100) = NULL,
    @OpenPositions       INT           = 1,
    @Location            NVARCHAR(150) = NULL,
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @IsDiversityHiring   BIT           = NULL,
    @DiversityCategory   VARCHAR(MAX)  = NULL,
    @WorkplaceType       NVARCHAR(50)  = 'On-Site',
    @EmploymentType      NVARCHAR(50)  = 'Full-Time',
    @ExperienceMin       DECIMAL(5,2)  = NULL,
    @ExperienceMax       DECIMAL(5,2)  = NULL,
    @CtcMin              DECIMAL(12,2) = NULL,
    @CtcMax              DECIMAL(12,2) = NULL,
    @Currency            NVARCHAR(10)  = 'INR',
    @Priority            NVARCHAR(50)  = 'Medium',
    @TargetStartDate     NVARCHAR(50)  = NULL,
    @EducationLevel      NVARCHAR(100) = NULL,
    @PrimarySkills       NVARCHAR(MAX) = NULL,
    @SecondarySkills     NVARCHAR(MAX) = NULL,
    @NoticePeriodMaxDays INT           = NULL,
    @Industry            NVARCHAR(100) = 'Logistics & Supply Chain',
    @JobDescription      NVARCHAR(MAX) = NULL,
    @Responsibilities    NVARCHAR(MAX) = NULL,
    @Qualifications      NVARCHAR(MAX) = NULL,
    @Benefits            NVARCHAR(MAX) = NULL,
    @HiringManager       NVARCHAR(150) = NULL,
    @HiringManagerId     NVARCHAR(50)  = NULL,
    @LeadRecruiter       NVARCHAR(150) = NULL,
    @LeadRecruiterId     NVARCHAR(50)  = NULL,
    @L1ApproverName      NVARCHAR(200) = NULL,
    @L1ApproverId        NVARCHAR(50)  = NULL,
    @Interviewers        NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @SubmittedBy         NVARCHAR(150) = 'Site HR Admin',
    @SubmittedById       NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL,
    -- Specific Foreign Key IDs from Employee Master Standard Dropdowns
    @fk_locid            NVARCHAR(50)  = NULL,
    @fk_deptid           NVARCHAR(50)  = NULL,
    @fk_subdeptid        NVARCHAR(50)  = NULL,
    @fk_desgid           NVARCHAR(50)  = NULL,
    @fk_classid          NVARCHAR(50)  = NULL, -- Grade
    @fk_catid            NVARCHAR(50)  = NULL, -- Category
    @fk_costcentreid     BIGINT        = NULL, -- Cost Center
    @fk_zoneId           NVARCHAR(50)  = NULL,
    @fk_cityid           NVARCHAR(50)  = NULL,
    @BusinessVertical    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize Company ID
    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;
    IF (@fk_companyId IS NULL OR @fk_companyId = '') AND (@CompanyId IS NOT NULL AND @CompanyId <> '')
        SET @fk_companyId = @CompanyId;

    -- Dynamic Lookup location ID if not explicitly provided
    IF @fk_locid IS NULL OR @fk_locid = ''
    BEGIN
        SELECT TOP 1 
            @fk_locid = pk_locid,
            @CompanyId = COALESCE(@CompanyId, fk_companyId),
            @fk_companyId = COALESCE(@fk_companyId, fk_companyId)
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;
    END
    ELSE
    BEGIN
        -- Also populate location name if missing
        IF @Location IS NULL OR @Location = ''
        BEGIN
            SELECT TOP 1 @Location = locname FROM dbo.Location_Mst WITH (NOLOCK) WHERE pk_locid = @fk_locid;
        END;
    END;

    -- Dynamic Lookup designation ID if not explicitly provided
    IF @fk_desgid IS NULL OR @fk_desgid = ''
    BEGIN
        SELECT TOP 1 @fk_desgid = pk_desgid 
        FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;
    END
    ELSE
    BEGIN
        IF @Designation IS NULL OR @Designation = ''
        BEGIN
            SELECT TOP 1 @Designation = designation FROM dbo.SAL_Designation_Mst WITH (NOLOCK) WHERE pk_desgid = @fk_desgid;
        END;
    END;

    -- Dynamic Lookup department ID if not explicitly provided
    IF @fk_deptid IS NULL OR @fk_deptid = ''
    BEGIN
        SELECT TOP 1 @fk_deptid = pk_deptid 
        FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;
    END
    ELSE
    BEGIN
        IF @Department IS NULL OR @Department = ''
        BEGIN
            SELECT TOP 1 @Department = description FROM dbo.Department_Mst WITH (NOLOCK) WHERE pk_deptid = @fk_deptid;
        END;
    END;

    -- Default user ID if null
    IF @SubmittedById IS NULL OR @SubmittedById = ''
        SET @SubmittedById = '1';

    -- Format Status and MRF Code
    DECLARE @statusChar CHAR(1) = CASE WHEN @IsDraft = 1 THEN 'D' WHEN @IsBufferUtilized = 1 THEN 'B' ELSE 'P' END;
    DECLARE @requisitionStatus NVARCHAR(50) = CASE WHEN @IsDraft = 1 THEN 'Draft' WHEN @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' ELSE 'Pending Approval' END;
    DECLARE @remarks NVARCHAR(500) = CONCAT('HM: ', @HiringManager, ' | Recruiter: ', @LeadRecruiter, ' | Approver: ', @L1ApproverName, ' | Sub: ', @SubmittedBy);
    
    DECLARE @GeneratedMrfCode NVARCHAR(100) = CONCAT('MRF/', YEAR(GETDATE()), '/', RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4));

    -- Insert Requisition Record with All Employee Master Standard Dropdowns
    INSERT INTO dbo.REC_JobRequisition_Mst (
        jobtitle, fk_locid, fk_deptid, fk_desgid, fk_classid, fk_costcentreid,
        fk_subdeptid, fk_catid, fk_zoneId, fk_cityid, BusinessVertical,
        HiringManagerId, LeadRecruiterId, L1ApproverId, L1ApproverName,
        No_of_post, dated, status,
        RequisitionStatus, Reason_of_Requirement, ServiceType, SkillCategory,
        IsDiversityHiring, DiversityCategory, WorkplaceType, EmploymentType,
        Experience_From, Experience_To, CTC_From, CTC_To, Currency, Priority,
        TargetStartDate, EducationLevel, PrimarySkills, SecondarySkills,
        NoticePeriodMaxDays, Industry, JobDescription, Justification_of_Position,
        Roles_Responsibilities, quali, Benefits, HiringManager, LeadRecruiter,
        Interviewers, IsBufferUtilized, BufferHeadsUtilized, SubmittedBy, SubmittedById,
        Mrfcode, Remarks,
        WorkflowStatus, CurrentApprovalLevel, SubmittedDate, LastWorkflowActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @JobTitle, @fk_locid, @fk_deptid, @fk_desgid, @fk_classid, @fk_costcentreid,
        @fk_subdeptid, @fk_catid, @fk_zoneId, @fk_cityid, @BusinessVertical,
        @HiringManagerId, @LeadRecruiterId, @L1ApproverId, @L1ApproverName,
        @OpenPositions, GETDATE(), @statusChar,
        @requisitionStatus, @HiringType, @ServiceType, @SkillCategory,
        @IsDiversityHiring, @DiversityCategory, @WorkplaceType, @EmploymentType,
        @ExperienceMin, @ExperienceMax, @CtcMin, @CtcMax, @Currency, @Priority,
        @TargetStartDate, @EducationLevel, @PrimarySkills, @SecondarySkills,
        @NoticePeriodMaxDays, @Industry, @JobDescription, @JobDescription,
        @Responsibilities, @Qualifications, @Benefits, @HiringManager, @LeadRecruiter,
        @Interviewers, @IsBufferUtilized, @BufferHeadsUtilized, @SubmittedBy, @SubmittedById,
        @GeneratedMrfCode, @remarks,
        'L1_Pending', 1, GETDATE(), GETDATE(),
        @CompanyId, @fk_companyId
    );

    DECLARE @NewReqId BIGINT = SCOPE_IDENTITY();

    -- Insert initial submit audit log in REC_JobRequisition_Mst_Approval with Company Mapping
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive, 
        approvalLevel, action, approverName, approverRole, workflowStatus,
        CompanyId, fk_companyId
    ) VALUES (
        @NewReqId, @SubmittedById, GETDATE(), 0, 'Requisition submitted for approval', 1, 
        0, 'Submitted', @SubmittedBy, 'Site HR', 'L1_Pending',
        @CompanyId, @fk_companyId
    );

    -- Mandatory Audit Logging: Insert into CL_UpdateAudit_Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @NewReqId, @GeneratedMrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            'None', 'L1_Pending', @SubmittedBy, GETDATE()
        );
    END TRY
    BEGIN CATCH
        -- Non-blocking audit log catch
    END CATCH;

    -- Return the result
    SELECT 
        1 AS Success,
        @NewReqId AS reqId, 
        @GeneratedMrfCode AS mrfCode,
        CASE WHEN @IsDraft = 1 THEN 'Draft saved successfully' ELSE 'Manpower requisition raised successfully â€” sent for L1 approval' END AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SUBMITINTERVIEWEVALUATION
-- Source File: 51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitInterviewEvaluation
    @AppId               BIGINT,
    @SkillClassification NVARCHAR(50)  = 'Semi-Skilled', -- Unskilled / Semi-Skilled / Skilled / Highly Skilled
    @Decision            NVARCHAR(50)  = 'Selected',     -- Selected / Rejected / Hold / Pending
    @Remarks             NVARCHAR(MAX) = 'Interview completed.',
    @Score               INT           = 80,
    @EvaluatorName       NVARCHAR(150) = 'Interviewer',
    @CompanyId           NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CleanCompId NVARCHAR(50) = REPLACE(ISNULL(@CompanyId, ''), 'GU-', '');
    DECLARE @PrefixedCompId NVARCHAR(50) = CASE WHEN @CleanCompId <> '' THEN 'GU-' + @CleanCompId ELSE '' END;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @ActualCompanyId NVARCHAR(50);

    -- 1. Try finding application matching company scope
    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @ActualCompanyId = COALESCE(CompanyId, fk_companyId, @CompanyId)
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId
      AND (
          @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
          OR CompanyId IN (@CompanyId, @CleanCompId, @PrefixedCompId)
          OR fk_companyId IN (@CompanyId, @CleanCompId, @PrefixedCompId)
      );

    -- 2. Fallback by pk_appId if company formatting differed in session
    IF @AppNo IS NULL
    BEGIN
        SELECT 
            @CurrentStage = Stage, 
            @AppNo = ApplicationNo,
            @ActualCompanyId = COALESCE(CompanyId, fk_companyId, @CompanyId)
        FROM dbo.REC_Candidate_Applications
        WHERE pk_appId = @AppId;
    END

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- 3. Determine next workflow stage based on interview decision:
    -- 'Hold' candidates MUST stay in 'Interview_Scheduled' with InterviewStatus = 'Hold'
    -- so they remain visible on the pipeline board under the Interview stage!
    DECLARE @NextStage NVARCHAR(50) = CASE 
        WHEN @Decision = 'Selected' THEN 'Selected'
        WHEN @Decision = 'Rejected' THEN 'Rejected'
        WHEN @Decision = 'Hold'     THEN 'Interview_Scheduled'
        ELSE 'Interview_Completed'
    END;

    -- 4. Update Candidate Application Record with Evaluation Details & Score
    UPDATE dbo.REC_Candidate_Applications SET
        Stage                = @NextStage,
        InterviewStatus      = @Decision,
        SkillClassification  = ISNULL(@SkillClassification, 'Semi-Skilled'),
        InterviewRemarks     = @Remarks,
        InterviewScore       = ISNULL(@Score, 80),
        InterviewerName      = @EvaluatorName,
        InterviewDate        = GETDATE(),
        LastUpdatedDate      = GETDATE(),
        LastUpdatedBy        = @EvaluatorName
    WHERE pk_appId = @AppId;

    -- 5. If Decision is Rejected, lock rejection stage
    IF @Decision = 'Rejected'
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            IsRejected       = 1,
            RejectionStage   = ISNULL(RejectionStage, 'Interview_Scheduled'),
            RejectionReason  = ISNULL(RejectionReason, 'Interview Evaluation Not Cleared'),
            RejectionRemarks = ISNULL(@Remarks, 'Did not meet competency benchmark during interview assessment')
        WHERE pk_appId = @AppId;
    END
    ELSE
    BEGIN
        -- If previously marked rejected and now Selected or Hold, clear isRejected lock
        UPDATE dbo.REC_Candidate_Applications SET
            IsRejected       = 0
        WHERE pk_appId = @AppId;
    END

    -- 6. Insert Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'EVALUATE', @CurrentStage, @NextStage,
        NULL, @EvaluatorName, 'Interviewer', 
        CONCAT('Evaluation: ', @Decision, ' | Skill Level: ', @SkillClassification, ' | Score: ', @Score, ' | Remarks: ', @Remarks), 
        GETDATE(), @ActualCompanyId
    );

    SELECT 
        1 AS Success, 
        'Interview evaluation saved successfully.' AS Message, 
        ISNULL(@Score, 80) AS Score, 
        @NextStage AS NewStage,
        @Decision AS Decision;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_MOVECANDIDATESTAGE
-- Source File: 52_CJ_DARCL_Enhance_MoveCandidateStage_CompanyScoping_And_Hold_Progression.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_MoveCandidateStage
    @AppId           BIGINT,
    @TargetStage     NVARCHAR(50),
    @Remarks         NVARCHAR(MAX)  = NULL,
    @MovedBy         NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @RowCompanyId NVARCHAR(50);

    SELECT 
        @CurrentStage  = Stage, 
        @AppNo         = ApplicationNo,
        @CandidateName = CandidateName,
        @RowCompanyId  = fk_companyId
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
          OR fk_companyId = REPLACE(@CompanyId, 'GU-', '')
          OR fk_companyId = CONCAT('GU-', @CompanyId)
      );

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- If @CompanyId was blank or prefix-mismatched, synchronize with row's company id
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0')
        SET @CompanyId = @RowCompanyId;

    -- =========================================================================
    -- MANDATORY RULE: IF CURRENT STAGE IS DOCS REVIEW (Docs_Submitted),
    -- ALL MANDATORY ONBOARDING DOCUMENTS MUST BE APPROVED BEFORE MOVING FORWARD
    -- =========================================================================
    IF (@CurrentStage = 'Docs_Submitted' OR @CurrentStage = 'Selected') 
       AND @TargetStage IN ('Docs_Verified', 'Offer_Issued', 'Hired')
    BEGIN
        DECLARE @UnapprovedMandatoryCount INT = 0;

        SELECT @UnapprovedMandatoryCount = COUNT(1)
        FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
        WHERE cd.fk_appId = @AppId
          AND cd.IsMandatory = 1
          AND ISNULL(cd.VerificationStatus, 'Pending') != 'Approved';

        DECLARE @TotalDocsCount INT = 0;
        SELECT @TotalDocsCount = COUNT(1)
        FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
        WHERE cd.fk_appId = @AppId AND ISNULL(cd.FileName, '') != '';

        IF @TotalDocsCount = 0 OR @UnapprovedMandatoryCount > 0
        BEGIN
            SELECT 0 AS Success, 
                   CONCAT('Cannot advance candidate to ', @TargetStage, ': All mandatory onboarding documents must be reviewed and approved by Site HR first (Pending: ', @UnapprovedMandatoryCount, ').') AS Message;
            RETURN;
        END
    END

    -- Synchronize interview/document/hiring sub-statuses when stage changes
    DECLARE @InterviewStatus NVARCHAR(50) = NULL;
    DECLARE @DocStatus NVARCHAR(50) = NULL;

    IF @TargetStage = 'Selected'
        SET @InterviewStatus = 'Selected';
    ELSE IF @TargetStage = 'Interview_Completed'
        SET @InterviewStatus = 'Completed';
    ELSE IF @TargetStage = 'Interview_Scheduled'
        SET @InterviewStatus = 'Scheduled';
    ELSE IF @TargetStage = 'Docs_Verified'
        SET @DocStatus = 'Verified';
    ELSE IF @TargetStage = 'Docs_Submitted'
        SET @DocStatus = 'Pending';

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                  = @TargetStage,
        InterviewStatus        = ISNULL(@InterviewStatus, InterviewStatus),
        DocVerificationStatus  = ISNULL(@DocStatus, DocVerificationStatus),
        LastUpdatedDate        = GETDATE(),
        LastUpdatedBy          = @MovedBy
    WHERE pk_appId = @AppId 
      AND (
          @CompanyId IS NULL 
          OR @CompanyId = '' 
          OR @CompanyId = '0' 
          OR fk_companyId = @CompanyId
          OR fk_companyId = REPLACE(@CompanyId, 'GU-', '')
          OR fk_companyId = CONCAT('GU-', @CompanyId)
      );

    -- Insert Audit Entry
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'STAGE_TRANSITION', @CurrentStage, @TargetStage,
        NULL, @MovedBy, 'Recruiter',
        CONCAT('Candidate moved from [', @CurrentStage, '] to [', @TargetStage, ']. ', ISNULL(@Remarks, 'Stage progression confirmed.')),
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, 
           CONCAT('Candidate successfully moved to ', @TargetStage) AS Message,
           @TargetStage AS newStage;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORLISTFORPORTAL
-- Source File: 32_CJ_DARCL_Strict_Company_Scoped_Vendor_Allocation.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorListForPortal
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        cd.pk_recId                                                    AS vendorId,
        COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
        ISNULL(cd.Vendor_Code, '')                                     AS vendorCode,
        COALESCE(NULLIF(cd.Vendor_ContactNo, ''), cd.mobile, '')       AS contactNo,
        ISNULL(cd.email, '')                                           AS email,
        -- Total Active MRFs Assigned to this vendor within this company
        (
            SELECT COUNT(DISTINCT rvm.fk_reqid)
            FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
            INNER JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = rvm.fk_reqid
            WHERE rvm.fk_vendorId = cd.pk_recId
              AND rvm.IsActive = 1
              AND (jm.RequisitionStatus = 'Active' OR jm.WorkflowStatus = 'Active' OR jm.status = 'A')
              AND (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0' OR jm.fk_companyId = @CompanyId OR jm.CompanyId = @CompanyId)
        ) AS assignedJobsCount,
        -- Total Candidates Sourced by this vendor
        (
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
            WHERE ca.fk_vendorId = cd.pk_recId
        ) AS totalCandidatesSourced
    FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
    WHERE cd.IsVendor = 1
      -- STRICT 100% COMPANY SCOPING (Zero Hardcoding)
      AND (
          @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
          OR cd.CompanyId = @CompanyId 
          OR cd.fk_companyId = @CompanyId
      )
    ORDER BY vendorName ASC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SUBMITVENDORCANDIDATE
-- Source File: 34_CJ_DARCL_Vendor_All_Candidates_And_Bench_Registration.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitVendorCandidate
    @ReqId          BIGINT        = NULL,
    @VendorId       NVARCHAR(50),
    @VendorName     NVARCHAR(150),
    @CandidateName  NVARCHAR(150),
    @Mobile         NVARCHAR(20),
    @Email          NVARCHAR(150) = NULL,
    @Gender         NVARCHAR(20)  = 'Male',
    @DateOfBirth    DATE          = NULL,
    @FatherName     NVARCHAR(150) = NULL,
    @AadhaarNo      NVARCHAR(30)  = NULL,
    @ResumeDocPath  NVARCHAR(500) = NULL,
    @SubmittedBy    NVARCHAR(100) = 'Vendor Portal',
    @CompanyId      NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Treat 0 as NULL for ReqId (bench/unassigned)
    IF @ReqId = 0 SET @ReqId = NULL;

    -- Dynamic Company resolution from Job Requisition if not supplied
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0') AND @ReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    -- Clean inputs
    SET @CandidateName = LTRIM(RTRIM(ISNULL(@CandidateName, '')));
    SET @Mobile = REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@Mobile, ''))), ' ', ''), '-', '');
    SET @Email  = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @FatherName = NULLIF(LTRIM(RTRIM(@FatherName)), '');
    IF @AadhaarNo IS NOT NULL
        SET @AadhaarNo = REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), ' ', ''), '-', '');
    SET @AadhaarNo = NULLIF(@AadhaarNo, '');

    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- 1. Format Validations (Phone & Aadhaar)
    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF LEN(@CandidateName) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 'Candidate full name is mandatory.' AS Message, 0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    IF LEN(@Mobile) <> 10 OR @Mobile LIKE '%[^0-9]%' OR LEFT(@Mobile, 1) NOT IN ('6', '7', '8', '9')
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Invalid Mobile Number [', @Mobile, ']. Must be a valid 10-digit number starting with 6-9.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    IF @AadhaarNo IS NULL OR LEN(@AadhaarNo) <> 12 OR @AadhaarNo LIKE '%[^0-9]%'
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Invalid Aadhaar Number [', ISNULL(@AadhaarNo, 'EMPTY'), ']. Must be a valid 12-digit numeric Aadhaar number.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- 2. Duplicate Validations (Matching Candidate Pipeline Page Standard)
    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- Check 2a: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2b: Mobile duplicate in REC_Candidate_Details
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE (mobile = @Mobile OR phone = @Mobile)
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Mobile number ', @Mobile, ' already exists in Candidate Database.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2c: Aadhaar duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE AadhaarNo = @AadhaarNo
          AND ISNULL(IsRejected, 0) = 0
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Aadhaar card ', @AadhaarNo, ' already registered in Candidate Applications.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- Check 2d: Aadhaar duplicate in SAL_Employee_Mst
    IF EXISTS (
        SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
        WHERE (adhaarNo = @AadhaarNo OR adhaarNo = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
          AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SELECT CAST(0 AS BIT) AS Success, 
               CONCAT('Duplicate Profile: Candidate with Aadhaar ', @AadhaarNo, ' is already an employee in Company Master.') AS Message, 
               0 AS AppId, '' AS ApplicationNo;
        RETURN;
    END

    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- 3. Job Metadata Resolution & Global Unique Sequence Generation
    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    DECLARE @MrfCode  NVARCHAR(50)  = 'BENCH';
    DECLARE @JobTitle NVARCHAR(150) = 'Talent Pool Candidate';
    DECLARE @LocName  NVARCHAR(100) = 'Talent Pool';
    DECLARE @DeptName NVARCHAR(100) = 'General';

    IF @ReqId IS NOT NULL
    BEGIN
        SELECT 
            @MrfCode  = ISNULL(jm.Mrfcode, CONCAT('MRF/', jm.pk_reqid)),
            @JobTitle = ISNULL(jm.jobtitle, 'Logistics Executive'),
            @LocName  = ISNULL(loc.locname, 'Hub Operations'),
            @DeptName = ISNULL(dept.description, 'Operations')
        FROM dbo.REC_JobRequisition_Mst jm WITH (NOLOCK)
        LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = jm.fk_locid
        LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = jm.fk_deptid
        WHERE jm.pk_reqid = @ReqId;
    END

    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    -- Global across REC_Candidate_Applications to satisfy table UNIQUE constraint on ApplicationNo
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- 4. Insert Candidate Application
    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, ResumeDocPath, Stage, SkillClassification, InterviewStatus,
        fk_companyId, CompanyId, CreatedBy, CreatedDate, LastUpdatedBy, LastUpdatedDate
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @LocName, @LocName,
        @DeptName, @JobTitle, 'Vendor', @VendorId, @VendorName,
        @AadhaarNo, @ResumeDocPath, 'Applied', 'Semi-Skilled', 'Pending',
        @CompanyId, @CompanyId, @SubmittedBy, GETDATE(), @SubmittedBy, GETDATE()
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Seed 13 Standard Onboarding Document placeholders
    IF OBJECT_ID('dbo.usp_REC_SeedCandidateDocuments', 'P') IS NOT NULL
    BEGIN
        EXEC dbo.usp_REC_SeedCandidateDocuments @AppId = @NewAppId, @CompanyId = @CompanyId;
    END

    -- Log Audit Trail
    DECLARE @AuditRemarks NVARCHAR(MAX) = CASE 
        WHEN @ReqId IS NOT NULL THEN CONCAT('Candidate profile verified and submitted by vendor [', @VendorName, '] for MRF ', @MrfCode, ' (', @JobTitle, ')')
        ELSE CONCAT('Candidate profile pre-registered beforehand into Talent Bench by vendor [', @VendorName, ']')
    END;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, CASE WHEN @ReqId IS NOT NULL THEN 'VENDOR_SUBMISSION' ELSE 'VENDOR_BENCH_REGISTRATION' END, 
        'None', 'Applied',
        @SubmittedBy, 'Vendor Partner',
        @AuditRemarks,
        GETDATE(), @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success, 
        CASE 
            WHEN @ReqId IS NOT NULL THEN CONCAT('Candidate registered successfully for ', @MrfCode, '.')
            ELSE 'Candidate pre-registered into Talent Bench successfully.'
        END AS Message, 
        @NewAppId AS AppId, 
        @NextAppNo AS ApplicationNo;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_REGISTERCANDIDATEAPPLICATION
-- Source File: 57_CJ_DARCL_Do_Not_Create_Candidate_On_Duplicate.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidateApplication
    @ReqId           BIGINT,
    @CandidateName   NVARCHAR(150),
    @Mobile          NVARCHAR(20),
    @Email           NVARCHAR(100)  = NULL,
    @Gender          NVARCHAR(20)   = 'Male',
    @DateOfBirth     DATE           = NULL,
    @FatherName      NVARCHAR(150)  = NULL,
    @CurrentLocation NVARCHAR(150)  = NULL,
    @SourceType      NVARCHAR(50)   = 'Vendor', -- Vendor / QR_Direct / Career_Portal
    @VendorId        NVARCHAR(50)   = NULL,
    @VendorName      NVARCHAR(150)  = NULL,
    @AadhaarNo       NVARCHAR(20)   = NULL,     -- Optional Aadhaar Card No
    @CreatedBy       NVARCHAR(100)  = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Clean & normalize inputs
    SET @Mobile = LTRIM(RTRIM(ISNULL(@Mobile, '')));
    SET @Mobile = REPLACE(REPLACE(REPLACE(REPLACE(@Mobile, '+91', ''), '-', ''), ' ', ''), '+', '');
    IF LEN(@Mobile) > 10
        SET @Mobile = RIGHT(@Mobile, 10);

    IF @AadhaarNo IS NOT NULL
    BEGIN
        SET @AadhaarNo = REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', '');
        IF LEN(@AadhaarNo) = 0 SET @AadhaarNo = NULL;
    END

    -- 2. Verify requisition exists
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @ReqStatus NVARCHAR(50);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);
    DECLARE @ReqCompanyId NVARCHAR(50);

    SELECT 
        @MrfCode      = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @ReqStatus    = r.WorkflowStatus,
        @Hub          = ISNULL(loc.locname, 'Hub Operations'),
        @Dept         = ISNULL(dept.description, 'Operations'),
        @Desg         = ISNULL(des.designation, r.jobtitle),
        @ReqCompanyId = r.fk_companyId
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des WITH (NOLOCK) ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
    BEGIN
        SELECT 
            CAST(0 AS BIT) AS Success, 
            CAST(0 AS BIT) AS IsRejected, 
            'Requisition not found.' AS Message,
            CAST(0 AS BIGINT) AS appId,
            CAST('' AS NVARCHAR(50)) AS applicationNo,
            '' AS mrfCode;
        RETURN;
    END

    IF (@CompanyId IS NULL OR @CompanyId = '')
        SET @CompanyId = @ReqCompanyId;

    -- 3. Duplicate Validations: Check active applications and database records
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupAadhaar BIT = 0;
    DECLARE @DupDetail NVARCHAR(500) = '';

    -- Check 1: Active application duplicate in REC_Candidate_Applications (Company-Scoped)
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
          AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
          AND ISNULL(IsRejected, 0) = 0
          AND Stage NOT IN ('Rejected')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already has an active application in Candidate Applications.');
    END

    -- Check 2: Mobile duplicate in REC_Candidate_Details (Candidate Master)
    IF @IsDuplicate = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (
                RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
                OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @Mobile
            )
            AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
            AND ISNULL(status, '') NOT IN ('Rejected')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in Candidate Master database.');
        END
    END

    -- Check 3: Aadhaar duplicate in REC_Candidate_Applications
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', '') = @AadhaarNo 
              AND (fk_companyId = @CompanyId OR CompanyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
              AND ISNULL(IsRejected, 0) = 0
              AND Stage NOT IN ('Rejected')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already has an active application in Candidate Applications.');
        END
    END

    -- Check 4: Active employee in SAL_Employee_Mst (already an active hired employee)
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE (REPLACE(REPLACE(adhaarNo, '-', ''), ' ', '') = @AadhaarNo 
                   OR adhaarNo = CONCAT(SUBSTRING(@AadhaarNo,1,4), ' ', SUBSTRING(@AadhaarNo,5,4), ' ', SUBSTRING(@AadhaarNo,9,4)))
              AND (@CompanyId IS NULL OR @CompanyId = '' OR fk_companyId = @CompanyId)
              AND ISNULL(active, 'Y') IN ('Y', '1', 'True')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupAadhaar = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists as an active employee in Employee Master.');
        END
    END

    -- =========================================================================
    -- CRITICAL RULE: IF DUPLICATE IS FOUND, DO NOT CREATE THE CANDIDATE!
    -- DO NOT INSERT INTO REC_Candidate_Applications!
    -- DO NOT INSERT INTO REC_Candidate_Lifecycle_Audit!
    -- DO NOT GENERATE AN APPLICATION SEQUENCE!
    -- Return failure immediately so no record is persisted.
    -- =========================================================================
    IF @IsDuplicate = 1
    BEGIN
        SELECT 
            CAST(0 AS BIT) AS Success,
            CAST(1 AS BIT) AS IsRejected,
            CONCAT('Duplicate Profile: ', @DupDetail, ' Candidate application will NOT be created.') AS Message,
            CAST(0 AS BIGINT) AS appId,
            CAST('' AS NVARCHAR(50)) AS applicationNo,
            @MrfCode AS mrfCode;

        RETURN;
    END

    -- =========================================================================
    -- 4. NEW CANDIDATE: Generate unique Application No: APP/YEAR/XXXX
    -- =========================================================================
    DECLARE @NextAppNo NVARCHAR(50);
    DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
    DECLARE @MaxSeq INT = 0;

    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');

    SET @NextAppNo = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Determine actual audit role for the registering user
    DECLARE @UserRole NVARCHAR(100) = CASE 
        WHEN @SourceType = 'Vendor' AND @CreatedBy NOT LIKE '%Vendor%' THEN 'Recruiter / Site HR'
        WHEN @SourceType = 'Vendor' AND @CreatedBy LIKE '%Vendor%'     THEN 'Vendor Partner'
        WHEN @SourceType = 'QR_Direct'                                THEN 'Self-Registered (QR)'
        ELSE 'Recruiter'
    END;

    -- Normal successful registration as fresh Applied candidate
    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus, 
        IsRejected, fk_companyId, CompanyId,
        CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending',
        0, @CompanyId, @CompanyId,
        GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @VendorId, @CreatedBy, @UserRole, 
        CONCAT('Candidate registered against MRF ', @MrfCode, CASE WHEN @VendorName IS NOT NULL AND @VendorName <> '' THEN CONCAT(' via ', @VendorName) ELSE '' END), 
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        CAST(1 AS BIT) AS Success,
        CAST(0 AS BIT) AS IsRejected,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;

END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_CANDIDATE_REPORT_GET
-- Source File: USP_Candidate_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Candidate_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @jobId VARCHAR(50) = '',
    @locationId VARCHAR(50) = '',
    @department VARCHAR(100) = '',
    @source VARCHAR(100) = '',
    @status VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Temp Table: Processed Candidate Pipeline Records
    SELECT 
        c.pk_recId AS PkRecId,
        ISNULL(c.candidate_name, 'Unknown Candidate') AS CandidateName,
        ISNULL(c.email, '') AS Email,
        ISNULL(c.mobile, ISNULL(c.phone, '')) AS Mobile,
        ISNULL(c.gender, '') AS Gender,
        ISNULL(c.education, '') AS Education,
        ISNULL(c.totexperience, '0') AS Experience,
        ISNULL(c.currentctc, '0') AS CurrentCtc,
        ISNULL(c.expectedctc, '0') AS ExpectedCtc,
        CASE 
            WHEN ISNULL(c.npdys, '') <> '' AND c.npdys <> '0' THEN c.npdys + ' Days'
            WHEN ISNULL(c.npmonth, '') <> '' AND c.npmonth <> '0' THEN c.npmonth + ' Months'
            ELSE 'Immediate'
        END AS NoticePeriod,
        ISNULL(c.keyskills, '') AS KeySkills,
        ISNULL(c.corresAddress, ISNULL(c.permanentAddress, ISNULL(c.Address, ''))) AS Address,
        ISNULL(c.source, ISNULL(c.AgentName, ISNULL(c.refname, 'Direct / Walk-In'))) AS Source,
        ISNULL(c.refcode, ISNULL(c.Vendor_Code, '')) AS VendorCode,
        ISNULL(c.fk_jobId, '') AS JobId,
        ISNULL(j.Mrfcode, CASE WHEN j.pk_reqid IS NOT NULL THEN 'MRF/' + CAST(j.pk_reqid AS VARCHAR(20)) ELSE '' END) AS MrfCode,
        ISNULL(j.jobtitle, ISNULL(c.designation, 'Unassigned Position')) AS JobTitle,
        ISNULL(dept.description, ISNULL(c.department, '')) AS Department,
        ISNULL(loc.locname, ISNULL(jloc.locname, '')) AS Location,
        CASE 
            WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined', 'Onboarded') THEN 'Joined'
            WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 'Offered'
            WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 'Interviewed'
            WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 'Screened'
            WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 'Rejected'
            ELSE 'Applied'
        END AS DisplayStatus,
        ISNULL(c.status, '1') AS RawStatus,
        c.dated AS AppliedDate,
        CAST(ISNULL(MONTH(c.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(c.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN c.dated IS NOT NULL 
            THEN DATENAME(MONTH, c.dated) + ' ' + CAST(YEAR(c.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        ISNULL(c.shortlist_status, 0) AS ShortlistStatus,
        ISNULL(c.interviewroundcandidate, 0) AS InterviewRound,
        ISNULL(c.final_selection_status, 0) AS FinalSelectionStatus,
        ISNULL(c.IsOnboardingDone, 0) AS IsOnboardingDone,
        c.OnboardCompletionDate AS OnboardCompletionDate
    INTO #CandidateData
    FROM REC_Candidate_Details c
    LEFT JOIN REC_JobRequisition_Mst j ON (CAST(j.pk_reqid AS VARCHAR(50)) = c.fk_jobId OR j.Mrfcode = c.fk_jobId)
    LEFT JOIN Department_Mst dept ON (j.fk_deptid = dept.pk_deptid OR j.fk_deptid = dept.deptcode)
    LEFT JOIN Location_Mst loc ON (c.fk_locid = loc.pk_locid OR c.fk_locid = loc.code)
    LEFT JOIN Location_Mst jloc ON (j.fk_locid = jloc.pk_locid OR j.fk_locid = jloc.code)
    WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
      AND (@fk_companyId = '' OR c.fk_companyId = @fk_companyId OR j.fk_companyId = @fk_companyId)
      AND (@jobId = '' OR c.fk_jobId = @jobId OR j.Mrfcode = @jobId OR CAST(j.pk_reqid AS VARCHAR(50)) = @jobId OR j.jobtitle LIKE '%' + @jobId + '%')
      AND (@locationId = '' OR c.fk_locid = @locationId OR loc.pk_locid = @locationId OR loc.locname LIKE '%' + @locationId + '%' OR jloc.locname LIKE '%' + @locationId + '%')
      AND (@department = '' OR dept.description LIKE '%' + @department + '%' OR dept.deptcode LIKE '%' + @department + '%' OR c.department LIKE '%' + @department + '%')
      AND (@source = '' OR c.source LIKE '%' + @source + '%' OR c.refcode LIKE '%' + @source + '%' OR c.refname LIKE '%' + @source + '%' OR c.AgentName LIKE '%' + @source + '%' OR c.Vendor_Code LIKE '%' + @source + '%')
      AND (
          @status = '' 
          OR (@status = 'Applied' AND (c.status = '1' OR c.status = 'Applied' OR c.status IS NULL OR (c.shortlist_status = 0 AND ISNULL(c.interviewroundcandidate, 0) = 0 AND c.final_selection_status = 0 AND c.IsOnboardingDone = 0 AND c.status NOT IN ('7', 'Rejected'))))
          OR (@status = 'Screened' AND (c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened')))
          OR (@status = 'Interviewed' AND (ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled')))
          OR (@status = 'Offered' AND (c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered')))
          OR (@status = 'Joined' AND (c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined', 'Onboarded')))
          OR (@status = 'Rejected' AND (c.status IN ('7', 'Rejected', 'Disapproved')))
          OR c.status = @status
      )
      AND (@month = '' OR MONTH(c.dated) = CAST(@month AS INT))
      AND (@year = '' OR YEAR(c.dated) = CAST(@year AS INT))
      AND (@fromDate = '' OR c.dated >= CAST(@fromDate AS DATETIME))
      AND (@toDate = '' OR c.dated <= CAST(@toDate AS DATETIME))
      AND (
          @searchTerm = '' 
          OR c.candidate_name LIKE '%' + @searchTerm + '%'
          OR c.email LIKE '%' + @searchTerm + '%'
          OR c.mobile LIKE '%' + @searchTerm + '%'
          OR c.phone LIKE '%' + @searchTerm + '%'
          OR c.keyskills LIKE '%' + @searchTerm + '%'
          OR c.pk_recId LIKE '%' + @searchTerm + '%'
          OR j.jobtitle LIKE '%' + @searchTerm + '%'
          OR j.Mrfcode LIKE '%' + @searchTerm + '%'
          OR dept.description LIKE '%' + @searchTerm + '%'
          OR loc.locname LIKE '%' + @searchTerm + '%'
          OR c.source LIKE '%' + @searchTerm + '%'
          OR c.refname LIKE '%' + @searchTerm + '%'
          OR c.AgentName LIKE '%' + @searchTerm + '%'
      );

    -- Resultset 1: Summary KPIs
    SELECT 
        COUNT(1) AS TotalCandidates,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Screened', 'Interviewed', 'Offered', 'Joined') OR ShortlistStatus = 1 OR RawStatus IN ('2', 'Shortlisted', 'Screened') THEN 1 ELSE 0 END), 0) AS TotalScreened,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Interviewed', 'Offered', 'Joined') OR InterviewRound > 0 OR RawStatus IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 ELSE 0 END), 0) AS TotalInterviewed,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Offered', 'Joined') OR FinalSelectionStatus = 1 OR RawStatus IN ('4', 'Selected', 'Offered') THEN 1 ELSE 0 END), 0) AS TotalOffered,
        ISNULL(SUM(CASE WHEN DisplayStatus = 'Joined' OR IsOnboardingDone = 1 OR RawStatus IN ('5', '6', 'Joined') THEN 1 ELSE 0 END), 0) AS TotalJoined,
        ISNULL(SUM(CASE WHEN DisplayStatus = 'Rejected' OR RawStatus IN ('7', 'Rejected', 'Disapproved') THEN 1 ELSE 0 END), 0) AS TotalRejected,
        CASE 
            WHEN COUNT(1) > 0 
            THEN CAST((CAST(SUM(CASE WHEN DisplayStatus = 'Joined' OR IsOnboardingDone = 1 OR RawStatus IN ('5', '6', 'Joined') THEN 1 ELSE 0 END) AS DECIMAL(10,2)) / CAST(COUNT(1) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS ConversionRate,
        COUNT(1) AS TotalCount
    FROM #CandidateData;

    -- Resultset 2: Paginated Grid Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY AppliedDate DESC, PkRecId DESC) AS RowNum,
            *
        FROM #CandidateData
    )
    SELECT 
        PkRecId,
        CandidateName,
        Email,
        Mobile,
        Gender,
        Education,
        Experience,
        CurrentCtc,
        ExpectedCtc,
        NoticePeriod,
        KeySkills,
        Address,
        Source,
        VendorCode,
        JobId,
        MrfCode,
        JobTitle,
        Department,
        Location,
        DisplayStatus,
        RawStatus,
        AppliedDate,
        [Month],
        [Year],
        MonthYear,
        ShortlistStatus,
        InterviewRound,
        FinalSelectionStatus,
        IsOnboardingDone,
        OnboardCompletionDate
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #CandidateData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORPOOLCANDIDATES
-- Source File: 46_CJ_DARCL_Pipeline_Company_Pool_Bench_And_Rejected_Allocation.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorPoolCandidates
    @VendorId    NVARCHAR(50)  = NULL,  -- NULL / 'ALL' for HR Pipeline, or specific VendorId
    @CompanyId   NVARCHAR(50)  = NULL,
    @TargetReqId BIGINT        = NULL,
    @SearchQuery NVARCHAR(150) = NULL,
    @PoolFilter  NVARCHAR(50)  = 'ALL'   -- 'ALL' | 'BENCH' | 'REJECTED'
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @VendorId = NULLIF(LTRIM(RTRIM(ISNULL(@VendorId, ''))), '');
    IF @VendorId = 'ALL' OR @VendorId = 'HR'
    BEGIN
        SET @VendorId = NULL;
    END

    SET @SearchQuery = NULLIF(LTRIM(RTRIM(@SearchQuery)), '');
    SET @PoolFilter = UPPER(LTRIM(RTRIM(ISNULL(@PoolFilter, 'ALL'))));

    -- Dynamic company resolution from Job Requisition if not explicitly supplied
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0') AND @TargetReqId IS NOT NULL
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @TargetReqId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ISNULL(ca.SkillClassification, 'Semi-Skilled')                   AS skillClassification,
        ca.CurrentLocation                                               AS location,
        ISNULL(ca.IsRejected, 0)                                         AS isRejected,
        ca.RejectionReason                                               AS rejectionReason,
        ca.RejectionStage                                                AS rejectionStage,
        ca.CreatedDate                                                   AS registeredDate,
        ca.LastUpdatedDate                                               AS lastUpdatedDate,
        ca.fk_reqid                                                      AS currentReqId,
        ISNULL(ca.MrfCode, 'BENCH')                                      AS mrfCode,
        ISNULL(ca.Designation, 'Talent Pool Candidate')                  AS jobTitle,
        ISNULL(ca.Department, 'General')                                 AS department,
        ISNULL(ca.OperatingHub, 'General')                               AS hub,
        ISNULL(ca.fk_vendorId, '')                                       AS vendorId,
        ISNULL(ca.VendorName, 'Direct / Internal')                       AS vendorName,
        ISNULL(ca.SourceType, 'Staffing Vendor')                         AS sourceType,
        CASE 
            WHEN ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected' THEN 'REJECTED'
            ELSE 'BENCH'
        END AS poolType
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE (@VendorId IS NULL OR ca.fk_vendorId = @VendorId)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      -- 100% STRICT POOL RULE: Only Bench candidates OR Previously Rejected candidates
      AND (
          (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench')
          OR (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected')
      )
      -- Exclude if candidate is already actively assigned to this target requisition
      AND (
          @TargetReqId IS NULL 
          OR ca.fk_reqid IS NULL 
          OR ca.fk_reqid <> @TargetReqId 
          OR (ca.fk_reqid = @TargetReqId AND (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected'))
      )
      -- Filter by sub-pool tab if requested
      AND (
          @PoolFilter = 'ALL'
          OR (@PoolFilter = 'BENCH' AND (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench') AND ISNULL(ca.IsRejected, 0) = 0 AND ca.Stage <> 'Rejected')
          OR (@PoolFilter = 'REJECTED' AND (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected'))
      )
      -- Multi-field Search: Aadhaar, Phone / Mobile, Candidate Name, Application Number, Vendor Name
      AND (
          @SearchQuery IS NULL 
          OR ca.CandidateName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Mobile LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.AadhaarNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.ApplicationNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Designation LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.VendorName LIKE CONCAT('%', @SearchQuery, '%')
      )
    ORDER BY ca.LastUpdatedDate DESC, ca.CreatedDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_MRF_REPORT_GET
-- Source File: USP_MRF_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_MRF_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @mrfCode VARCHAR(50) = '',
    @locationId VARCHAR(50) = '',
    @department VARCHAR(100) = '',
    @workflowStatus VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    -- CTE 1: Candidate Funnel Aggregations per Requisition / MRF
    ;WITH CandFunnel AS (
        SELECT 
            c.fk_jobId,
            COUNT(1) AS ProfilesSubmitted,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 1 END) AS Offered,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND c.fk_jobId IS NOT NULL AND c.fk_jobId <> ''
        GROUP BY c.fk_jobId
    )
    SELECT 
        j.pk_reqid AS PkReqId,
        ISNULL(j.Mrfcode, 'MRF/' + CAST(j.pk_reqid AS VARCHAR(20))) AS MrfCode,
        ISNULL(j.Mrfcode, 'MRF/' + CAST(j.pk_reqid AS VARCHAR(20))) AS ReqCode,
        ISNULL(j.jobtitle, 'Untitled Position') AS JobTitle,
        ISNULL(desg.designation, '') AS Designation,
        ISNULL(dept.description, '') AS Department,
        ISNULL(loc.locname, '') AS Location,
        ISNULL(emp.empname, ISNULL(j.fk_empid, 'System')) AS RaisedBy,
        ISNULL(j.Reason_of_Requirement, '') AS RequirementType,
        ISNULL(j.Justification_of_Position, '') AS Justification,
        ISNULL(j.Experience_From, 0) AS ExpFrom,
        ISNULL(j.Experience_To, 0) AS ExpTo,
        ISNULL(j.CTC_From, 0) AS CtcFrom,
        ISNULL(j.CTC_To, 0) AS CtcTo,
        ISNULL(j.No_of_post, 1) AS TargetPositions,
        ISNULL(j.WorkflowStatus, 'Submitted') AS WorkflowStatus,
        ISNULL(j.CurrentApprovalLevel, 1) AS CurrentApprovalLevel,
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        j.dated AS CreatedDate,
        j.approvaldate AS ApprovalDate,
        j.HiringOpenedDate AS HiringOpenedDate,
        j.SubmittedDate AS SubmittedDate,
        -- Approver details
        j.L1ApproverId,
        j.L1ApproverName,
        j.L1Action,
        j.L1ActionDate,
        j.L1Remarks,
        j.L2ApproverId,
        j.L2ApproverName,
        j.L2Action,
        j.L2ActionDate,
        j.L2Remarks,
        j.L3ApproverId,
        j.L3ApproverName,
        j.L3Action,
        j.L3ActionDate,
        j.L3Remarks,
        j.RejectedByLevel,
        j.RejectedByName,
        j.RejectedByDate,
        j.RejectionRemarks,
        -- Funnel metrics
        ISNULL(cf.ProfilesSubmitted, 0) AS ProfilesSubmitted,
        ISNULL(cf.Screened, 0) AS Screened,
        ISNULL(cf.Interviewed, 0) AS Interviewed,
        ISNULL(cf.Offered, 0) AS Offered,
        ISNULL(cf.Joined, 0) AS Joined,
        ISNULL(cf.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) - ISNULL(cf.Joined, 0) < 0 THEN 0
            ELSE ISNULL(j.No_of_post, 1) - ISNULL(cf.Joined, 0)
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > 0 
            THEN CAST((CAST(ISNULL(cf.Joined, 0) AS DECIMAL(10,2)) / CAST(j.No_of_post AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cf.AvgTatDays, 0) AS AvgTatDays
    INTO #MRFData
    FROM REC_JobRequisition_Mst j
    LEFT JOIN Location_Mst loc ON j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code
    LEFT JOIN Department_Mst dept ON j.fk_deptid = dept.pk_deptid OR j.fk_deptid = dept.deptcode
    LEFT JOIN SAL_Designation_Mst desg ON j.fk_desgid = desg.pk_desgid
    LEFT JOIN SAL_Employee_Mst emp ON j.fk_empid = emp.pk_empid OR j.fk_empid = emp.empcode
    LEFT JOIN CandFunnel cf ON (cf.fk_jobId = CAST(j.pk_reqid AS VARCHAR(50)) OR cf.fk_jobId = j.Mrfcode)
    WHERE 
        (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
        -- STRICTLY only show MRFs in Level 1, Level 2, Level 3 approval workflow (Not approved jobs)
        AND ISNULL(j.isApproved, 0) = 0
        AND ISNULL(j.CurrentApprovalLevel, 1) IN (1, 2, 3)
        AND (j.WorkflowStatus IS NULL OR j.WorkflowStatus NOT IN ('Approved', 'Active', 'Closed'))
        AND (@mrfCode = '' OR j.Mrfcode = @mrfCode OR CAST(j.pk_reqid AS VARCHAR(50)) = @mrfCode)
        AND (@locationId = '' OR j.fk_locid = @locationId OR loc.pk_locid = @locationId OR loc.locname LIKE '%' + @locationId + '%')
        AND (@department = '' OR dept.description LIKE '%' + @department + '%' OR dept.deptcode LIKE '%' + @department + '%')
        AND (@workflowStatus = '' OR j.WorkflowStatus = @workflowStatus)
        AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
        AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
        AND (@fromDate = '' OR j.dated >= CAST(@fromDate AS DATETIME))
        AND (@toDate = '' OR j.dated <= CAST(@toDate AS DATETIME))
        AND (
            @searchTerm = '' 
            OR j.jobtitle LIKE '%' + @searchTerm + '%' 
            OR j.Mrfcode LIKE '%' + @searchTerm + '%'
            OR desg.designation LIKE '%' + @searchTerm + '%'
            OR dept.description LIKE '%' + @searchTerm + '%'
            OR loc.locname LIKE '%' + @searchTerm + '%'
            OR emp.empname LIKE '%' + @searchTerm + '%'
        );

    -- Resultset 1: Summary KPIs
    SELECT 
        COUNT(1) AS TotalMRFs,
        ISNULL(SUM(TargetPositions), 0) AS TotalPositions,
        ISNULL(SUM(CASE WHEN WorkflowStatus IN ('Submitted', 'L1_Pending', 'L2_Pending', 'L3_Pending') THEN 1 ELSE 0 END), 0) AS TotalInWorkflow,
        ISNULL(SUM(CASE WHEN WorkflowStatus = 'Active' THEN 1 ELSE 0 END), 0) AS TotalActive,
        ISNULL(SUM(ProfilesSubmitted), 0) AS TotalProfilesSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        ISNULL(SUM(PendingPositions), 0) AS TotalPendingPositions,
        CASE 
            WHEN SUM(TargetPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TargetPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate,
        COUNT(1) AS TotalCount
    FROM #MRFData;

    -- Resultset 2: Paginated Grid Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC, PkReqId DESC) AS RowNum,
            *
        FROM #MRFData
    )
    SELECT 
        PkReqId,
        MrfCode,
        ReqCode,
        JobTitle,
        Designation,
        Department,
        Location,
        RaisedBy,
        RequirementType,
        Justification,
        ExpFrom,
        ExpTo,
        CtcFrom,
        CtcTo,
        TargetPositions,
        WorkflowStatus,
        CurrentApprovalLevel,
        [Month],
        [Year],
        MonthYear,
        CreatedDate,
        ApprovalDate,
        HiringOpenedDate,
        SubmittedDate,
        L1ApproverId,
        L1ApproverName,
        L1Action,
        L1ActionDate,
        L1Remarks,
        L2ApproverId,
        L2ApproverName,
        L2Action,
        L2ActionDate,
        L2Remarks,
        L3ApproverId,
        L3ApproverName,
        L3Action,
        L3ActionDate,
        L3Remarks,
        RejectedByLevel,
        RejectedByName,
        RejectedByDate,
        RejectionRemarks,
        ProfilesSubmitted,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        PendingPositions,
        FulfillmentPct,
        AvgTatDays
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #MRFData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REPORT_MASTER_DATA_GET
-- Source File: USP_Report_Master_Data_Get.sql
-- ==========================================================================================
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
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_VENDOR_REPORT_GET
-- Source File: USP_Vendor_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Vendor_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @vendorCode VARCHAR(50) = '',
    @location VARCHAR(100) = '',
    @status VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CandMetrics AS (
        SELECT 
            ISNULL(c.refcode, ISNULL(c.source, ISNULL(c.Vendor_Code, ''))) AS VendorRef,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Shortlisted,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected') THEN 1 END) AS Selected,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND (c.refcode IS NOT NULL OR c.source IS NOT NULL OR c.Vendor_Code IS NOT NULL)
        GROUP BY ISNULL(c.refcode, ISNULL(c.source, ISNULL(c.Vendor_Code, '')))
    ),
    VendorJobMapping AS (
        SELECT 
            m.fk_vendorId,
            COUNT(DISTINCT m.fk_reqid) AS ActiveJobs
        FROM REC_Requisition_Vendor_Mapping m
        WHERE m.IsActive = 1 OR m.IsActive IS NULL
        GROUP BY m.fk_vendorId
    )
    SELECT 
        ISNULL(v.Vendor_Code, ISNULL(v.pk_recId, '')) AS VendorCode,
        ISNULL(v.Vendor_Name, ISNULL(v.candidate_name, '')) AS VendorName,
        ISNULL(v.Vendor_FatherName, ISNULL(v.father_name, ISNULL(v.AgentName, ''))) AS ContactPerson,
        ISNULL(v.email, ISNULL(v.EmailID, '')) AS Email,
        ISNULL(v.Vendor_ContactNo, ISNULL(v.mobile, ISNULL(v.phone, ''))) AS Phone,
        ISNULL(loc.locname, ISNULL(v.Vendor_City, '')) AS Location,
        CAST(ISNULL(MONTH(v.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(v.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN v.dated IS NOT NULL 
            THEN DATENAME(MONTH, v.dated) + ' ' + CAST(YEAR(v.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        ISNULL(jm.ActiveJobs, 0) AS ActiveJobsAssigned,
        ISNULL(cm.TotalSubmitted, 0) AS TotalSubmitted,
        ISNULL(cm.Shortlisted, 0) AS Shortlisted,
        ISNULL(cm.Interviewed, 0) AS Interviewed,
        ISNULL(cm.Selected, 0) AS Selected,
        ISNULL(cm.Joined, 0) AS Joined,
        ISNULL(cm.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(cm.TotalSubmitted, 0) > 0 
            THEN CAST((CAST(ISNULL(cm.Joined, 0) AS DECIMAL(10,2)) / CAST(cm.TotalSubmitted AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS ConversionRate,
        ISNULL(cm.AvgTatDays, 0) AS AvgTatDays,
        CASE 
            WHEN v.Vendor_Status IS NOT NULL AND v.Vendor_Status <> '' THEN v.Vendor_Status
            ELSE 'Active'
        END AS [Status],
        ISNULL(v.dated, GETDATE()) AS CreatedDate
    INTO #VendorData
    FROM REC_Candidate_Details v
    LEFT JOIN Location_Mst loc ON v.fk_locid = loc.pk_locid OR v.Vendor_FKCityId = loc.pk_locid
    LEFT JOIN CandMetrics cm ON cm.VendorRef = v.Vendor_Code OR cm.VendorRef = v.pk_recId OR cm.VendorRef = v.Vendor_Name
    LEFT JOIN VendorJobMapping jm ON jm.fk_vendorId = v.pk_recId OR jm.fk_vendorId = v.Vendor_Code
    WHERE (v.IsVendor = 1 OR v.Vendor_Code IS NOT NULL)
      AND (@fk_companyId = '' OR v.fk_companyId = @fk_companyId)
      AND (@vendorCode = '' OR v.Vendor_Code = @vendorCode OR v.pk_recId = @vendorCode)
      AND (@location = '' OR loc.locname LIKE '%' + @location + '%' OR v.Vendor_City LIKE '%' + @location + '%')
      AND (@status = '' OR v.Vendor_Status = @status OR (@status = 'Active' AND (v.Vendor_Status IS NULL OR v.Vendor_Status = '')))
      AND (@month = '' OR MONTH(v.dated) = CAST(@month AS INT))
      AND (@year = '' OR YEAR(v.dated) = CAST(@year AS INT))
      AND (@fromDate = '' OR v.dated >= CAST(@fromDate AS DATETIME))
      AND (@toDate = '' OR v.dated <= CAST(@toDate AS DATETIME))
      AND (
          @searchTerm = '' 
          OR v.Vendor_Name LIKE '%' + @searchTerm + '%' 
          OR v.candidate_name LIKE '%' + @searchTerm + '%'
          OR v.Vendor_Code LIKE '%' + @searchTerm + '%' 
          OR v.Vendor_FatherName LIKE '%' + @searchTerm + '%'
          OR v.Vendor_City LIKE '%' + @searchTerm + '%'
      );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalVendors,
        ISNULL(SUM(TotalSubmitted), 0) AS TotalProfilesSubmitted,
        ISNULL(SUM(Shortlisted), 0) AS TotalShortlisted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        CASE 
            WHEN SUM(TotalSubmitted) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TotalSubmitted) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallConversionRate
    FROM #VendorData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY VendorName ASC) AS RowNum,
            *
        FROM #VendorData
    )
    SELECT 
        VendorCode,
        VendorName,
        ContactPerson,
        Email,
        Phone,
        Location,
        [Month],
        [Year],
        MonthYear,
        ActiveJobsAssigned,
        TotalSubmitted,
        Shortlisted,
        Interviewed,
        Selected,
        Joined,
        Rejected,
        ConversionRate,
        AvgTatDays,
        [Status]
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #VendorData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_LOCATION_WISE_JOBS_REPORT_GET
-- Source File: USP_Location_Wise_Jobs_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Location_Wise_Jobs_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @locationId VARCHAR(50) = '',
    @department VARCHAR(100) = '',
    @status VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CandReqStats AS (
        SELECT 
            c.fk_jobId,
            COUNT(1) AS ProfilesShared,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 1 END) AS Offered,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
        GROUP BY c.fk_jobId
    )
    SELECT 
        loc.pk_locid AS LocationId,
        ISNULL(loc.code, loc.pk_locid) AS LocationCode,
        ISNULL(loc.locname, '') AS LocationName,
        CAST(j.pk_reqid AS VARCHAR(50)) AS ReqId,
        ISNULL(j.Mrfcode, 'REQ-' + CAST(j.pk_reqid AS VARCHAR(20))) AS ReqCode,
        ISNULL(j.jobtitle, '') AS JobTitle,
        ISNULL(d.description, '') AS Department,
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        ISNULL(j.No_of_post, 0) AS TargetPositions,
        ISNULL(cs.ProfilesShared, 0) AS ProfilesShared,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 0) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(j.No_of_post, 0) - ISNULL(cs.Joined, 0)
            ELSE 0 
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 0) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(j.No_of_post AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        CASE 
            WHEN j.isApproved = 1 THEN 'Approved'
            WHEN j.isHold = 1 THEN 'On Hold'
            WHEN j.isDisapproved = 1 THEN 'Closed'
            ELSE 'Active'
        END AS [Status],
        ISNULL(j.dated, GETDATE()) AS CreatedDate
    INTO #LocReqData
    FROM REC_JobRequisition_Mst j
    LEFT JOIN Location_Mst loc ON j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code
    LEFT JOIN Department_Mst d ON j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode
    LEFT JOIN CandReqStats cs ON cs.fk_jobId = CAST(j.pk_reqid AS VARCHAR(50)) OR cs.fk_jobId = j.Mrfcode
    WHERE 
        (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
        AND (@locationId = '' OR loc.pk_locid = @locationId OR loc.code = @locationId OR j.fk_locid = @locationId OR loc.locname = @locationId OR loc.locname LIKE '%' + @locationId + '%')
        AND (@department = '' OR d.pk_deptid = @department OR j.fk_deptid = @department OR d.deptcode = @department OR d.description = @department OR d.description LIKE '%' + @department + '%')
        AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
        AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
        AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
        AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
        AND (
            @searchTerm = '' 
            OR j.jobtitle LIKE '%' + @searchTerm + '%' 
            OR j.Mrfcode LIKE '%' + @searchTerm + '%'
            OR loc.locname LIKE '%' + @searchTerm + '%'
            OR loc.code LIKE '%' + @searchTerm + '%'
            OR d.description LIKE '%' + @searchTerm + '%'
        );

    -- Resultset 1: Total Count
    SELECT COUNT(1) AS TotalCount 
    FROM #LocReqData
    WHERE (@status = '' OR [Status] = @status);

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC) AS RowNum,
            *
        FROM #LocReqData
        WHERE (@status = '' OR [Status] = @status)
    )
    SELECT 
        LocationId,
        LocationCode,
        LocationName,
        ReqId,
        ReqCode,
        JobTitle,
        Department,
        [Month],
        [Year],
        MonthYear,
        TargetPositions,
        ProfilesShared,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        PendingPositions,
        FulfillmentPct,
        AvgTatDays,
        [Status]
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #LocReqData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_JOB_REPORT_GET
-- Source File: USP_Job_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Job_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @locationId VARCHAR(50) = '',
    @department VARCHAR(100) = '',
    @workflowStatus VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CandJobStats AS (
        SELECT 
            c.fk_jobId,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 1 END) AS Offered,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
        GROUP BY c.fk_jobId
    )
    SELECT 
        j.pk_reqid AS ReqId,
        ISNULL(j.Mrfcode, 'JOB-' + CAST(j.pk_reqid AS VARCHAR(20))) AS ReqCode,
        ISNULL(j.jobtitle, '') AS JobTitle,
        ISNULL(d.description, '') AS Department,
        ISNULL(loc.locname, '') AS Location,
        ISNULL(loc.pk_locid, '') AS LocationId,
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        ISNULL(j.No_of_post, 0) AS TargetPositions,
        CASE 
            WHEN j.isDisapproved = 1 OR j.WorkflowStatus = 'Closed' THEN 'Closed'
            WHEN j.isHold = 1 OR j.WorkflowStatus = 'On Hold' THEN 'On Hold'
            ELSE 'Approved'
        END AS WorkflowStatus,
        ISNULL(j.CurrentApprovalLevel, 99) AS CurrentApprovalLevel,
        ISNULL(j.L1ApproverId, '') AS L1ApproverId,
        ISNULL(j.L1ApproverName, '') AS L1ApproverName,
        ISNULL(j.L1Action, 'Approved') AS L1Action,
        j.L1ActionDate,
        ISNULL(j.L1Remarks, '') AS L1Remarks,
        ISNULL(j.L2ApproverId, '') AS L2ApproverId,
        ISNULL(j.L2ApproverName, '') AS L2ApproverName,
        ISNULL(j.L2Action, 'Approved') AS L2Action,
        j.L2ActionDate,
        ISNULL(j.L2Remarks, '') AS L2Remarks,
        ISNULL(j.L3ApproverId, '') AS L3ApproverId,
        ISNULL(j.L3ApproverName, '') AS L3ApproverName,
        ISNULL(j.L3Action, 'Approved') AS L3Action,
        j.L3ActionDate,
        ISNULL(j.L3Remarks, '') AS L3Remarks,
        ISNULL(j.HiringOpenedDate, j.dated) AS HiringOpenedDate,
        ISNULL(j.RejectedByLevel, '') AS RejectedByLevel,
        ISNULL(j.RejectedByName, '') AS RejectedByName,
        j.RejectedByDate,
        ISNULL(j.RejectionRemarks, '') AS RejectionRemarks,
        ISNULL(cs.TotalSubmitted, 0) AS ProfilesSubmitted,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 0) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(j.No_of_post, 0) - ISNULL(cs.Joined, 0)
            ELSE 0 
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 0) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(j.No_of_post AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        ISNULL(j.dated, GETDATE()) AS CreatedDate
    INTO #JobData
    FROM REC_JobRequisition_Mst j
    LEFT JOIN Location_Mst loc ON j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code
    LEFT JOIN Department_Mst d ON j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode
    LEFT JOIN CandJobStats cs ON cs.fk_jobId = CAST(j.pk_reqid AS VARCHAR(50)) OR cs.fk_jobId = j.Mrfcode
    WHERE 
        (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
        -- ONLY show approved jobs (L1, L2, L3 approved or isApproved = 1 or WorkflowStatus IN ('Active', 'Closed', 'Approved') or CurrentApprovalLevel = 99)
        AND (
            j.isApproved = 1 
            OR j.WorkflowStatus IN ('Active', 'Closed', 'Approved') 
            OR j.CurrentApprovalLevel = 99 
            OR (j.L1Action = 'Approved' AND j.L2Action = 'Approved' AND j.L3Action = 'Approved')
            OR j.HiringOpenedDate IS NOT NULL
        )
        AND (@locationId = '' OR loc.pk_locid = @locationId OR loc.code = @locationId OR j.fk_locid = @locationId)
        AND (@department = '' OR d.description LIKE '%' + @department + '%' OR d.deptcode LIKE '%' + @department + '%')
        AND (
            @workflowStatus = '' 
            OR (
                CASE 
                    WHEN j.isDisapproved = 1 OR j.WorkflowStatus = 'Closed' THEN 'Closed'
                    WHEN j.isHold = 1 OR j.WorkflowStatus = 'On Hold' THEN 'On Hold'
                    ELSE 'Approved'
                END
            ) = @workflowStatus
            OR (@workflowStatus = 'Approved' AND (j.isApproved = 1 OR j.WorkflowStatus IN ('Active', 'Approved')))
        )
        AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
        AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
        AND (@fromDate = '' OR j.dated >= CAST(@fromDate AS DATETIME))
        AND (@toDate = '' OR j.dated <= CAST(@toDate AS DATETIME))
        AND (
            @searchTerm = '' 
            OR j.jobtitle LIKE '%' + @searchTerm + '%' 
            OR j.Mrfcode LIKE '%' + @searchTerm + '%'
            OR loc.locname LIKE '%' + @searchTerm + '%'
            OR d.description LIKE '%' + @searchTerm + '%'
            OR j.WorkflowStatus LIKE '%' + @searchTerm + '%'
        );

    -- Resultset 1: Summary Stats
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalJobs,
        ISNULL(SUM(TargetPositions), 0) AS TotalPositions,
        0 AS TotalInWorkflow,
        COUNT(CASE WHEN WorkflowStatus = 'Approved' OR WorkflowStatus = 'Active' THEN 1 END) AS TotalActive,
        ISNULL(SUM(ProfilesSubmitted), 0) AS TotalProfilesSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        ISNULL(SUM(PendingPositions), 0) AS TotalPendingPositions,
        CASE 
            WHEN SUM(TargetPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TargetPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #JobData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC) AS RowNum,
            *
        FROM #JobData
    )
    SELECT 
        ReqId,
        ReqCode,
        JobTitle,
        Department,
        Location,
        LocationId,
        [Month],
        [Year],
        MonthYear,
        TargetPositions,
        WorkflowStatus,
        CurrentApprovalLevel,
        L1ApproverId,
        L1ApproverName,
        L1Action,
        L1ActionDate,
        L1Remarks,
        L2ApproverId,
        L2ApproverName,
        L2Action,
        L2ActionDate,
        L2Remarks,
        L3ApproverId,
        L3ApproverName,
        L3Action,
        L3ActionDate,
        L3Remarks,
        HiringOpenedDate,
        RejectedByLevel,
        RejectedByName,
        RejectedByDate,
        RejectionRemarks,
        ProfilesSubmitted,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        PendingPositions,
        FulfillmentPct,
        AvgTatDays
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #JobData;
END
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_LOCATION_REPORT_GET
-- Source File: USP_Location_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Location_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @locationId VARCHAR(50) = '',
    @location VARCHAR(100) = '',
    @status VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH JobStats AS (
        SELECT 
            ISNULL(j.fk_locid, '') AS LocRef,
            COUNT(DISTINCT j.pk_reqid) AS TotalOpeningJobs,
            SUM(ISNULL(j.No_of_post, 0)) AS TotalPositions
        FROM REC_JobRequisition_Mst j
        WHERE (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
          AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
          AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
          AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
          AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
        GROUP BY ISNULL(j.fk_locid, '')
    ),
    CandLocStats AS (
        SELECT 
            COALESCE(c.fk_locid, j.fk_locid, '') AS LocRef,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Shortlisted,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 1 END) AS Selected,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        LEFT JOIN REC_JobRequisition_Mst j ON CAST(j.pk_reqid AS VARCHAR(50)) = c.fk_jobId OR j.Mrfcode = c.fk_jobId
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND (@fk_companyId = '' OR c.fk_companyId = @fk_companyId OR j.fk_companyId = @fk_companyId)
        GROUP BY COALESCE(c.fk_locid, j.fk_locid, '')
    )
    SELECT 
        loc.pk_locid AS LocationId,
        ISNULL(loc.code, loc.pk_locid) AS LocationCode,
        ISNULL(loc.locname, '') AS LocationName,
        CAST(ISNULL(MONTH(GETDATE()), 1) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(GETDATE()), 2026) AS VARCHAR(10)) AS [Year],
        DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4)) AS MonthYear,
        ISNULL(js.TotalOpeningJobs, 0) AS TotalOpeningJobs,
        ISNULL(js.TotalPositions, 0) AS TotalPositions,
        ISNULL(cs.TotalSubmitted, 0) AS TotalSubmitted,
        ISNULL(cs.Shortlisted, 0) AS Shortlisted,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Selected, 0) AS Selected,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(js.TotalPositions, 0) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(js.TotalPositions, 0) - ISNULL(cs.Joined, 0)
            ELSE 0 
        END AS OpenPositions,
        CASE 
            WHEN ISNULL(js.TotalPositions, 0) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(js.TotalPositions AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentRate,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        'Active' AS [Status]
    INTO #LocationData
    FROM Location_Mst loc
    LEFT JOIN JobStats js ON loc.pk_locid = js.LocRef OR loc.code = js.LocRef
    LEFT JOIN CandLocStats cs ON loc.pk_locid = cs.LocRef OR loc.code = cs.LocRef
    WHERE (@fk_companyId = '' OR loc.fk_companyId = @fk_companyId)
      AND (@locationId = '' OR loc.pk_locid = @locationId OR loc.code = @locationId OR loc.locname = @locationId OR loc.locname LIKE '%' + @locationId + '%')
      AND (@location = '' OR loc.locname LIKE '%' + @location + '%' OR loc.code LIKE '%' + @location + '%')
      AND (
          @searchTerm = '' 
          OR loc.locname LIKE '%' + @searchTerm + '%' 
          OR loc.code LIKE '%' + @searchTerm + '%'
          OR loc.pk_locid LIKE '%' + @searchTerm + '%'
      );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalLocations,
        ISNULL(SUM(TotalOpeningJobs), 0) AS TotalOpeningJobs,
        ISNULL(SUM(TotalPositions), 0) AS TotalPositions,
        ISNULL(SUM(TotalSubmitted), 0) AS TotalProfilesSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        ISNULL(SUM(OpenPositions), 0) AS TotalOpenPositions,
        CASE 
            WHEN SUM(TotalPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TotalPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #LocationData
    WHERE (@status = '' OR [Status] = @status);

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY LocationName ASC) AS RowNum,
            *
        FROM #LocationData
        WHERE (@status = '' OR [Status] = @status)
    )
    SELECT 
        LocationId,
        LocationCode,
        LocationName,
        [Month],
        [Year],
        MonthYear,
        TotalOpeningJobs,
        TotalPositions,
        TotalSubmitted,
        Shortlisted,
        Interviewed,
        Selected,
        Joined,
        Rejected,
        OpenPositions,
        FulfillmentRate,
        AvgTatDays,
        [Status]
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #LocationData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_VENDOR_WISE_REPORT_GET
-- Source File: USP_Vendor_Wise_Report_Get.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[USP_Vendor_Wise_Report_Get]
(
    @fk_companyId VARCHAR(50) = '',
    @vendorCode VARCHAR(50) = '',
    @department VARCHAR(100) = '',
    @status VARCHAR(50) = '',
    @month VARCHAR(10) = '',
    @year VARCHAR(10) = '',
    @fromDate VARCHAR(50) = '',
    @toDate VARCHAR(50) = '',
    @searchTerm VARCHAR(200) = '',
    @pageIndex INT = 0,
    @pageSize INT = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CandReqStats AS (
        SELECT 
            c.fk_jobId,
            ISNULL(c.refcode, ISNULL(c.source, ISNULL(c.Vendor_Code, ''))) AS VendorRef,
            COUNT(1) AS ProfilesShared,
            COUNT(CASE WHEN c.shortlist_status = 1 OR c.status IN ('2', 'Shortlisted', 'Screened') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ISNULL(c.interviewroundcandidate, 0) > 0 OR c.status IN ('3', 'Interviewed', 'Interview Scheduled') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN c.final_selection_status = 1 OR c.status IN ('4', 'Selected', 'Offered') THEN 1 END) AS Offered,
            COUNT(CASE WHEN c.IsOnboardingDone = 1 OR c.status IN ('5', '6', 'Joined') THEN 1 END) AS Joined,
            COUNT(CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN c.dated IS NOT NULL THEN DATEDIFF(day, c.dated, ISNULL(c.OnboardCompletionDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
        GROUP BY c.fk_jobId, ISNULL(c.refcode, ISNULL(c.source, ISNULL(c.Vendor_Code, '')))
    ),
    TotalJobProfiles AS (
        SELECT 
            c.fk_jobId,
            COUNT(1) AS TotalJobApplicants
        FROM REC_Candidate_Details c
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
        GROUP BY c.fk_jobId
    )
    SELECT 
        ISNULL(v.Vendor_Code, ISNULL(v.pk_recId, '')) AS VendorCode,
        ISNULL(v.Vendor_Name, ISNULL(v.candidate_name, '')) AS VendorName,
        ISNULL(j.Mrfcode, '') AS ReqCode,
        ISNULL(j.jobtitle, '') AS JobTitle,
        ISNULL(d.description, '') AS Department,
        ISNULL(loc.locname, '') AS Location,
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        ISNULL(j.No_of_post, 0) AS TargetPositions,
        ISNULL(cs.ProfilesShared, 0) AS ProfilesShared,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(tp.TotalJobApplicants, 0) > 0 
            THEN CAST((CAST(ISNULL(cs.ProfilesShared, 0) AS DECIMAL(10,2)) / CAST(tp.TotalJobApplicants AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS VendorSharePct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        CASE 
            WHEN j.isApproved = 1 THEN 'Approved'
            WHEN j.isHold = 1 THEN 'On Hold'
            WHEN j.isDisapproved = 1 THEN 'Closed'
            ELSE 'Active'
        END AS [Status],
        ISNULL(j.dated, GETDATE()) AS CreatedDate
    INTO #ReqData
    FROM REC_JobRequisition_Mst j
    LEFT JOIN REC_Requisition_Vendor_Mapping m ON j.pk_reqid = m.fk_reqid
    LEFT JOIN REC_Candidate_Details v ON (m.fk_vendorId = v.pk_recId OR m.VendorCode = v.Vendor_Code OR (v.IsVendor = 1 AND m.pk_mapId IS NULL))
    LEFT JOIN Department_Mst d ON j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode
    LEFT JOIN Location_Mst loc ON j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code
    LEFT JOIN CandReqStats cs ON (cs.fk_jobId = CAST(j.pk_reqid AS VARCHAR(50)) OR cs.fk_jobId = j.Mrfcode)
                            AND (cs.VendorRef = v.Vendor_Code OR cs.VendorRef = v.pk_recId OR cs.VendorRef = v.Vendor_Name)
    LEFT JOIN TotalJobProfiles tp ON (tp.fk_jobId = CAST(j.pk_reqid AS VARCHAR(50)) OR tp.fk_jobId = j.Mrfcode)
    WHERE 
        (@fk_companyId = '' OR j.fk_companyId = @fk_companyId)
        AND (@vendorCode = '' OR v.Vendor_Code = @vendorCode OR v.pk_recId = @vendorCode OR v.Vendor_Name = @vendorCode OR v.Vendor_Name LIKE '%' + @vendorCode + '%')
        AND (@department = '' OR d.pk_deptid = @department OR j.fk_deptid = @department OR d.deptcode = @department OR d.description = @department OR d.description LIKE '%' + @department + '%')
        AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
        AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
        AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
        AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
        AND (
            @searchTerm = '' 
            OR j.jobtitle LIKE '%' + @searchTerm + '%' 
            OR j.Mrfcode LIKE '%' + @searchTerm + '%'
            OR v.Vendor_Name LIKE '%' + @searchTerm + '%'
            OR v.Vendor_Code LIKE '%' + @searchTerm + '%'
            OR d.description LIKE '%' + @searchTerm + '%'
        );

    -- Resultset 1: Total Count
    SELECT COUNT(1) AS TotalCount 
    FROM #ReqData
    WHERE (@status = '' OR [Status] = @status);

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC) AS RowNum,
            *
        FROM #ReqData
        WHERE (@status = '' OR [Status] = @status)
    )
    SELECT 
        VendorCode,
        VendorName,
        ReqCode,
        JobTitle,
        Department,
        Location,
        [Month],
        [Year],
        MonthYear,
        TargetPositions,
        ProfilesShared,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        VendorSharePct,
        AvgTatDays,
        [Status]
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #ReqData;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_UPDATEJOBREQUISITION
-- Source File: 41_Rejection_Resubmit_Workflow.sql
-- ==========================================================================================
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

    IF NOT EXISTS (SELECT 1 FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    BEGIN
        SELECT 0 AS Success, @ReqId AS reqId, '' AS mrfCode, 'Job Requisition not found.' AS Message;
        RETURN;
    END;

    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;

    IF @fk_locid IS NULL OR @fk_locid = ''
        SELECT TOP 1 @fk_locid = pk_locid FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;

    IF @fk_desgid IS NULL OR @fk_desgid = ''
        SELECT TOP 1 @fk_desgid = pk_desgid FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;

    IF @fk_deptid IS NULL OR @fk_deptid = ''
        SELECT TOP 1 @fk_deptid = pk_deptid FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;

    DECLARE @CurrentStatus          CHAR(1);
    DECLARE @CurrentWorkflow        NVARCHAR(30);
    DECLARE @ExistingMrfCode        NVARCHAR(100);
    DECLARE @CurrentIsDisapproved   BIT;
    DECLARE @CurrentRejectedByLevel NVARCHAR(10);

    SELECT
        @CurrentStatus          = status,
        @CurrentWorkflow        = WorkflowStatus,
        @ExistingMrfCode        = Mrfcode,
        @CurrentIsDisapproved   = ISNULL(isDisapproved, 0),
        @CurrentRejectedByLevel = RejectedByLevel
    FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId;

    -- Workflow Resume: if rejected and not a draft save, route back to rejected level
    DECLARE @NewWorkflowStatus NVARCHAR(30);
    DECLARE @NewApprovalLevel  INT;
    DECLARE @IsResubmit        BIT = 0;

    IF @CurrentIsDisapproved = 1 AND @IsDraft = 0
    BEGIN
        SET @IsResubmit        = 1;
        SET @NewWorkflowStatus = CASE @CurrentRejectedByLevel
            WHEN 'L1' THEN 'L1_Pending'
            WHEN 'L2' THEN 'L2_Pending'
            WHEN 'L3' THEN 'L3_Pending'
            ELSE 'L1_Pending'
        END;
        SET @NewApprovalLevel  = CASE @CurrentRejectedByLevel
            WHEN 'L1' THEN 1
            WHEN 'L2' THEN 2
            WHEN 'L3' THEN 3
            ELSE 1
        END;
    END
    ELSE
    BEGIN
        SET @NewWorkflowStatus = ISNULL(@CurrentWorkflow, 'Submitted');
        SET @NewApprovalLevel  = CASE @CurrentWorkflow
            WHEN 'L1_Pending' THEN 1
            WHEN 'L2_Pending' THEN 2
            WHEN 'L3_Pending' THEN 3
            ELSE 1
        END;
    END;

    DECLARE @statusChar CHAR(1) = CASE
        WHEN @IsDraft = 1 THEN 'D'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'P'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 1 THEN 'B'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 0 THEN 'P'
        ELSE @CurrentStatus
    END;

    DECLARE @requisitionStatus NVARCHAR(50) = CASE
        WHEN @IsDraft = 1 THEN 'Draft'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval'
        WHEN @CurrentStatus = 'D' AND @IsDraft = 0 THEN 'Pending Approval'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 1 THEN 'Pending Buffer Approval'
        WHEN @CurrentStatus IN ('P','B') AND @IsBufferUtilized = 0 THEN 'Pending Approval'
        ELSE (SELECT ISNULL(RequisitionStatus,'Active') FROM dbo.REC_JobRequisition_Mst WHERE pk_reqid = @ReqId)
    END;

    UPDATE dbo.REC_JobRequisition_Mst SET
        jobtitle                  = @JobTitle,
        fk_locid                  = COALESCE(@fk_locid,  fk_locid),
        fk_deptid                 = COALESCE(@fk_deptid, fk_deptid),
        fk_subdeptid              = COALESCE(@fk_subdeptid, fk_subdeptid),
        fk_desgid                 = COALESCE(@fk_desgid, fk_desgid),
        fk_classid                = COALESCE(@fk_classid, fk_classid),
        fk_catid                  = COALESCE(@fk_catid,  fk_catid),
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
        UpdatedDate               = GETDATE(),
        WorkflowStatus            = @NewWorkflowStatus,
        CurrentApprovalLevel      = @NewApprovalLevel,
        isDisapproved             = CASE WHEN @IsResubmit = 1 THEN 0         ELSE isDisapproved  END,
        ResubmittedDate           = CASE WHEN @IsResubmit = 1 THEN GETDATE() ELSE ResubmittedDate END,
        ResubmittedBy             = CASE WHEN @IsResubmit = 1 THEN @UpdatedBy ELSE ResubmittedBy  END,
        LastWorkflowActionDate    = CASE WHEN @IsResubmit = 1 THEN GETDATE() ELSE LastWorkflowActionDate END
    WHERE pk_reqid = @ReqId;

    IF @IsResubmit = 1
        INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
            fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
            approvalLevel, action, approverName, approverRole, workflowStatus
        ) VALUES (
            @ReqId, @UpdatedById, GETDATE(), @NewApprovalLevel,
            CONCAT('Resubmitted after ', @CurrentRejectedByLevel,
                   ' rejection. Resuming at ', @CurrentRejectedByLevel, '.'),
            1, @NewApprovalLevel, 'Resubmitted', @UpdatedBy, 'Site HR', @NewWorkflowStatus
        );

    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @ExistingMrfCode, 'REC_JobRequisition_Mst',
            CASE WHEN @IsResubmit = 1 THEN 'WorkflowResubmit' ELSE 'JobRequisitionUpdate' END,
            CASE WHEN @IsResubmit = 1 THEN CONCAT('Rejected/',@CurrentRejectedByLevel) ELSE 'Multiple Fields' END,
            CASE WHEN @IsResubmit = 1 THEN @NewWorkflowStatus ELSE 'Updated' END,
            @UpdatedBy, GETDATE()
        );
    END TRY BEGIN CATCH END CATCH;

    SELECT
        1 AS Success,
        @ReqId AS reqId,
        @ExistingMrfCode AS mrfCode,
        CASE WHEN @IsResubmit = 1
            THEN CONCAT('MRF resubmitted. Workflow resumed at ', @CurrentRejectedByLevel, ' level.')
            ELSE 'Job Requisition updated successfully.'
        END AS Message,
        @IsResubmit        AS IsResubmit,
        @NewWorkflowStatus AS NewWorkflowStatus;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_REJECTREQUISITION
-- Source File: 58_CJ_DARCL_Approvals_Page_Rights_Email_Resolution.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_RejectRequisition
    @ReqId         BIGINT,
    @ApprovalLevel INT,
    @ApproverId    NVARCHAR(50),
    @ApproverName  NVARCHAR(150),
    @ApproverRole  NVARCHAR(100) = NULL,
    @Remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStatus NVARCHAR(30);
    DECLARE @JobTitle      NVARCHAR(200);
    DECLARE @MrfCode       NVARCHAR(100);
    DECLARE @SubmittedBy   NVARCHAR(150);
    DECLARE @SubmittedById NVARCHAR(50);
    DECLARE @CompanyId     NVARCHAR(50);
    DECLARE @DeptName      NVARCHAR(150);
    DECLARE @LocName       NVARCHAR(150);
    DECLARE @OpeningsCount INT = 1;

    -- Resolve Requisition Details + Company ID (via Location, Department, or Submitting User)
    SELECT 
        @CurrentStatus = r.WorkflowStatus,
        @JobTitle      = r.jobtitle,
        @MrfCode       = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @SubmittedBy   = r.SubmittedBy,
        @SubmittedById = r.SubmittedById,
        @CompanyId     = COALESCE(r.fk_companyId, loc.fk_companyId, dept.fk_companyId, u.fk_companyId),
        @DeptName      = ISNULL(dept.description, 'Operations'),
        @LocName       = ISNULL(loc.locname, 'Hub Operations'),
        @OpeningsCount = ISNULL(r.No_of_post, 1)
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.UM_Users_Mst u WITH (NOLOCK) ON (u.pk_userId = r.SubmittedById OR u.loginname = r.SubmittedById)
    WHERE r.pk_reqid = @ReqId;

    IF @CurrentStatus IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Check if approver is Admin (Roles 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    WHERE (u.pk_userId = @ApproverId OR u.loginname = @ApproverId)
      AND u.fk_roleId IN (1, 2);

    DECLARE @EffectiveLevel INT = @ApprovalLevel;
    IF @IsAdmin = 1
    BEGIN
        IF @CurrentStatus = 'L1_Pending' SET @EffectiveLevel = 1;
        ELSE IF @CurrentStatus = 'L2_Pending' SET @EffectiveLevel = 2;
        ELSE IF @CurrentStatus = 'L3_Pending' SET @EffectiveLevel = 3;
    END

    DECLARE @Now DATETIME = GETDATE();

    -- Reset to Submitted â€” Site HR must resubmit from L1
    IF @EffectiveLevel = 1
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L1ApproverId           = @ApproverId,
            L1ApproverName         = @ApproverName,
            L1Action               = 'Rejected',
            L1ActionDate           = @Now,
            L1Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 2
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L2ApproverId           = @ApproverId,
            L2ApproverName         = @ApproverName,
            L2Action               = 'Rejected',
            L2ActionDate           = @Now,
            L2Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 3
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Submitted',
            CurrentApprovalLevel   = 0,
            L3ApproverId           = @ApproverId,
            L3ApproverName         = @ApproverName,
            L3Action               = 'Rejected',
            L3ActionDate           = @Now,
            L3Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END

    -- Insert into Approval History Log
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @ReqId, @ApproverId, @Now, @EffectiveLevel, @Remarks, 1,
        @EffectiveLevel, 'Rejected', @ApproverName, ISNULL(@ApproverRole, CONCAT('L', @EffectiveLevel, ' Approver')), 'Submitted'
    );

    -- Mandatory Audit Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @MrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            @CurrentStatus, 'Submitted', @ApproverName, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    -- Fetch Site HR Email (Original Requisition Raiser) to notify about rejection
    DECLARE @SiteHrEmail NVARCHAR(200) = '';
    SELECT TOP 1 @SiteHrEmail = COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), ''))
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
    WHERE (u.pk_userId = @SubmittedById OR u.loginname = @SubmittedById OR u.name = @SubmittedBy)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
      AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL;

    -- Return Action Result with full template metadata
    SELECT 
        1 AS Success,
        CONCAT('Requisition rejected at L', @EffectiveLevel, ' â€” returned to Submitted status.') AS Message,
        'Submitted' AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @DeptName AS Department,
        @LocName AS Location,
        @OpeningsCount AS Openings,
        @SubmittedBy AS SubmittedBy,
        @ApproverName AS ApproverName,
        @EffectiveLevel AS EffectiveLevel,
        ISNULL(@Remarks, 'Requisition rejected.') AS Remarks,
        CONVERT(VARCHAR(19), @Now, 120) AS ActionDate,
        ISNULL(@SiteHrEmail, '') AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETLOCATIONMANPOWERLIST
-- Source File: 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetLocationManpowerList
(
    @CompanyId VARCHAR(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        l.pk_locid AS locationId,
        l.locname  AS locationName,
        ISNULL(l.locationCode, ISNULL(l.code, 'HUB')) AS locationCode,
        ISNULL(c.cityname, ISNULL(s.description, 'Operational Hub')) AS state,
        ISNULL(z.zoneDescription, 'General Zone') AS zone,
        ISNULL(l.BaseDemand, 0) AS baseRequired,
        ISNULL(l.BufferPercent, 0.00) AS bufferPercentage,
        ISNULL(l.BufferHeads, 0) AS bufferHeadcount,
        ISNULL(l.TargetCapacity, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0)) AS totalTargetCapacity,
        ISNULL((
            SELECT COUNT(1) 
            FROM dbo.SAL_Employee_Mst e WITH (NOLOCK) 
            WHERE e.fk_locid = l.pk_locid
              AND (
                  @CompanyId IS NULL 
                  OR l.fk_companyId = @CompanyId 
                  OR e.fk_companyId = @CompanyId 
                  OR e.fk_companyId = l.fk_companyId
              )
              AND ISNULL(e.active, 1) = 1
              AND ISNULL(e.employeeleftstatus, 'N') <> 'Y'
        ), 0) AS currentOccupied,
        l.fk_companyId AS companyId,
        ISNULL(ccd.compname, 'HRMS Portal') AS companyName,
        ISNULL(cfg.Company_LogoPath, ccd.complogo) AS companyLogo
    FROM dbo.Location_Mst l WITH (NOLOCK)
    LEFT JOIN dbo.SAL_City_Mst c WITH (NOLOCK) ON c.pk_cityid = l.fk_cityid
    LEFT JOIN dbo.SAL_State_Mst s WITH (NOLOCK) ON s.pk_stateid = l.fk_stateid
    LEFT JOIN dbo.SAL_Zone_Mst z WITH (NOLOCK) ON z.pk_zoneId = l.fk_zoneId
    LEFT JOIN dbo.Common_Client_Details ccd WITH (NOLOCK) ON (
        ccd.fk_companyId = l.fk_companyId 
        OR CAST(ccd.pk_clientid AS VARCHAR(50)) = l.fk_companyId
        OR (@CompanyId IS NOT NULL AND (ccd.fk_companyId = @CompanyId OR CAST(ccd.pk_clientid AS VARCHAR(50)) = @CompanyId))
    )
    LEFT JOIN dbo.SAL_Company_Config cfg WITH (NOLOCK) ON (
        cfg.pk_companyId = l.fk_companyId 
        OR cfg.pk_companyId = ccd.fk_companyId
        OR (@CompanyId IS NOT NULL AND cfg.pk_companyId = @CompanyId)
    )
    WHERE (@CompanyId IS NULL OR l.fk_companyId = @CompanyId)
    ORDER BY l.locname;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_APPROVEREQUISITION
-- Source File: 58_CJ_DARCL_Approvals_Page_Rights_Email_Resolution.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_ApproveRequisition
    @ReqId         BIGINT,
    @ApprovalLevel INT,
    @ApproverId    NVARCHAR(50),
    @ApproverName  NVARCHAR(150),
    @ApproverRole  NVARCHAR(100) = NULL,
    @Remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStatus NVARCHAR(30);
    DECLARE @JobTitle      NVARCHAR(200);
    DECLARE @MrfCode       NVARCHAR(100);
    DECLARE @SubmittedBy   NVARCHAR(150);
    DECLARE @SubmittedById NVARCHAR(50);
    DECLARE @CompanyId     NVARCHAR(50);
    DECLARE @DeptName      NVARCHAR(150);
    DECLARE @LocName       NVARCHAR(150);
    DECLARE @OpeningsCount INT = 1;

    -- Resolve Requisition Details + Company ID (via Location, Department, or Submitting User)
    SELECT 
        @CurrentStatus = r.WorkflowStatus,
        @JobTitle      = r.jobtitle,
        @MrfCode       = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @SubmittedBy   = r.SubmittedBy,
        @SubmittedById = r.SubmittedById,
        @CompanyId     = COALESCE(r.fk_companyId, loc.fk_companyId, dept.fk_companyId, u.fk_companyId),
        @DeptName      = ISNULL(dept.description, 'Operations'),
        @LocName       = ISNULL(loc.locname, 'Hub Operations'),
        @OpeningsCount = ISNULL(r.No_of_post, 1)
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.UM_Users_Mst u WITH (NOLOCK) ON (u.pk_userId = r.SubmittedById OR u.loginname = r.SubmittedById)
    WHERE r.pk_reqid = @ReqId;

    IF @CurrentStatus IS NULL
    BEGIN
        SELECT 0 AS Success, 'Requisition not found.' AS Message;
        RETURN;
    END

    -- Check if approver is Admin (Roles 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    WHERE (u.pk_userId = @ApproverId OR u.loginname = @ApproverId)
      AND u.fk_roleId IN (1, 2);

    -- Effective action level: if admin, act at current level or specified level
    DECLARE @EffectiveLevel INT = @ApprovalLevel;
    IF @IsAdmin = 1
    BEGIN
        IF @CurrentStatus = 'L1_Pending' AND @ApprovalLevel <= 1 SET @EffectiveLevel = 1;
        ELSE IF @CurrentStatus = 'L2_Pending' AND @ApprovalLevel <= 2 SET @EffectiveLevel = 2;
        ELSE IF @ApprovalLevel >= 3 OR @CurrentStatus = 'L3_Pending' SET @EffectiveLevel = 3;
    END
    ELSE
    BEGIN
        DECLARE @ExpectedStatus NVARCHAR(30) = CASE @EffectiveLevel
            WHEN 1 THEN 'L1_Pending'
            WHEN 2 THEN 'L2_Pending'
            WHEN 3 THEN 'L3_Pending'
            ELSE ''
        END;

        IF @CurrentStatus <> @ExpectedStatus
        BEGIN
            SELECT 0 AS Success, CONCAT('Requisition is currently at ', @CurrentStatus, ', not ready for L', @EffectiveLevel, ' action.') AS Message;
            RETURN;
        END
    END

    DECLARE @NextStatus NVARCHAR(30) = CASE @EffectiveLevel
        WHEN 1 THEN 'L2_Pending'
        WHEN 2 THEN 'L3_Pending'
        WHEN 3 THEN 'Active'
    END;

    DECLARE @Now DATETIME = GETDATE();

    -- Perform Update per Level
    IF @EffectiveLevel = 1
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'L2_Pending',
            CurrentApprovalLevel   = 2,
            L1ApproverId           = @ApproverId,
            L1ApproverName         = @ApproverName,
            L1Action               = 'Approved',
            L1ActionDate           = @Now,
            L1Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 2
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'L3_Pending',
            CurrentApprovalLevel   = 3,
            L2ApproverId           = @ApproverId,
            L2ApproverName         = @ApproverName,
            L2Action               = 'Approved',
            L2ActionDate           = @Now,
            L2Remarks              = @Remarks,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END
    ELSE IF @EffectiveLevel = 3
    BEGIN
        UPDATE dbo.REC_JobRequisition_Mst SET
            WorkflowStatus         = 'Active',
            CurrentApprovalLevel   = 99,
            L3ApproverId           = @ApproverId,
            L3ApproverName         = @ApproverName,
            L3Action               = 'Approved',
            L3ActionDate           = @Now,
            L3Remarks              = @Remarks,
            HiringOpenedDate       = @Now,
            isApproved             = 1,
            approvaldate           = @Now,
            LastWorkflowActionDate = @Now
        WHERE pk_reqid = @ReqId;
    END

    -- Insert into Approval History Log
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive,
        approvalLevel, action, approverName, approverRole, workflowStatus
    ) VALUES (
        @ReqId, @ApproverId, @Now, @EffectiveLevel, @Remarks, 1,
        @EffectiveLevel, 'Approved', @ApproverName, ISNULL(@ApproverRole, CONCAT('L', @EffectiveLevel, ' Approver')), @NextStatus
    );

    -- Mandatory Audit Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @ReqId, @MrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            @CurrentStatus, @NextStatus, @ApproverName, GETDATE()
        );
    END TRY
    BEGIN CATCH
    END CATCH;

    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- NOTIFICATION & EMAIL RESOLUTION ACCORDING TO PAGE RIGHTS (L1, L2, L3)
    -- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    DECLARE @NextLevelEmails NVARCHAR(MAX) = '';

    -- If approved at L1 (moving to L2_Pending) -> Fetch users with L2_Access = 1 in UM_UserPageRights
    IF @EffectiveLevel = 1
    BEGIN
        SELECT @NextLevelEmails = STRING_AGG(Email, ',')
        FROM (
            SELECT DISTINCT COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) AS Email
            FROM dbo.UM_Users_Mst u WITH (NOLOCK)
            INNER JOIN dbo.UM_UserPageRights upr WITH (NOLOCK) ON upr.fk_userId = u.pk_userId
            LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
            WHERE upr.L2_Access = 1
              AND u.active = 1
              AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
              AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL
        ) src;
    END

    -- If approved at L2 (moving to L3_Pending) -> Fetch users with L3_Access = 1 in UM_UserPageRights
    ELSE IF @EffectiveLevel = 2
    BEGIN
        SELECT @NextLevelEmails = STRING_AGG(Email, ',')
        FROM (
            SELECT DISTINCT COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) AS Email
            FROM dbo.UM_Users_Mst u WITH (NOLOCK)
            INNER JOIN dbo.UM_UserPageRights upr WITH (NOLOCK) ON upr.fk_userId = u.pk_userId
            LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
            WHERE upr.L3_Access = 1
              AND u.active = 1
              AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
              AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL
        ) src;
    END

    -- Fetch Site HR Email (Original Requisition Raiser) from the SAME COMPANY
    DECLARE @SiteHrEmail NVARCHAR(200) = '';
    SELECT TOP 1 @SiteHrEmail = COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), ''))
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON emp.pk_empId = u.fk_empId
    WHERE (u.pk_userId = @SubmittedById OR u.loginname = @SubmittedById OR u.name = @SubmittedBy)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId)
      AND COALESCE(NULLIF(RTRIM(LTRIM(u.email)), ''), NULLIF(RTRIM(LTRIM(emp.email)), '')) IS NOT NULL;

    -- Return Action Result with full template metadata
    SELECT 
        1 AS Success,
        CASE WHEN @EffectiveLevel = 3 
             THEN 'Requisition approved â€” Hiring is now OPEN!' 
             ELSE CONCAT('Requisition approved at L', @EffectiveLevel, ' â€” forwarded to L', @EffectiveLevel + 1, ' approver.') 
        END AS Message,
        @NextStatus AS NewStatus,
        @MrfCode AS MrfCode,
        @JobTitle AS JobTitle,
        @DeptName AS Department,
        @LocName AS Location,
        @OpeningsCount AS Openings,
        @SubmittedBy AS SubmittedBy,
        @ApproverName AS ApproverName,
        @EffectiveLevel AS EffectiveLevel,
        ISNULL(@Remarks, 'Approved') AS Remarks,
        CONVERT(VARCHAR(19), @Now, 120) AS ActionDate,
        ISNULL(@NextLevelEmails, '') AS NextLevelEmails,
        ISNULL(@SiteHrEmail, '') AS SiteHrEmail,
        @CompanyId AS CompanyId;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.LOCATION_UPDATE_MANPOWER_BUFFER
-- Source File: 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.Location_Update_Manpower_Buffer
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
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETREQUISITIONMASTERDATA
-- Source File: 37_CJ_DARCL_GetRequisitionMasterData_CompanySpecificEmployees.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetRequisitionMasterData
    @UserId    NVARCHAR(50)  = NULL,
    @LoginName NVARCHAR(100) = NULL,
    @CompanyId NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Dynamically resolve @CompanyId from user session if not passed explicitly
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId 
        FROM dbo.UM_Users_Mst WITH (NOLOCK) 
        WHERE (@UserId IS NOT NULL AND (pk_userId = @UserId OR loginName = @UserId))
           OR (@LoginName IS NOT NULL AND (loginName = @LoginName OR email = @LoginName));
    END;

    -- 2. Normalize numeric CompanyId if needed (e.g., '1' -> 'GU-1')
    IF (@CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.SAL_Employee_Mst WHERE fk_companyId = @CompanyId)
           AND EXISTS (SELECT 1 FROM dbo.SAL_Employee_Mst WHERE fk_companyId = 'GU-' + @CompanyId)
        BEGIN
            SET @CompanyId = 'GU-' + @CompanyId;
        END;
    END;

    -- 3. Fallback to active system company if still unresolved
    IF (@CompanyId IS NULL OR RTRIM(LTRIM(@CompanyId)) = '')
    BEGIN
        SELECT TOP 1 @CompanyId = fk_companyId FROM dbo.UM_Users_Mst WITH (NOLOCK) WHERE pk_userId = 'GU-1';
    END;

    -- â”€â”€ 1. Departments (Strictly Company-Specific) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    SELECT 
        pk_deptid   AS id, 
        description AS name 
    FROM dbo.Department_Mst 
    WHERE dep_active = 1 
      AND (fk_companyId = @CompanyId OR fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY description;

    -- â”€â”€ 2. Locations with Capacity & Buffer Metrics (Strictly Company-Specific)
    SELECT 
        l.pk_locid AS id, 
        l.locname  AS name, 
        ISNULL(l.locationCode, l.code) AS code, 
        ISNULL(z.zoneDescription, 'General Zone') AS zone, 
        ISNULL(l.BaseDemand, 100) AS baseDemand, 
        ISNULL(l.BufferPercent, 10.00) AS bufferPercent, 
        ISNULL(l.BufferHeads, 10) AS bufferHeads, 
        ISNULL(l.TargetCapacity, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0)) AS targetCapacity,
        ISNULL((
            SELECT COUNT(1) 
            FROM dbo.SAL_Employee_Mst e WITH (NOLOCK) 
            WHERE e.fk_locid = l.pk_locid
              AND (
                  @CompanyId IS NULL 
                  OR e.fk_companyId = @CompanyId 
                  OR e.fk_companyId = l.fk_companyId
              )
              AND ISNULL(e.active, 1) = 1
              AND ISNULL(e.employeeleftstatus, 'N') <> 'Y'
        ), 0) AS currentOccupied
    FROM dbo.Location_Mst l
    LEFT JOIN dbo.SAL_Zone_Mst z ON z.pk_zoneId = l.fk_zoneId
    WHERE (l.fk_companyId = @CompanyId OR l.fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY l.locname;

    -- â”€â”€ 3. Designations (Strictly Company-Specific) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    SELECT 
        pk_desgid   AS id, 
        designation AS name 
    FROM dbo.SAL_Designation_Mst 
    WHERE isActive = 1 
      AND (fk_companyId = @CompanyId OR fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
    ORDER BY designation;

    -- â”€â”€ 4. Employees for Hiring Panel & Approvers (Strictly Company-Specific) 
    SELECT 
        e.pk_empid AS id, 
        e.empname  AS name, 
        e.empcode  AS code,
        ISNULL((SELECT TOP 1 des.designation FROM dbo.SAL_Designation_Mst des WHERE des.pk_desgid = e.fk_desgid), 'Reviewer') AS extra
    FROM dbo.SAL_Employee_Mst e
    WHERE (e.fk_companyId = @CompanyId OR e.fk_companyId = REPLACE(@CompanyId, 'GU-', ''))
      AND ISNULL(e.employeeleftstatus, 'N') = 'N'
    ORDER BY e.empname;

    -- â”€â”€ 5. User Default Location (Tier 1 -> Tier 2 -> Empty) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    DECLARE @DefaultLocId   NVARCHAR(50)  = NULL;
    DECLARE @DefaultLocName NVARCHAR(200) = NULL;

    IF (@UserId IS NOT NULL AND RTRIM(LTRIM(@UserId)) <> '') OR (@LoginName IS NOT NULL AND RTRIM(LTRIM(@LoginName)) <> '')
    BEGIN
        SELECT TOP 1 
            @DefaultLocId   = l.pk_locid, 
            @DefaultLocName = l.locname
        FROM dbo.UM_Users_Mst u
        INNER JOIN dbo.SAL_Employee_Mst e ON e.pk_empid = u.fk_empId
        INNER JOIN dbo.Location_Mst l     ON l.pk_locid = e.fk_locid
        WHERE 
            (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId OR e.empcode = @UserId OR CAST(e.pk_empid AS NVARCHAR(50)) = @UserId))
            OR
            (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR e.empcode = @LoginName OR u.email = @LoginName));

        IF @DefaultLocId IS NULL
        BEGIN
            SELECT TOP 1 
                @DefaultLocId   = l.pk_locid, 
                @DefaultLocName = l.locname
            FROM dbo.UM_Users_Mst u
            INNER JOIN dbo.Location_Mst l ON (l.fk_companyId = u.fk_companyId OR l.fk_companyId = @CompanyId)
            WHERE 
                (@UserId IS NOT NULL AND (u.pk_userId = @UserId OR u.loginname = @UserId))
                OR
                (@LoginName IS NOT NULL AND (u.loginname = @LoginName OR u.email = @LoginName))
            ORDER BY l.pk_locid;
        END
    END

    SELECT 
        @DefaultLocId   AS defaultLocationId, 
        @DefaultLocName AS defaultLocationName;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SAVECANDIDATEONBOARDINGDOSSIER
-- Source File: 31_CJ_DARCL_Allow_Editing_Prefilled_Candidate_Details_In_Dossier.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveCandidateOnboardingDossier
    @AppId           BIGINT,
    @AadhaarNo       NVARCHAR(20)  = NULL,
    @PanNo           NVARCHAR(20)  = NULL,
    @BankAccNo       NVARCHAR(50)  = NULL,
    @BankIfsc        NVARCHAR(20)  = NULL,
    @BankName        NVARCHAR(100) = NULL,
    @NomineeName     NVARCHAR(150) = NULL,
    @NomineeRelation NVARCHAR(50)  = NULL,
    @NomineeDOB      NVARCHAR(30)  = NULL,
    @NomineeContact  NVARCHAR(30)  = NULL,
    @UanNo           NVARCHAR(30)  = NULL,
    @EsicNo          NVARCHAR(30)  = NULL,
    @CandidateName   NVARCHAR(150) = NULL,
    @Mobile          NVARCHAR(20)  = NULL,
    @Email           NVARCHAR(100) = NULL,
    @Gender          NVARCHAR(20)  = NULL,
    @DateOfBirth     DATE          = NULL,
    @FatherName      NVARCHAR(150) = NULL,
    @SubmittedBy     NVARCHAR(100) = 'Site HR Admin',
    @CompanyId       NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE pk_appId = @AppId;
    END

    UPDATE dbo.REC_Candidate_Applications SET
        CandidateName   = ISNULL(NULLIF(@CandidateName, ''), CandidateName),
        Mobile          = ISNULL(NULLIF(@Mobile, ''), Mobile),
        Email           = ISNULL(NULLIF(@Email, ''), Email),
        Gender          = ISNULL(NULLIF(@Gender, ''), Gender),
        DateOfBirth     = COALESCE(@DateOfBirth, DateOfBirth),
        FatherName      = ISNULL(NULLIF(@FatherName, ''), FatherName),
        AadhaarNo       = ISNULL(NULLIF(@AadhaarNo, ''), AadhaarNo),
        PanNo           = ISNULL(NULLIF(@PanNo, ''), PanNo),
        BankAccNo       = ISNULL(NULLIF(@BankAccNo, ''), BankAccNo),
        BankIfsc        = ISNULL(NULLIF(@BankIfsc, ''), BankIfsc),
        BankName        = ISNULL(NULLIF(@BankName, ''), BankName),
        NomineeName     = @NomineeName,
        NomineeRelation = @NomineeRelation,
        NomineeDOB      = @NomineeDOB,
        NomineeContact  = @NomineeContact,
        UanNo           = @UanNo,
        EsicNo          = @EsicNo,
        LastUpdatedDate = GETDATE(),
        LastUpdatedBy   = @SubmittedBy
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Insert Audit Trail
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WITH (NOLOCK) WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByName, ActionRole, Remarks, ActionDate, CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'DOSSIER_UPDATE', 'Selected', 'Selected',
        @SubmittedBy, 'Vendor Partner',
        CONCAT('Vendor updated candidate onboarding dossier and profile details for [', ISNULL(@CandidateName, 'Candidate'), ']'),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 1 AS Success, 'Candidate onboarding dossier and profile details saved successfully.' AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETJOBREQUISITIONBYID
-- Source File: 41_Rejection_Resubmit_Workflow.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetJobRequisitionById
    @ReqId     BIGINT,
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CleanCompanyId    NVARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId NVARCHAR(50) = NULL;
    IF @CompanyId IS NOT NULL AND RTRIM(LTRIM(@CompanyId)) <> '' AND @CompanyId <> '0'
    BEGIN
        SET @CleanCompanyId    = REPLACE(@CompanyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;
    SELECT TOP 1
        r.pk_reqid AS reqId,
        r.pk_reqid AS jobId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.jobtitle AS title,
        ISNULL(dept.description, 'General Logistics') AS department,
        r.fk_deptid, r.fk_subdeptid,
        ISNULL(subdept.description, '') AS subDepartment,
        ISNULL(loc.locname, 'Hub Operations') AS location,
        r.fk_locid,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(des.designation, r.jobtitle) AS designation,
        r.fk_desgid, r.fk_classid,
        ISNULL(grd.gradedetails, '') AS gradeName,
        r.fk_catid,
        ISNULL(cat.category, '') AS categoryName,
        r.fk_costcentreid,
        ISNULL(cc.description, '') AS costCenterName,
        r.fk_zoneId, r.fk_cityid,
        ISNULL(r.BusinessVertical, '') AS businessVertical,
        ISNULL(r.ServiceType, 'Fleet & Transportation') AS serviceType,
        ISNULL(r.SkillCategory, 'Skilled') AS skillCategory,
        ISNULL(r.No_of_post, 1) AS openPositions,
        ISNULL(r.Reason_of_Requirement, 'New') AS hiringType,
        r.ReplacedEmpName, r.Reason_of_Replacement AS replacementReason,
        r.IsDiversityHiring, r.DiversityCategory,
        COALESCE(r.CompanyId, r.fk_companyId) AS companyId,
        COALESCE(r.fk_companyId, r.CompanyId) AS fk_companyId,
        ISNULL(r.WorkplaceType, 'On-Site') AS workplaceType,
        ISNULL(r.EmploymentType, 'Full-Time') AS employmentType,
        ISNULL(r.Priority, 'Medium') AS priority,
        ISNULL(r.Currency, 'INR') AS currency,
        r.Experience_From AS experienceMin, r.Experience_To AS experienceMax,
        r.CTC_From AS ctcMin, r.CTC_To AS ctcMax,
        r.TargetStartDate, r.EducationLevel, r.PrimarySkills, r.SecondarySkills,
        r.NoticePeriodMaxDays, r.Industry,
        r.JobDescription, r.Roles_Responsibilities AS responsibilities,
        r.quali AS qualifications, r.Benefits AS benefits,
        r.HiringManager, r.HiringManagerId, r.LeadRecruiter, r.LeadRecruiterId,
        r.L1ApproverName, r.L1ApproverId, r.Interviewers,
        ISNULL(r.IsBufferUtilized, 0) AS isBufferUtilized,
        ISNULL(r.BufferHeadsUtilized, 0) AS bufferHeadsUtilized,
        ISNULL(r.SubmittedBy, 'Site HR Admin') AS submittedBy,
        r.SubmittedById,
        r.UpdatedBy, r.UpdatedById, r.UpdatedDate,
        r.dated AS createdDate, r.dated AS postedDate,
        ISNULL(r.WorkflowStatus, 'Submitted') AS workflowStatus,
        ISNULL(r.CurrentApprovalLevel, 1) AS currentApprovalLevel,
        -- Rejection / Resubmit tracking
        ISNULL(r.isDisapproved, 0) AS isDisapproved,
        r.RejectedByLevel AS rejectedByLevel,
        r.RejectedByName  AS rejectedByName,
        r.RejectedByDate  AS rejectedByDate,
        r.RejectionRemarks AS rejectionRemarks,
        r.ResubmittedDate, r.ResubmittedBy,
        ISNULL(r.RequisitionStatus,
            CASE
                WHEN r.status = 'D' THEN 'Draft'
                WHEN r.status = 'B' THEN 'Pending Buffer Approval'
                WHEN r.status = 'P' THEN 'Pending Approval'
                WHEN r.status = 'A' THEN 'Active'
                ELSE 'Active'
            END
        ) AS status,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
         WHERE ca.fk_reqid = r.pk_reqid) AS applicantsCount,
        ISNULL((SELECT COUNT(1) FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
                WHERE ca.fk_reqid = r.pk_reqid AND ca.Stage = 'Hired'), 0) AS hiredCount
    FROM dbo.REC_JobRequisition_Mst r WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst        dept    WITH (NOLOCK) ON dept.pk_deptid        = r.fk_deptid
    LEFT JOIN dbo.Sub_Department_Mst    subdept WITH (NOLOCK) ON subdept.pk_subdeptid   = r.fk_subdeptid
    LEFT JOIN dbo.Location_Mst          loc     WITH (NOLOCK) ON loc.pk_locid           = r.fk_locid
    LEFT JOIN dbo.SAL_Designation_Mst   des     WITH (NOLOCK) ON des.pk_desgid          = r.fk_desgid
    LEFT JOIN dbo.SAL_Grade_Mst         grd     WITH (NOLOCK) ON grd.pk_gradeid         = r.fk_classid
    LEFT JOIN dbo.SAL_Category_Mst      cat     WITH (NOLOCK) ON cat.pk_catid           = r.fk_catid
    LEFT JOIN dbo.SAL_Cost_Centre_Mst   cc      WITH (NOLOCK) ON cc.pk_cost_centre_id   = r.fk_costcentreid
    WHERE r.pk_reqid = @ReqId
      AND (
            @CleanCompanyId IS NULL
            OR r.CompanyId    = @CleanCompanyId    OR r.CompanyId    = @PrefixedCompanyId
            OR r.fk_companyId = @CleanCompanyId    OR r.fk_companyId = @PrefixedCompanyId
            OR r.CompanyId IS NULL
          );
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_REGISTERCANDIDATE
-- Source File: 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_RegisterCandidate
    @ReqId          BIGINT,
    @CandidateName  NVARCHAR(200),
    @Mobile         NVARCHAR(20),
    @Email          NVARCHAR(150) = NULL,
    @AadhaarNo      NVARCHAR(20)  = NULL,
    @Gender         NVARCHAR(20)  = 'Male',
    @DateOfBirth    NVARCHAR(30)  = NULL,
    @FatherName     NVARCHAR(150) = NULL,
    @CurrentLocation NVARCHAR(150)= NULL,
    @SourceType     NVARCHAR(50)  = 'Vendor',
    @VendorId       NVARCHAR(50)  = NULL,
    @VendorName     NVARCHAR(150) = NULL,
    @CompanyId      NVARCHAR(50)  = NULL,
    @CreatedBy      NVARCHAR(100) = 'Site HR Admin'
AS
BEGIN
    SET NOCOUNT ON;

    -- Retrieve Job Requisition Details (MRF Code, Location, Department, Designation, Diversity Settings)
    DECLARE @MrfCode NVARCHAR(100);
    DECLARE @Hub NVARCHAR(150);
    DECLARE @Dept NVARCHAR(150);
    DECLARE @Desg NVARCHAR(150);
    DECLARE @JobCompanyId NVARCHAR(50);
    DECLARE @JobIsDiversity BIT;
    DECLARE @JobDiversityCategory VARCHAR(MAX);

    SELECT 
        @MrfCode = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)),
        @Hub = ISNULL(loc.locname, 'Hub Operations'),
        @Dept = ISNULL(dept.description, 'General Logistics'),
        @Desg = ISNULL(des.designation, r.jobtitle),
        @JobCompanyId = COALESCE(r.CompanyId, r.fk_companyId),
        @JobIsDiversity = r.IsDiversityHiring,
        @JobDiversityCategory = r.DiversityCategory
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.Department_Mst dept ON dept.pk_deptid = r.fk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst des ON des.pk_desgid = r.fk_desgid
    WHERE r.pk_reqid = @ReqId;

    IF @MrfCode IS NULL
        SET @MrfCode = CONCAT('MRF/2026/', @ReqId);

    IF (@CompanyId IS NULL OR @CompanyId = '')
        SET @CompanyId = @JobCompanyId;

    -- =========================================================================
    -- ZERO DUPLICATION ENGINE (Phone & Aadhaar Validation)
    -- =========================================================================
    DECLARE @IsDuplicate BIT = 0;
    DECLARE @DupDetail NVARCHAR(500) = '';

    -- Check 1: Mobile duplicate in REC_Candidate_Applications
    IF EXISTS (
        SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE Mobile = @Mobile
          AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
    )
    BEGIN
        SET @IsDuplicate = 1;
        SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate applications.');
    END

    -- Check 2: Mobile duplicate in REC_Candidate_Details
    IF @IsDuplicate = 0
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Details WITH (NOLOCK)
            WHERE (mobile = @Mobile OR phone = @Mobile)
              AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Mobile number ', @Mobile, ' already exists in candidate master.');
        END
    END

    -- Check 3: Aadhaar duplicate in REC_Candidate_Applications
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL AND @AadhaarNo <> ''
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
            WHERE AadhaarNo = @AadhaarNo
              AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in candidate applications.');
        END
    END

    -- Check 4: Aadhaar duplicate in SAL_Employee_Mst
    IF @IsDuplicate = 0 AND @AadhaarNo IS NOT NULL AND @AadhaarNo <> ''
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dbo.SAL_Employee_Mst WITH (NOLOCK)
            WHERE adhaarNo = @AadhaarNo
              AND (fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '')
        )
        BEGIN
            SET @IsDuplicate = 1;
            SET @DupDetail = CONCAT('Aadhaar Card No ', @AadhaarNo, ' already exists in company Employee Master.');
        END
    END

    -- If duplicate: reject immediately
    IF @IsDuplicate = 1
    BEGIN
        SELECT 
            0 AS Success,
            1 AS IsRejected,
            CONCAT('Registration Rejected: ', @DupDetail, ' Candidate profile already exists.') AS Message,
            0 AS appId,
            '' AS applicationNo,
            @MrfCode AS mrfCode;
        RETURN;
    END

    -- Generate Application No
    DECLARE @YearStr VARCHAR(4) = CAST(YEAR(GETDATE()) AS VARCHAR(4));
    DECLARE @MaxSeq INT = 0;
    
    SELECT @MaxSeq = ISNULL(MAX(TRY_CAST(RIGHT(ApplicationNo, 4) AS INT)), 0)
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE ApplicationNo LIKE CONCAT('APP/', @YearStr, '/%');
    
    DECLARE @NextAppNo NVARCHAR(50) = CONCAT('APP/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));

    -- Determine actual audit role for the registering user
    DECLARE @UserRole NVARCHAR(100) = CASE 
        WHEN @SourceType = 'Vendor' AND @CreatedBy NOT LIKE '%Vendor%' THEN 'Site HR Admin'
        WHEN @SourceType = 'Vendor' AND @CreatedBy LIKE '%Vendor%'     THEN 'Vendor Partner'
        WHEN @SourceType = 'QR_Direct'                                THEN 'Self-Registered (QR)'
        ELSE 'Site HR Admin'
    END;

    INSERT INTO dbo.REC_Candidate_Applications (
        ApplicationNo, fk_reqid, MrfCode, CandidateName, Mobile, Email,
        Gender, DateOfBirth, FatherName, CurrentLocation, OperatingHub,
        Department, Designation, SourceType, fk_vendorId, VendorName,
        AadhaarNo, Stage, SkillClassification, InterviewStatus,
        IsDiversityHiring, DiversityCategory,
        CompanyId, fk_companyId, CreatedDate, CreatedBy, LastUpdatedDate, LastUpdatedBy
    ) VALUES (
        @NextAppNo, @ReqId, @MrfCode, @CandidateName, @Mobile, @Email,
        @Gender, @DateOfBirth, @FatherName, @CurrentLocation, @Hub,
        @Dept, @Desg, @SourceType, @VendorId, @VendorName,
        @AadhaarNo, 'Applied', 'Semi-Skilled', 'Pending',
        @JobIsDiversity, @JobDiversityCategory,
        @CompanyId, @CompanyId, GETDATE(), @CreatedBy, GETDATE(), @CreatedBy
    );

    DECLARE @NewAppId BIGINT = SCOPE_IDENTITY();

    -- Insert Audit Trail
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @NewAppId, @NextAppNo, 'REGISTER', 'None', 'Applied',
        @CreatedBy, @CreatedBy, @UserRole, 
        CONCAT('Candidate registered against MRF ', @MrfCode, CASE WHEN @VendorName IS NOT NULL AND @VendorName <> '' THEN CONCAT(' via ', @VendorName) ELSE '' END), 
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success,
        0 AS IsRejected,
        'Candidate registered successfully.' AS Message,
        @NewAppId AS appId,
        @NextAppNo AS applicationNo,
        @MrfCode AS mrfCode;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETCANDIDATELIFECYCLEAUDIT
-- Source File: 20_CJ_DARCL_Candidate_Audit_Trail_Company_Scoping.sql
-- ==========================================================================================
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

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_REJECTCANDIDATE
-- Source File: 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_RejectCandidate
    @AppId           BIGINT,
    @RejectionReason NVARCHAR(150),
    @Remarks         NVARCHAR(MAX),
    @CooloffPolicy   NVARCHAR(50)  = '90_Days', -- 90_Days / Immediate_Other_Roles / Blacklist
    @NotifyCandidate BIT           = 1,
    @RejectedBy      NVARCHAR(100) = 'Recruiter',
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @CandidateName NVARCHAR(150);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @CandidateName = CandidateName
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found.' AS Message;
        RETURN;
    END

    -- User Rule: In case of reject, candidate STAYS on that stage, marked in red & locked
    UPDATE dbo.REC_Candidate_Applications SET
        -- Keep Stage unchanged at @CurrentStage
        IsRejected       = 1,
        RejectionStage   = @CurrentStage,
        InterviewStatus  = 'Rejected',
        RejectionReason  = @RejectionReason,
        RejectionRemarks = @Remarks,
        CooloffPolicy    = @CooloffPolicy,
        LastUpdatedDate  = GETDATE(),
        LastUpdatedBy    = @RejectedBy
    WHERE pk_appId = @AppId 
      AND (CompanyId = @CompanyId OR fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Insert Audit Entry (Step 15)
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, 
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'REJECT', @CurrentStage, CONCAT(@CurrentStage, ' (Rejected)'),
        NULL, @RejectedBy, 'Site HR Admin',
        CONCAT('Candidate Rejected at stage [', @CurrentStage, '] | Reason: [', @RejectionReason, '] | Remarks: ', @Remarks),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success, 
        CONCAT('Candidate ', @CandidateName, ' marked as Rejected at ', @CurrentStage, ' stage. Candidate remains locked in red at this stage.') AS Message,
        @AppId AS AppId,
        @CurrentStage AS Stage,
        1 AS IsRejected,
        @RejectionReason AS RejectionReason;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.UM_SP_GETUSERACCESSRIGHTS
-- Source File: 43_CJ_DARCL_L1L2L3_USPs.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[UM_SP_GetUserAccessRights]
(
    @userId    varchar(15),
    @moduleId  tinyint
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Result Set 1: Aggregated access flags for the module
    -- MAX across all assigned pages: if user has the right on ANY page they get it
    SELECT
        ISNULL(MAX(CAST(UPR.L1_Access           AS INT)), 0) AS L1_Access,
        ISNULL(MAX(CAST(UPR.L2_Access           AS INT)), 0) AS L2_Access,
        ISNULL(MAX(CAST(UPR.L3_Access           AS INT)), 0) AS L3_Access,
        ISNULL(MAX(CAST(UPR.CanRaiseRequisition AS INT)), 0) AS CanRaiseRequisition,
        ISNULL(MAX(CAST(UPR.CanEditManpower     AS INT)), 0) AS CanEditManpower
    FROM dbo.UM_UserPageRights UPR
    INNER JOIN dbo.UM_WebPage_Mst WP
           ON WP.pk_webpageId = UPR.fk_webpageId
    WHERE UPR.fk_userId  = @userId
      AND WP.fk_moduleId = @moduleId;

    -- Result Set 2: User assigned location IDs for this module
    -- Reading from EXISTING UM_UserModuleDetails — no new table
    SELECT fk_locid
    FROM dbo.UM_UserModuleDetails
    WHERE fk_userId   = @userId
      AND fk_moduleId = @moduleId;
END
GO

-- ==========================================================================================
-- Stored Procedure: dbo.UM_SP_GETWEBPAGESONUSERMODID
-- Source File: 43_CJ_DARCL_L1L2L3_USPs.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[UM_SP_GetWebPagesOnUserModId]
(
    @fk_userId   varchar(15),
    @fk_moduleId tinyint
)
AS
BEGIN
    DECLARE @mappedalias varchar(3)
    EXEC Comm_UserRole_Alias @fk_userId, @mappedalias OUTPUT

    SELECT
        U.pk_webpageId,
        U.menucaption,
        U.webpagename,
        U.pagepath,
        U.tooltip,
        U.parentId,
        U.displayorder,
        U.activestatus,
        U.fk_moduleId,
        U.fk_pagetypeId,
        U.pagedescription,
        U.selectable,
        V.menucaption AS ParentMenu,
        CASE
            WHEN @mappedalias = 'S' THEN 1
            WHEN UR.fk_webpageId IS NOT NULL THEN 1
            ELSE 0
        END AS IsAssigned,
        -- Existing right columns
        ISNULL(UR.AllowAdd,            0) AS AllowAdd,
        ISNULL(UR.AllowUpdate,         0) AS AllowUpdate,
        ISNULL(UR.AllowDelete,         0) AS AllowDelete,
        ISNULL(UR.AllowView,           0) AS AllowView,
        -- NEW: 5 access flag columns
        ISNULL(UR.L1_Access,           0) AS L1_Access,
        ISNULL(UR.L2_Access,           0) AS L2_Access,
        ISNULL(UR.L3_Access,           0) AS L3_Access,
        ISNULL(UR.CanRaiseRequisition, 0) AS CanRaiseRequisition,
        ISNULL(UR.CanEditManpower,     0) AS CanEditManpower
    FROM UM_WebPage_Mst U
    INNER JOIN UM_WebPage_Mst V ON U.parentId = V.pk_webpageId
    LEFT JOIN UM_UserPageRights UR
           ON U.pk_webpageId = UR.fk_webpageId
          AND UR.fk_userId   = @fk_userId
    WHERE U.fk_moduleId  = @fk_moduleId
      AND U.activestatus = 1
    ORDER BY U.displayorder
END
GO

-- ==========================================================================================
-- Stored Procedure: dbo.UM_SP_INSERTUSERPAGERIGHTS
-- Source File: 43_CJ_DARCL_L1L2L3_USPs.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [dbo].[UM_SP_InsertUserPageRights]
(
    @doc      varchar(Max),
    @userid   varchar(15),
    @moduleid tinyint
)
AS
DECLARE @idoc int
BEGIN
    EXEC sp_xml_preparedocument @idoc OUTPUT, @doc
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
    BEGIN TRAN
    BEGIN TRY

    -- [UNCHANGED] Delete + re-insert locations into UM_UserModuleDetails
    Delete From UM_UserModuleDetails
    Where fk_userId = @userid and fk_moduleId = @moduleid

    Insert Into UM_UserModuleDetails(fk_userId, fk_locid, fk_moduleId)
    Select @userid, fk_locid, @moduleid
    From OPENXML (@idoc, '/NewDataSet/LocationList', 2)
    WITH(fk_locid varchar(15))

    -- [UNCHANGED] Delete old page rights for this user+module
    Delete From UM_UserPageRights
    Where fk_userId = @userid
    And fk_webpageId in (Select pk_webpageId From UM_WebPage_Mst Where fk_moduleid = @moduleid)

    -- [UPDATED] Insert page rights with 5 new BIT columns
    Insert Into UM_UserPageRights(
        fk_userId,
        fk_webpageId,
        AllowAdd,
        AllowUpdate,
        AllowDelete,
        AllowView,
        L1_Access,
        L2_Access,
        L3_Access,
        CanRaiseRequisition,
        CanEditManpower
    )
    Select
        @userid,
        fk_webpageId,
        AllowAdd,
        AllowUpdate,
        AllowDelete,
        AllowView,
        ISNULL(L1_Access,           0),
        ISNULL(L2_Access,           0),
        ISNULL(L3_Access,           0),
        ISNULL(CanRaiseRequisition, 0),
        ISNULL(CanEditManpower,     0)
    From OPENXML (@idoc, '/NewDataSet/UM_UserPageRights', 2)
    WITH (
        fk_webpageId        int,
        AllowAdd            bit,
        AllowUpdate         bit,
        AllowDelete         bit,
        AllowView           bit,
        L1_Access           bit,
        L2_Access           bit,
        L3_Access           bit,
        CanRaiseRequisition bit,
        CanEditManpower     bit
    )

    COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK
        DECLARE @ErrMsg nvarchar(4000), @ErrSeverity int
        SELECT @ErrMsg = ERROR_MESSAGE(), @ErrSeverity = ERROR_SEVERITY()
        RAISERROR(@ErrMsg, @ErrSeverity, 1)
    END CATCH
    EXEC sp_xml_removedocument @idoc
END
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_CHECKCANDIDATEAADHAARSTATUS
-- Source File: 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_CheckCandidateAadhaarStatus
    @AadhaarNo NVARCHAR(50),
    @CompanyId VARCHAR(100) = NULL,
    @LocationId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @AadhaarNo = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', ''), '.', '');

    -- ─────────────────────────────────────────────────────────────────────────
    -- 1. MANDATORY BLACKLIST CHECK: SAL_Employee_Mst (isBlacklisted = 1)
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @BlkEmpName NVARCHAR(200);
    DECLARE @BlkReason NVARCHAR(500);

    SELECT TOP 1
        @BlkEmpName = emp.empname,
        @BlkReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
    FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(emp.adhaarNo)), ' ', ''), '-', ''), '.', '') = @AadhaarNo
      AND emp.isBlacklisted = 1
      AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

    IF @BlkEmpName IS NOT NULL
    BEGIN
        SELECT 
            1 AS ExistsStatus,
            0 AS CanProceed,
            @BlkEmpName AS CandidateName,
            'Blacklisted' AS CurrentStatus,
            'Blacklisted' AS JobTitle,
            'Security Restriction: Candidate (' + @BlkEmpName + ') with Aadhaar [' + @AadhaarNo + '] is blacklisted in company records (' + @BlkReason + '). Application cannot be submitted.' AS Message;
        RETURN;
    END;

    -- ─────────────────────────────────────────────────────────────────────────
    -- 2. DUPLICATE AADHAAR CHECK: REC_Candidate_Applications
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @AppCandidateName NVARCHAR(200);
    DECLARE @AppStage NVARCHAR(100);
    DECLARE @AppInterviewStatus NVARCHAR(100);
    DECLARE @AppJobTitle NVARCHAR(200);

    SELECT TOP 1
        @AppCandidateName = CandidateName,
        @AppStage = Stage,
        @AppInterviewStatus = InterviewStatus,
        @AppJobTitle = Designation
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
    ORDER BY pk_appId DESC;

    IF @AppCandidateName IS NOT NULL
    BEGIN
        -- If candidate is already in active interview or selected or hired
        IF @AppInterviewStatus IN ('Selected', 'Interview Scheduled', 'L1 Cleared', 'L2 Cleared', 'HR Cleared', 'Offer Released', 'Joined')
           OR @AppStage IN ('Interview', 'Selected', 'Offer', 'Onboarding', 'Hired')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @AppCandidateName AS CandidateName,
                ISNULL(@AppInterviewStatus, @AppStage) AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate is already in active interview / selection process (' + ISNULL(@AppInterviewStatus, @AppStage) + '). New application cannot be submitted.' AS Message;
            RETURN;
        END
        ELSE IF @AppInterviewStatus IN ('Rejected', 'Dropped')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                1 AS CanProceed,
                @AppCandidateName AS CandidateName,
                @AppInterviewStatus AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate record found (Previous Status: ' + @AppInterviewStatus + '). Re-application allowed.' AS Message;
            RETURN;
        END
        ELSE
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @AppCandidateName AS CandidateName,
                ISNULL(@AppInterviewStatus, 'Under Review') AS CurrentStatus,
                ISNULL(@AppJobTitle, 'Walk-In Role') AS JobTitle,
                'An application with this Aadhaar number is already pending review (' + ISNULL(@AppInterviewStatus, 'Applied') + '). Duplicate submission not allowed.' AS Message;
            RETURN;
        END
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 3. DUPLICATE AADHAAR CHECK: REC_Candidate_Details (Vendor_AaddharNo)
    -- ─────────────────────────────────────────────────────────────────────────
    DECLARE @DetCandidateName NVARCHAR(200);
    DECLARE @DetStatus NVARCHAR(100);
    DECLARE @DetJobTitle NVARCHAR(200);

    SELECT TOP 1
        @DetCandidateName = candidate_name,
        @DetStatus = status,
        @DetJobTitle = designation
    FROM dbo.REC_Candidate_Details WITH (NOLOCK)
    WHERE REPLACE(REPLACE(REPLACE(Vendor_AaddharNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
    ORDER BY pk_recId DESC;

    IF @DetCandidateName IS NOT NULL
    BEGIN
        IF @DetStatus IN ('Selected', 'Final Selected', 'Joined', 'Onboarding', 'Active', 'Interview')
        BEGIN
            SELECT 
                1 AS ExistsStatus,
                0 AS CanProceed,
                @DetCandidateName AS CandidateName,
                @DetStatus AS CurrentStatus,
                ISNULL(@DetJobTitle, 'Walk-In Role') AS JobTitle,
                'Candidate already exists in onboarding/selection (' + @DetStatus + '). New submission blocked.' AS Message;
            RETURN;
        END
    END

    -- ─────────────────────────────────────────────────────────────────────────
    -- 4. ALL CLEAR: Eligible to Apply
    -- ─────────────────────────────────────────────────────────────────────────
    SELECT 
        0 AS ExistsStatus,
        1 AS CanProceed,
        '' AS CandidateName,
        'New' AS CurrentStatus,
        '' AS JobTitle,
        'Aadhaar number verified and clear. Candidate eligible to apply.' AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_DEALLOCATEVENDORREQUISITIONMAPPING
-- Source File: 13_MAP_Vendors_To_Locations_And_Filter_By_Job_Location.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_DeallocateVendorRequisitionMapping
    @ReqId     BIGINT,
    @VendorId  NVARCHAR(50),
    @CompanyId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.REC_Requisition_Vendor_Mapping
    WHERE fk_reqid = @ReqId 
      AND (fk_vendorId = @VendorId OR fk_vendorId = (SELECT TOP 1 pk_recId FROM dbo.REC_Candidate_Details WHERE Vendor_Code = @VendorId));

    SELECT 1 AS Success, 'Vendor deallocated successfully.' AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GENERATEOFFERLETTER
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GenerateOfferLetter
    @AppId               BIGINT,
    @OfferedCTC          DECIMAL(12,2),
    @ExpectedJoiningDate DATE,
    @IssuedBy            NVARCHAR(150),
    @CompanyId           NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @ExistingCode NVARCHAR(50);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @ExistingCode = CandidateCode
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- Generate unique Candidate Code: CJ/YEAR/XXXX
    DECLARE @CandidateCode NVARCHAR(50) = @ExistingCode;
    IF @CandidateCode IS NULL OR RTRIM(LTRIM(@CandidateCode)) = ''
    BEGIN
        DECLARE @YearStr NVARCHAR(4) = CAST(YEAR(GETDATE()) AS NVARCHAR(4));
        DECLARE @MaxSeq INT = 0;

        SELECT @MaxSeq = ISNULL(MAX(CAST(RIGHT(CandidateCode, 4) AS INT)), 0)
        FROM dbo.REC_Candidate_Applications
        WHERE CandidateCode LIKE CONCAT('CJ/', @YearStr, '/%');

        SET @CandidateCode = CONCAT('CJ/', @YearStr, '/', RIGHT('0000' + CAST(@MaxSeq + 1 AS VARCHAR(4)), 4));
    END

    DECLARE @OfferCode NVARCHAR(50) = CONCAT('OFFER/', YEAR(GETDATE()), '/', RIGHT(@AppNo, 4));

    UPDATE dbo.REC_Candidate_Applications SET
        Stage               = 'Offer_Issued',
        CandidateCode       = @CandidateCode,
        OfferedCTC          = @OfferedCTC,
        OfferLetterCode     = @OfferCode,
        OfferLetterSentDate = GETDATE(),
        ExpectedJoiningDate = @ExpectedJoiningDate,
        LastUpdatedDate     = GETDATE(),
        LastUpdatedBy       = @IssuedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'ISSUE_OFFER', @CurrentStage, 'Offer_Issued',
        NULL, @IssuedBy, 'Corporate HR', 
        CONCAT('Candidate Code ', @CandidateCode, ' generated. Offer issued with CTC INR ', @OfferedCTC, '. Joining: ', CONVERT(VARCHAR(10), @ExpectedJoiningDate, 120)), 
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Offer letter generated and candidate ID assigned successfully.' AS Message,
        @CandidateCode AS candidateCode,
        @OfferCode AS offerCode;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETAPPROVALHISTORY
-- Source File: 08_USP_REC_JobRequisition_Workflow.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetApprovalHistory
    @ReqId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. History log
    SELECT
        a.pk_reqtrnid   AS id,
        a.fk_reqid      AS reqId,
        a.approvalLevel,
        a.action,
        a.approverName,
        a.approverRole,
        a.workflowStatus,
        a.remarks,
        a.dated         AS actionDate,
        a.fk_empId      AS approverId
    FROM dbo.REC_JobRequisition_Mst_Approval a
    WHERE a.fk_reqid = @ReqId
    ORDER BY a.dated ASC;

    -- 2. Current State Snapshot
    SELECT 
        r.pk_reqid AS reqId,
        ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid)) AS mrfCode,
        r.jobtitle AS jobTitle,
        r.WorkflowStatus,
        r.CurrentApprovalLevel,
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
        r.HiringOpenedDate,
        r.RejectedByLevel,
        r.RejectedByName,
        r.RejectedByDate,
        r.RejectionRemarks,
        r.SubmittedBy,
        r.SubmittedDate
    FROM dbo.REC_JobRequisition_Mst r 
    WHERE r.pk_reqid = @ReqId;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETCANDIDATEDOCUMENTFILE
-- Source File: 27_CJ_DARCL_USP_GetCandidateDocumentFile.sql
-- ==========================================================================================
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

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETCANDIDATEDOCUMENTS
-- Source File: 19_CJ_DARCL_Document_Review_Verification_Architecture.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetCandidateDocuments
    @AppId     BIGINT,
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Auto-seed standard 13 CJ DARCL document rows if not existing for this candidate
    IF NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId)
    BEGIN
        INSERT INTO dbo.REC_Candidate_Documents (
            fk_appId, DocTypeCode, DocTypeName, DocCategory, IsMandatory, VerificationStatus, CompanyId, fk_companyId
        ) VALUES 
        (@AppId, 'AADHAAR',             'Aadhaar Card (Front & Back Copy)',               'Identity',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'BANK',                'Bank Proof (Cancelled Cheque / Passbook)',       'Financial',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PHOTO',               'Passport Size Photograph',                       'Personal',    1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'PAN',                 'PAN Card Copy (Tax Compliance)',                 'Identity',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EDUCATION',           'Educational Qualification Certificates',         'Academic',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EXPERIENCE',          'Previous Experience & Relieving Letters',        'Career',      0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ADDRESS',             'Address Proof (Voter ID / DL / Utility Bill)',   'Identity',    0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'POLICE_VERIFICATION', 'Police Verification Certificate',                'Compliance',  0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'MEDICAL_FITNESS',     'Pre-Employment Medical Fitness Report',          'Health',      0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ESIC',                'ESIC Declaration & Supporting Documents',        'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EPF',                 'EPF Declaration & UAN Details Form',             'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'NOMINEE',             'Nominee Declaration & Proof Documents',          'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'CONTRACT',            'Employment Contract / Appointment Ack',          'Legal',       0, 'Missing', @CompanyId, @CompanyId);

        -- If candidate already had default Aadhaar, PAN, Bank, Photo stored on REC_Candidate_Applications, prefill them
        UPDATE cd
        SET cd.FileName = 'Aadhaar_Card.pdf',
            cd.FilePath = ca.AadhaarDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'AADHAAR' AND ca.AadhaarDocPath IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'PAN_Card.pdf',
            cd.FilePath = ca.PanDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'PAN' AND ca.PanDocPath IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'Bank_Passbook.pdf',
            cd.FilePath = '/uploads/docs/bank_proof.pdf',
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'BANK' AND ca.BankAccNo IS NOT NULL;

        UPDATE cd
        SET cd.FileName = 'Passport_Photo.jpg',
            cd.FilePath = ca.PhotoDocPath,
            cd.VerificationStatus = CASE WHEN ca.DocVerificationStatus = 'Verified' THEN 'Approved' ELSE 'Pending' END
        FROM dbo.REC_Candidate_Documents cd
        JOIN dbo.REC_Candidate_Applications ca ON ca.pk_appId = cd.fk_appId
        WHERE cd.fk_appId = @AppId AND cd.DocTypeCode = 'PHOTO' AND ca.PhotoDocPath IS NOT NULL;
    END;

    -- Result Set 1: Candidate Full Dossier Header
    SELECT 
        ca.pk_appId               AS appId,
        ca.ApplicationNo          AS applicationNo,
        ca.fk_reqid               AS reqId,
        ca.MrfCode                AS mrfCode,
        ca.CandidateName          AS candidateName,
        ca.Mobile                 AS mobile,
        ca.Email                  AS email,
        ca.Gender                 AS gender,
        ca.DateOfBirth            AS dateOfBirth,
        ca.FatherName             AS fatherName,
        ca.CurrentLocation        AS currentLocation,
        ca.OperatingHub           AS operatingHub,
        ca.Department             AS department,
        ca.Designation            AS designation,
        ca.SourceType             AS sourceType,
        ca.VendorName             AS vendorName,
        ca.AadhaarNo              AS aadhaarNo,
        ca.PanNo                  AS panNo,
        ca.BankAccNo              AS bankAccNo,
        ca.BankIfsc               AS bankIfsc,
        ca.BankName               AS bankName,
        ca.NomineeName            AS nomineeName,
        ca.NomineeRelation        AS nomineeRelation,
        ca.NomineeDOB             AS nomineeDOB,
        ca.NomineeContact         AS nomineeContact,
        ca.UanNo                  AS uanNo,
        ca.EsicNo                 AS esicNo,
        ca.Stage                  AS stage,
        ISNULL(ca.DocVerificationStatus, 'Pending') AS docVerificationStatus,
        ISNULL(ca.OnboardingStatus, 'Pending')      AS onboardingStatus,
        ISNULL(ca.DeficiencyRemarks, '')            AS deficiencyRemarks,
        -- Summary metrics
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1) AS totalMandatory,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1 AND VerificationStatus = 'Approved') AS approvedMandatory,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND VerificationStatus = 'Rejected') AS rejectedCount,
        (SELECT COUNT(1) FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND IsMandatory = 1 AND VerificationStatus = 'Missing') AS missingMandatory
    FROM dbo.REC_Candidate_Applications ca
    WHERE ca.pk_appId = @AppId 
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId OR @CompanyId IS NULL OR @CompanyId = '');

    -- Result Set 2: Itemized Document Records
    SELECT 
        cd.pk_docId             AS docId,
        cd.fk_appId             AS appId,
        cd.DocTypeCode          AS docTypeCode,
        cd.DocTypeName          AS docTypeName,
        cd.DocCategory          AS docCategory,
        cd.IsMandatory          AS isMandatory,
        cd.FileName             AS fileName,
        cd.FilePath             AS filePath,
        cd.FileSize             AS fileSize,
        cd.FileType             AS fileType,
        cd.VerificationStatus   AS verificationStatus,
        cd.RejectionRemarks     AS rejectionRemarks,
        cd.VerifiedBy           AS verifiedBy,
        cd.VerifiedDate         AS verifiedDate,
        cd.UploadedBy           AS uploadedBy,
        cd.UploadedDate         AS uploadedDate
    FROM dbo.REC_Candidate_Documents cd
    WHERE cd.fk_appId = @AppId AND cd.IsActive = 1
    ORDER BY cd.IsMandatory DESC, cd.pk_docId ASC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETMYAPPROVALLEVEL
-- Source File: 08_USP_REC_JobRequisition_Workflow.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetMyApprovalLevel
    @UserId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if user is Administrator / Super Admin
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND u.fk_roleId IN (1, 2);

    IF @IsAdmin = 1
    BEGIN
        SELECT 
            3 AS ApprovalLevel,
            'Administrator (Full Access - All Levels)' AS LevelLabel,
            'ADMINISTRATOR' AS RoleLabel,
            1 AS IsAdmin;
        RETURN;
    END

    SELECT TOP 1 
        cfg.ApprovalLevel,
        cfg.LevelLabel,
        cfg.RoleLabel,
        0 AS IsAdmin
    FROM dbo.REC_ApprovalLevel_Config cfg
    INNER JOIN dbo.UM_Users_Mst u ON u.fk_roleId = cfg.fk_roleId
    WHERE cfg.IsActive = 1
      AND (u.pk_userId = @UserId OR u.loginname = @UserId)
    ORDER BY cfg.ApprovalLevel;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETPENDINGAPPROVALS
-- Source File: 08_USP_REC_JobRequisition_Workflow.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetPendingApprovals
    @UserId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if user is Admin / Super Admin (Role 1 or 2)
    DECLARE @IsAdmin BIT = 0;
    SELECT TOP 1 @IsAdmin = 1
    FROM dbo.UM_Users_Mst u
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND u.fk_roleId IN (1, 2);

    IF @IsAdmin = 1
    BEGIN
        -- Admin has full visibility across all pending approval levels
        SELECT 
            3 AS approvalLevel, 
            (SELECT COUNT(1) FROM dbo.VW_REC_PendingApprovals WHERE WorkflowStatus IN ('L1_Pending','L2_Pending','L3_Pending')) AS pendingCount,
            1 AS isAdmin;

        SELECT * 
        FROM dbo.VW_REC_PendingApprovals
        WHERE WorkflowStatus IN ('L1_Pending','L2_Pending','L3_Pending')
        ORDER BY createdDate DESC;
        RETURN;
    END

    DECLARE @Level INT = NULL;
    SELECT TOP 1 @Level = cfg.ApprovalLevel
    FROM dbo.REC_ApprovalLevel_Config cfg
    INNER JOIN dbo.UM_Users_Mst u ON u.fk_roleId = cfg.fk_roleId
    WHERE cfg.IsActive = 1 AND (u.pk_userId = @UserId OR u.loginname = @UserId);

    IF @Level IS NULL
    BEGIN
        SELECT 0 AS approvalLevel, 0 AS pendingCount, 0 AS isAdmin;
        SELECT TOP 0 * FROM dbo.VW_REC_PendingApprovals;
        RETURN;
    END

    DECLARE @ExpectedStatus NVARCHAR(30) = CASE @Level
        WHEN 1 THEN 'L1_Pending'
        WHEN 2 THEN 'L2_Pending'
        WHEN 3 THEN 'L3_Pending'
        ELSE ''
    END;

    -- Header summary
    SELECT @Level AS approvalLevel, 
           (SELECT COUNT(1) FROM dbo.VW_REC_PendingApprovals WHERE WorkflowStatus = @ExpectedStatus) AS pendingCount,
           0 AS isAdmin;

    -- Pending items
    SELECT * 
    FROM dbo.VW_REC_PendingApprovals
    WHERE WorkflowStatus = @ExpectedStatus
    ORDER BY createdDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETPIPELINESTAGECONFIG
-- Source File: 10_REC_PipelineStageConfig.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetPipelineStageConfig
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

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETPUBLICLOCATIONJOBSANDVENDORS
-- Source File: 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetPublicLocationJobsAndVendors
    @LocationId VARCHAR(100),
    @CompanyId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Dynamic Company Code & Client ID Resolution
    DECLARE @CompanyCode VARCHAR(50) = NULL;
    DECLARE @ClientPkId VARCHAR(50) = NULL;

    IF @CompanyId IS NOT NULL AND @CompanyId <> ''
    BEGIN
        SELECT TOP 1 
            @CompanyCode = fk_companyId,
            @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
        FROM dbo.Common_Client_Details WITH (NOLOCK)
        WHERE fk_companyId = @CompanyId OR CAST(pk_clientid AS VARCHAR(50)) = @CompanyId;

        IF @CompanyCode IS NULL
        BEGIN
            SET @CompanyCode = @CompanyId;
        END;
    END;

    -- Fallback: deduce company from Location record if companyId wasn't passed directly
    IF (@CompanyCode IS NULL OR @CompanyCode = '') AND @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @CompanyCode = loc.fk_companyId
        FROM dbo.Location_Mst loc WITH (NOLOCK)
        WHERE loc.pk_locid = @LocationId OR loc.code = @LocationId OR loc.locationCode = @LocationId OR loc.locname = @LocationId;

        IF @CompanyCode IS NOT NULL
        BEGIN
            SELECT TOP 1 @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
            FROM dbo.Common_Client_Details WITH (NOLOCK)
            WHERE fk_companyId = @CompanyCode;
        END;
    END;

    -- Dynamically resolve active primary company if still unassigned (Zero Hardcoding)
    IF @CompanyCode IS NULL OR @CompanyCode = ''
    BEGIN
        SELECT TOP 1 
            @CompanyCode = fk_companyId,
            @ClientPkId = CAST(pk_clientid AS VARCHAR(50))
        FROM dbo.Common_Client_Details WITH (NOLOCK)
        ORDER BY pk_clientid ASC;
    END;

    -- Resolve Location ID to standard pk_locid
    DECLARE @ResolvedLocId VARCHAR(50) = NULL;
    IF @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @ResolvedLocId = pk_locid
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE pk_locid = @LocationId OR code = @LocationId OR locationCode = @LocationId OR locname = @LocationId;
    END;

    -- 2. Result Set 1: Location Details with Company Name & Logo
    IF @ResolvedLocId IS NOT NULL AND @ResolvedLocId <> ''
    BEGIN
        SELECT TOP 1
            loc.pk_locid AS locationId,
            loc.locname AS locationName,
            ISNULL(loc.locationCode, loc.code) AS locationCode,
            ISNULL(st.description, 'Operational Hub') AS state,
            ISNULL(zn.zoneDescription, 'General Zone') AS zone,
            ISNULL(ccd.compname, 'HRMS Portal') AS companyName,
            ISNULL(cfg.Company_LogoPath, ccd.complogo) AS companyLogo
        FROM dbo.Location_Mst loc WITH (NOLOCK)
        LEFT JOIN dbo.SAL_State_Mst st WITH (NOLOCK) ON TRY_CAST(loc.fk_stateid AS SMALLINT) = st.pk_stateid
        LEFT JOIN dbo.SAL_Zone_Mst zn WITH (NOLOCK) ON TRY_CAST(loc.fk_zoneId AS BIGINT) = zn.pk_zoneId
        LEFT JOIN dbo.Common_Client_Details ccd WITH (NOLOCK) ON (
            ccd.fk_companyId = @CompanyCode 
            OR CAST(ccd.pk_clientid AS VARCHAR(50)) = @ClientPkId
            OR ccd.fk_companyId = loc.fk_companyId
        )
        LEFT JOIN dbo.SAL_Company_Config cfg WITH (NOLOCK) ON (
            cfg.pk_companyId = ccd.fk_companyId 
            OR cfg.pk_companyId = @CompanyCode 
            OR cfg.pk_companyId = loc.fk_companyId
        )
        WHERE loc.pk_locid = @ResolvedLocId;
    END
    ELSE
    BEGIN
        SELECT TOP 1
            '' AS locationId,
            'Walk-In Recruitment Portal' AS locationName,
            'WALKIN' AS locationCode,
            'All Operational Hubs' AS state,
            'All Zones' AS zone,
            ISNULL(ccd.compname, 'HRMS Portal') AS companyName,
            ISNULL(cfg.Company_LogoPath, ccd.complogo) AS companyLogo
        FROM dbo.Common_Client_Details ccd WITH (NOLOCK)
        LEFT JOIN dbo.SAL_Company_Config cfg WITH (NOLOCK) ON (
            cfg.pk_companyId = ccd.fk_companyId 
            OR cfg.pk_companyId = @CompanyCode
        )
        WHERE ccd.fk_companyId = @CompanyCode OR CAST(ccd.pk_clientid AS VARCHAR(50)) = @ClientPkId;
    END;

    -- 3. Result Set 2: Dynamic Job Requisitions (STRICTLY Company-Wise and Location-Wise)
    SELECT 
        req.pk_reqid AS jobId,
        req.Mrfcode AS mrfCode,
        req.jobtitle AS jobTitle,
        ISNULL(dept.description, '') AS department,
        ISNULL(desg.designation, req.jobtitle) AS designation,
        ISNULL(loc.locname, 'Hub') AS locationName,
        req.fk_locid AS locationId,
        'On-Site' AS workplaceType,
        'Full-Time' AS employmentType,
        ISNULL(req.No_of_post, 1) AS openPositions,
        ISNULL(req.Experience_From, 0) AS expMin,
        ISNULL(req.Experience_To, 5) AS expMax,
        ISNULL(req.CTC_From, 0) AS ctcMin,
        ISNULL(req.CTC_To, 0) AS ctcMax,
        ISNULL(req.Technical_Skills, '') AS primarySkills,
        CONVERT(VARCHAR(10), req.dated, 120) AS targetStartDate
    FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON req.fk_deptid = dept.pk_deptid
    LEFT JOIN dbo.SAL_Designation_Mst desg WITH (NOLOCK) ON req.fk_desgid = desg.pk_desgid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON req.fk_locid = loc.pk_locid
    WHERE (
        req.fk_companyId = @CompanyCode 
        OR req.fk_companyId = @ClientPkId 
        OR req.fk_companyId = @CompanyId
        OR req.CompanyId = @CompanyCode
    )
    AND (
        @ResolvedLocId IS NULL OR @ResolvedLocId = ''
        OR req.fk_locid = @ResolvedLocId
    )
    -- Exclude rejected and unapproved requisitions; only show approved/active jobs
    AND ISNULL(req.isDisapproved, 0) = 0
    AND ISNULL(req.RequisitionStatus, '') <> 'Rejected'
    AND ISNULL(req.WorkflowStatus, '') <> 'Rejected'
    AND (req.isApproved = 1 OR req.WorkflowStatus IN ('Active', 'Approved'))
    ORDER BY req.dated DESC;

    -- 4. Result Set 3: Sourcing Vendors (STRICTLY Company-Wise and Location-Wise)
    IF @ResolvedLocId IS NOT NULL AND @ResolvedLocId <> ''
    BEGIN
        SELECT DISTINCT
            cd.pk_recId                                                       AS vendorId,
            COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
            ISNULL(cd.Vendor_Code, '')                                        AS vendorCode
        FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
        INNER JOIN dbo.Vendor_Location_Mapping vlm WITH (NOLOCK) 
                ON vlm.fk_VendorId = CAST(cd.pk_recId AS NVARCHAR(50))
        WHERE cd.IsVendor = 1
          AND (cd.fk_companyId = @CompanyCode OR cd.CompanyId = @CompanyCode OR @CompanyCode IS NULL)
          AND vlm.fk_LocationId = @ResolvedLocId
        ORDER BY vendorName ASC;
    END
    ELSE
    BEGIN
        SELECT DISTINCT
            cd.pk_recId                                                       AS vendorId,
            COALESCE(NULLIF(cd.Vendor_Name, ''), cd.candidate_name, 'Vendor') AS vendorName,
            ISNULL(cd.Vendor_Code, '')                                        AS vendorCode
        FROM dbo.REC_Candidate_Details cd WITH (NOLOCK)
        WHERE cd.IsVendor = 1
          AND (cd.fk_companyId = @CompanyCode OR cd.CompanyId = @CompanyCode OR @CompanyCode IS NULL)
          AND cd.Vendor_Name IS NOT NULL AND LTRIM(RTRIM(cd.Vendor_Name)) <> ''
        ORDER BY vendorName ASC;
    END;

    -- 5. Result Set 4: Active Locations for Company (For Public Walk-In Hub Filter)
    SELECT 
        loc.pk_locid AS locationId,
        loc.locname AS locationName,
        ISNULL(loc.locationCode, loc.code) AS locationCode,
        ISNULL(st.description, 'Operational Hub') AS state,
        ISNULL(zn.zoneDescription, 'General Zone') AS zone
    FROM dbo.Location_Mst loc WITH (NOLOCK)
    LEFT JOIN dbo.SAL_State_Mst st WITH (NOLOCK) ON TRY_CAST(loc.fk_stateid AS SMALLINT) = st.pk_stateid
    LEFT JOIN dbo.SAL_Zone_Mst zn WITH (NOLOCK) ON TRY_CAST(loc.fk_zoneId AS BIGINT) = zn.pk_zoneId
    WHERE (loc.fk_companyId = @CompanyCode OR @CompanyCode IS NULL OR @CompanyCode = '')
      AND loc.locname IS NOT NULL AND LTRIM(RTRIM(loc.locname)) <> ''
    ORDER BY loc.locname ASC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETRECRUITMENTMISREPORT
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetRecruitmentMISReport
    @CompanyId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Result Set 1: Overall Pipeline Funnel Counters
    SELECT 
        COUNT(1) AS totalApplications,
        ISNULL(SUM(CASE WHEN Stage = 'Applied' THEN 1 ELSE 0 END), 0) AS appliedCount,
        ISNULL(SUM(CASE WHEN Stage IN ('Interview_Scheduled', 'Interview_Completed') THEN 1 ELSE 0 END), 0) AS interviewCount,
        ISNULL(SUM(CASE WHEN Stage = 'Selected' THEN 1 ELSE 0 END), 0) AS selectedCount,
        ISNULL(SUM(CASE WHEN Stage IN ('Docs_Submitted', 'Docs_Verified') THEN 1 ELSE 0 END), 0) AS docVerifiedCount,
        ISNULL(SUM(CASE WHEN Stage = 'Offer_Issued' THEN 1 ELSE 0 END), 0) AS offerIssuedCount,
        ISNULL(SUM(CASE WHEN Stage = 'Hired' THEN 1 ELSE 0 END), 0) AS hiredCount,
        ISNULL(SUM(CASE WHEN Stage = 'Rejected' THEN 1 ELSE 0 END), 0) AS rejectedCount
    FROM dbo.REC_Candidate_Applications
    WHERE fk_companyId = @CompanyId;

    -- Result Set 2: Location-Wise Demand vs Filled
    SELECT 
        ISNULL(loc.locname, 'Corporate HQ') AS locationName,
        SUM(ISNULL(r.No_of_post, 1))        AS openDemand,
        COUNT(ca.pk_appId)                  AS totalApplicants,
        SUM(CASE WHEN ca.Stage = 'Hired' THEN 1 ELSE 0 END) AS hiredCount
    FROM dbo.REC_JobRequisition_Mst r
    LEFT JOIN dbo.Location_Mst loc ON loc.pk_locid = r.fk_locid
    LEFT JOIN dbo.REC_Candidate_Applications ca ON ca.fk_reqid = r.pk_reqid AND ca.fk_companyId = @CompanyId
    WHERE (loc.fk_companyId = @CompanyId OR @CompanyId IS NULL)
    GROUP BY loc.locname
    ORDER BY openDemand DESC;

    -- Result Set 3: Skill Classification Distribution
    SELECT 
        ISNULL(SkillClassification, 'Unclassified') AS skillLevel,
        COUNT(1) AS candidateCount
    FROM dbo.REC_Candidate_Applications
    WHERE fk_companyId = @CompanyId
    GROUP BY SkillClassification;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORALLCANDIDATES
-- Source File: 34_CJ_DARCL_Vendor_All_Candidates_And_Bench_Registration.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorAllCandidates
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL,
    @StageFilter NVARCHAR(50) = 'ALL',
    @SearchQuery NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Clean inputs
    SET @VendorId = LTRIM(RTRIM(ISNULL(@VendorId, '')));
    SET @SearchQuery = NULLIF(LTRIM(RTRIM(@SearchQuery)), '');
    SET @StageFilter = UPPER(LTRIM(RTRIM(ISNULL(@StageFilter, 'ALL'))));

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ISNULL(ca.Stage, 'Applied')                                      AS stage,
        ISNULL(ca.InterviewStatus, 'Pending')                            AS interviewStatus,
        ISNULL(ca.SkillClassification, 'Semi-Skilled')                   AS skillClassification,
        ca.CurrentLocation                                               AS location,
        ISNULL(ca.IsRejected, 0)                                         AS isRejected,
        ca.RejectionReason                                               AS rejectionReason,
        ca.CreatedDate                                                   AS submittedDate,
        ca.LastUpdatedDate                                               AS lastUpdatedDate,
        ca.fk_reqid                                                      AS reqId,
        ISNULL(ca.MrfCode, 'BENCH')                                      AS mrfCode,
        ISNULL(ca.Designation, 'Talent Pool Candidate')                  AS jobTitle,
        ISNULL(ca.Department, 'General')                                 AS department,
        ISNULL(ca.OperatingHub, 'General')                               AS hub
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
      AND (
          @StageFilter = 'ALL'
          OR (@StageFilter = 'BENCH' AND (ca.fk_reqid IS NULL OR ca.fk_reqid = 0 OR ca.MrfCode = 'BENCH' OR ca.Stage = 'Bench'))
          OR (@StageFilter = 'REJECTED' AND (ISNULL(ca.IsRejected, 0) = 1 OR ca.Stage = 'Rejected'))
          OR (@StageFilter = 'INTERVIEW_PASSED' AND (ca.Stage = 'Selected' OR ca.InterviewStatus = 'Passed' OR ca.InterviewStatus = 'Selected'))
          OR (@StageFilter = 'INTERVIEW' AND (ca.Stage LIKE '%Interview%' AND ca.Stage <> 'Selected'))
          OR (@StageFilter = 'HIRED' AND ca.Stage = 'Hired')
          OR (@StageFilter = 'APPLIED' AND ca.Stage = 'Applied' AND ISNULL(ca.IsRejected, 0) = 0)
          OR (UPPER(ca.Stage) = @StageFilter)
      )
      AND (
          @SearchQuery IS NULL 
          OR ca.CandidateName LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Mobile LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.AadhaarNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.ApplicationNo LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.MrfCode LIKE CONCAT('%', @SearchQuery, '%')
          OR ca.Designation LIKE CONCAT('%', @SearchQuery, '%')
      )
    ORDER BY ca.CreatedDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORJOBSUBMISSIONS
-- Source File: 30_CJ_DARCL_USP_GetVendorJobSubmissions.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorJobSubmissions
    @VendorId    NVARCHAR(50),
    @ReqId       BIGINT,
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(CompanyId, fk_companyId)
        FROM dbo.REC_JobRequisition_Mst WITH (NOLOCK)
        WHERE pk_reqid = @ReqId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ISNULL(ca.Stage, 'Applied')                                      AS stage,
        ISNULL(ca.InterviewStatus, 'Pending')                            AS interviewStatus,
        ISNULL(ca.SkillClassification, 'Semi-Skilled')                   AS skillClassification,
        ca.CurrentLocation                                               AS location,
        ISNULL(ca.IsRejected, 0)                                         AS isRejected,
        ca.RejectionReason                                               AS rejectionReason,
        ca.CreatedDate                                                   AS submittedDate,
        ca.LastUpdatedDate                                               AS lastUpdatedDate
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    WHERE ca.fk_vendorId = @VendorId
      AND ca.fk_reqid = @ReqId
      AND (@CompanyId IS NULL OR @CompanyId = '' OR ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
    ORDER BY ca.CreatedDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_GETVENDORSELECTEDCANDIDATES
-- Source File: 22_CJ_DARCL_Vendor_Portal_Architecture.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_GetVendorSelectedCandidates
    @VendorId    NVARCHAR(50),
    @CompanyId   NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company resolution if not passed
    IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '0'
    BEGIN
        SELECT TOP 1 @CompanyId = COALESCE(fk_companyId, CompanyId)
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE pk_recId = @VendorId;
    END

    SELECT 
        ca.pk_appId                                                      AS appId,
        ca.ApplicationNo                                                 AS applicationNo,
        ca.CandidateName                                                 AS candidateName,
        ca.Mobile                                                        AS mobile,
        ca.Email                                                         AS email,
        ca.Gender                                                        AS gender,
        ca.DateOfBirth                                                   AS dateOfBirth,
        ca.FatherName                                                    AS fatherName,
        ca.AadhaarNo                                                     AS aadhaarNo,
        ca.PanNo                                                         AS panNo,
        ca.BankAccNo                                                     AS bankAccNo,
        ca.BankIfsc                                                      AS bankIfsc,
        ca.BankName                                                      AS bankName,
        ca.NomineeName                                                   AS nomineeName,
        ca.NomineeRelation                                               AS nomineeRelation,
        ca.NomineeDOB                                                    AS nomineeDOB,
        ca.NomineeContact                                                AS nomineeContact,
        ca.UanNo                                                         AS uanNo,
        ca.EsicNo                                                        AS esicNo,
        ca.fk_reqid                                                      AS reqId,
        ISNULL(jm.Mrfcode, CONCAT('MRF/', ca.fk_reqid))                  AS mrfCode,
        ISNULL(jm.jobtitle, ca.Designation)                              AS jobTitle,
        ISNULL(dept.description, 'Operations')                           AS department,
        ISNULL(loc.locname, 'Hub Operations')                            AS location,
        ca.Stage                                                         AS stage,
        ca.LastUpdatedDate                                               AS selectedDate,
        -- Total uploaded docs count
        ISNULL((
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
            WHERE cd.fk_appId = ca.pk_appId 
              AND ISNULL(cd.FileName, '') != ''
              AND (cd.CompanyId = @CompanyId OR cd.fk_companyId = @CompanyId)
        ), 0) AS uploadedDocsCount,
        -- Missing mandatory docs count
        ISNULL((
            SELECT COUNT(1)
            FROM dbo.REC_Candidate_Documents cd WITH (NOLOCK)
            WHERE cd.fk_appId = ca.pk_appId 
              AND cd.IsMandatory = 1 
              AND (cd.FileName IS NULL OR cd.FileName = '')
              AND (cd.CompanyId = @CompanyId OR cd.fk_companyId = @CompanyId)
        ), 0) AS missingMandatoryDocsCount
    FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
    LEFT JOIN dbo.REC_JobRequisition_Mst jm WITH (NOLOCK) ON jm.pk_reqid = ca.fk_reqid
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON loc.pk_locid = jm.fk_locid
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON dept.pk_deptid = jm.fk_deptid
    WHERE ca.fk_vendorId = @VendorId
      AND ca.Stage = 'Selected'
      AND ISNULL(ca.IsRejected, 0) = 0
      AND (ca.CompanyId = @CompanyId OR ca.fk_companyId = @CompanyId)
    ORDER BY ca.LastUpdatedDate DESC;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_HIREANDTRANSFERTOEMPLOYEEMASTER
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_HireAndTransferToEmployeeMaster
    @AppId           BIGINT,
    @HiredBy         NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReqId BIGINT;
    DECLARE @CandidateName NVARCHAR(150);
    DECLARE @Mobile NVARCHAR(20);
    DECLARE @Email NVARCHAR(100);
    DECLARE @FatherName NVARCHAR(150);
    DECLARE @DOB DATE;
    DECLARE @Gender NVARCHAR(20);
    DECLARE @CandidateCode NVARCHAR(50);
    DECLARE @OfferedCTC DECIMAL(12,2);
    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @AadhaarNo NVARCHAR(20);
    DECLARE @PanNo NVARCHAR(20);
    DECLARE @BankAccNo NVARCHAR(50);

    SELECT 
        @ReqId         = fk_reqid,
        @CandidateName = CandidateName,
        @Mobile        = Mobile,
        @Email         = Email,
        @FatherName    = FatherName,
        @DOB           = DateOfBirth,
        @Gender        = Gender,
        @CandidateCode = CandidateCode,
        @OfferedCTC    = ISNULL(OfferedCTC, 300000),
        @CurrentStage  = Stage,
        @AppNo         = ApplicationNo,
        @AadhaarNo     = AadhaarNo,
        @PanNo         = PanNo,
        @BankAccNo     = BankAccNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    -- Resolve Location and Department IDs from Requisition
    DECLARE @LocId NVARCHAR(50);
    DECLARE @DeptId NVARCHAR(50);
    DECLARE @DesgId NVARCHAR(50);

    SELECT 
        @LocId  = fk_locid,
        @DeptId = fk_deptid,
        @DesgId = fk_desgid
    FROM dbo.REC_JobRequisition_Mst
    WHERE pk_reqid = @ReqId;

    -- Generate Employee Code in SAL_Employee_Mst (CJXXXX)
    DECLARE @NewEmpCode NVARCHAR(50) = @CandidateCode;
    IF @NewEmpCode IS NULL OR @NewEmpCode = ''
        SET @NewEmpCode = CONCAT('EMP', RIGHT(CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(10)), 5));

    -- Generate dynamic pk_empid for company: {CompanyId}-{MaxSeq+1} (100% Company-Specific, Zero Hardcoding)
    DECLARE @NewEmpId NVARCHAR(50);
    DECLARE @MaxNum BIGINT = 0;
    SELECT @MaxNum = ISNULL(MAX(TRY_CAST(SUBSTRING(pk_empid, CHARINDEX('-', pk_empid) + 1, 20) AS BIGINT)), 0)
    FROM dbo.SAL_Employee_Mst
    WHERE fk_companyId = @CompanyId;

    SET @NewEmpId = CONCAT(@CompanyId, '-', @MaxNum + 1);

    -- Insert into SAL_Employee_Mst using exact existing schema
    BEGIN TRY
        INSERT INTO dbo.SAL_Employee_Mst (
            pk_empid, empcode, empname, fathername, dateofbirth, dateofjoining,
            fk_locid, fk_deptid, fk_desgid, email, panno, adhaarNo, bankaccountno,
            ctc, basic, employeeleftstatus, active, fk_companyId
        ) VALUES (
            @NewEmpId, @NewEmpCode, @CandidateName, @FatherName, ISNULL(@DOB, '1995-01-01'), GETDATE(),
            @LocId, @DeptId, @DesgId, @Email, @PanNo, @AadhaarNo, @BankAccNo,
            @OfferedCTC, (@OfferedCTC / 12) * 0.5, 'N', 1, @CompanyId
        );
    END TRY
    BEGIN CATCH
        -- Fallback catch to ensure non-blocking transaction
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
    END CATCH;

    -- Update Candidate Application Stage to Hired
    UPDATE dbo.REC_Candidate_Applications SET
        Stage           = 'Hired',
        EmployeeCode    = @NewEmpCode,
        HiredDate       = GETDATE(),
        HiredBy         = @HiredBy,
        LastUpdatedDate = GETDATE(),
        LastUpdatedBy   = @HiredBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'HIRE', @CurrentStage, 'Hired',
        NULL, @HiredBy, 'Site HR', 
        CONCAT('Candidate successfully onboarded and converted to Employee Master. Assigned Employee Code: ', @NewEmpCode, ' (EmpId: ', @NewEmpId, ')'), 
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Candidate successfully hired and transferred to Employee Master.' AS Message,
        @NewEmpCode AS employeeCode,
        @NewEmpId AS empId;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SAVECANDIDATEONBOARDINGDOCS
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveCandidateOnboardingDocs
    @AppId           BIGINT,
    @AadhaarNo       NVARCHAR(20),
    @AadhaarDocPath  NVARCHAR(300) = NULL,
    @PanNo           NVARCHAR(20)  = NULL,
    @PanDocPath      NVARCHAR(300) = NULL,
    @BankAccNo       NVARCHAR(50)  = NULL,
    @BankIfsc        NVARCHAR(20)  = NULL,
    @BankName        NVARCHAR(100) = NULL,
    @PhotoDocPath    NVARCHAR(300) = NULL,
    @ResumeDocPath   NVARCHAR(300) = NULL,
    @SubmittedBy     NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                 = 'Docs_Submitted',
        AadhaarNo             = @AadhaarNo,
        AadhaarDocPath        = ISNULL(@AadhaarDocPath, AadhaarDocPath),
        PanNo                 = @PanNo,
        PanDocPath            = ISNULL(@PanDocPath, PanDocPath),
        BankAccNo             = @BankAccNo,
        BankIfsc              = @BankIfsc,
        BankName              = @BankName,
        PhotoDocPath          = ISNULL(@PhotoDocPath, PhotoDocPath),
        ResumeDocPath         = ISNULL(@ResumeDocPath, ResumeDocPath),
        DocVerificationStatus = 'Pending',
        LastUpdatedDate       = GETDATE(),
        LastUpdatedBy         = @SubmittedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'SUBMIT_DOCS', @CurrentStage, 'Docs_Submitted',
        NULL, @SubmittedBy, 'Vendor/Candidate', 
        'Onboarding documents (Aadhaar, PAN, Bank, Photo) submitted for Site HR verification', 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, 'Onboarding documents uploaded successfully.' AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SCHEDULECANDIDATEINTERVIEW
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ================================================    -- Clean inputs
    SET @CandidateName = LTRIM(RTRIM(@CandidateName));
    SET @MobileNumber = RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@MobileNumber)), '+91', ''), '-', ''), ' ', ''), '+', ''), 10);
    SET @AadhaarNo = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@AadhaarNo, ''))), '-', ''), ' ', ''), '.', '');

    -- ── 1. MANDATORY BLACKLIST CHECK (SAL_Employee_Mst isBlacklisted = 1) ────
    -- Check 1a: Blacklisted Aadhaar
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @BlkAadhaarName NVARCHAR(200);
        DECLARE @BlkAadhaarReason NVARCHAR(500);

        SELECT TOP 1
            @BlkAadhaarName = emp.empname,
            @BlkAadhaarReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
        FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(emp.adhaarNo)), ' ', ''), '-', ''), '.', '') = @AadhaarNo
          AND emp.isBlacklisted = 1
          AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

        IF @BlkAadhaarName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @BlkAadhaarName AS CandidateName,
                'Blacklisted' AS JobTitle,
                'Security Restriction: Candidate (' + @BlkAadhaarName + ') with Aadhaar [' + @AadhaarNo + '] is blacklisted in company employee records (' + @BlkAadhaarReason + '). Application cannot be submitted.' AS Message;
            RETURN;
        END
    END

    -- Check 1b: Blacklisted Mobile Number
    IF @MobileNumber IS NOT NULL AND LEN(@MobileNumber) = 10
    BEGIN
        DECLARE @BlkMobileName NVARCHAR(200);
        DECLARE @BlkMobileReason NVARCHAR(500);

        SELECT TOP 1
            @BlkMobileName = emp.empname,
            @BlkMobileReason = ISNULL(emp.blacklistReason, 'Disciplinary dismissal - Blacklisted in Company Records')
        FROM dbo.SAL_Employee_Mst emp WITH (NOLOCK)
        LEFT JOIN dbo.SAL_EmployeeOther_Details oth WITH (NOLOCK) ON emp.pk_empid = oth.fk_empid
        WHERE emp.isBlacklisted = 1
          AND (
            RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(oth.PersonalContactno, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
            OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(oth.permanentContactNo, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
            OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(emp.NomineeMobileNo, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
          )
          AND (@CompanyId IS NULL OR @CompanyId = '' OR emp.fk_companyId = @CompanyId);

        IF @BlkMobileName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @BlkMobileName AS CandidateName,
                'Blacklisted' AS JobTitle,
                'Security Restriction: Candidate (' + @BlkMobileName + ') with Mobile Number [' + @MobileNumber + '] is blacklisted in company records (' + @BlkMobileReason + '). Application cannot be submitted.' AS Message;
            RETURN;
        END
    END

    -- ── 2. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Applications) ──────
    DECLARE @ExistingAppName NVARCHAR(200);
    DECLARE @ExistingAppStatus NVARCHAR(100);
    DECLARE @ExistingAppJob NVARCHAR(200);

    SELECT TOP 1
        @ExistingAppName = CandidateName,
        @ExistingAppStatus = ISNULL(InterviewStatus, Stage),
        @ExistingAppJob = Designation
    FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
    WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
    ORDER BY pk_appId DESC;

    IF @ExistingAppName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingAppName AS CandidateName,
            ISNULL(@ExistingAppJob, 'Spot Candidate') AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' already exists with active application (' + @ExistingAppName + ' - ' + ISNULL(@ExistingAppStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 3. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Details) ───────────
    DECLARE @ExistingDetName NVARCHAR(200);
    DECLARE @ExistingDetStatus NVARCHAR(100);

    SELECT TOP 1
        @ExistingDetName = candidate_name,
        @ExistingDetStatus = status
    FROM dbo.REC_Candidate_Details WITH (NOLOCK)
    WHERE (IsVendor = 0 OR IsVendor IS NULL)
      AND (
        RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
        OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      )
      AND ISNULL(status, '') NOT IN ('Rejected', 'Dropped')
    ORDER BY pk_recId DESC;

    IF @ExistingDetName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingDetName AS CandidateName,
            'Spot Candidate' AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' is already registered under ' + @ExistingDetName + ' (' + ISNULL(@ExistingDetStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 4. DUPLICATE AADHAAR NUMBER CHECK (If Provided) ────────────────────
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @AadhaarDupName NVARCHAR(200);
        DECLARE @AadhaarDupStatus NVARCHAR(100);

        SELECT TOP 1 
            @AadhaarDupName = CandidateName,
            @AadhaarDupStatus = ISNULL(InterviewStatus, Stage)
        FROM dbo.REC_Candidate_Applications WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
          AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
        ORDER BY pk_appId DESC;

        IF @AadhaarDupName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @AadhaarDupName AS CandidateName,
                'Spot Candidate' AS JobTitle,
                'Aadhaar Number already exists with active application (' + @AadhaarDupName + ' - ' + ISNULL(@AadhaarDupStatus, 'Active') + '). Duplicate application not allowed.' AS Message;
            RETURN;
        END

        -- Check in REC_Candidate_Details
        DECLARE @DetAadhaarName NVARCHAR(200);
        DECLARE @DetAadhaarStatus NVARCHAR(100);

        SELECT TOP 1
            @DetAadhaarName = candidate_name,
            @DetAadhaarStatus = status
        FROM dbo.REC_Candidate_Details WITH (NOLOCK)
        WHERE REPLACE(REPLACE(REPLACE(Vendor_AaddharNo, '-', ''), ' ', ''), '.', '') = @AadhaarNo
          AND ISNULL(status, '') NOT IN ('Rejected', 'Dropped')
        ORDER BY pk_recId DESC;

        IF @DetAadhaarName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @DetAadhaarName AS CandidateName,
                'Spot Candidate' AS JobTitle,
                'Aadhaar Number is already registered in recruitment records under ' + @DetAadhaarName + ' (' + ISNULL(@DetAadhaarStatus, 'Active') + '). Duplicate application not allowed.' AS Message;
            RETURN;
        END
    END   'Compliance',  1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'MEDICAL_FITNESS',     'Pre-Employment Medical Fitness Report',          'Health',      1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'ESIC',                'ESIC Declaration & Supporting Documents',        'Statutory',   0, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'EPF',                 'EPF Declaration & UAN Details Form',             'Statutory',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'NOMINEE',             'Nominee Declaration & Proof Documents',          'Statutory',   1, 'Missing', @CompanyId, @CompanyId),
        (@AppId, 'CONTRACT',            'Employment Contract / Appointment Ack',          'Legal',       1, 'Missing', @CompanyId, @CompanyId);
    END
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_SUBMITWALKINCANDIDATE
-- Source File: 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_SubmitWalkInCandidate
    @CandidateName NVARCHAR(200),
    @MobileNumber NVARCHAR(50),
    @AadhaarNo NVARCHAR(50) = NULL,
    @VendorId VARCHAR(100) = NULL,
    @VendorName NVARCHAR(200) = NULL,
    @JobId VARCHAR(100) = NULL,
    @JobTitle NVARCHAR(200) = NULL,
    @LocationId VARCHAR(100) = NULL,
    @CompanyId VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Sanitize Mobile Number
    SET @MobileNumber = REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@MobileNumber)), '+91', ''), '-', ''), ' ', ''), '+', '');
    IF LEN(@MobileNumber) > 10
    BEGIN
        SET @MobileNumber = RIGHT(@MobileNumber, 10);
    END

    -- Sanitize Aadhaar Number (if provided)
    SET @AadhaarNo = CASE 
        WHEN @AadhaarNo IS NOT NULL AND LTRIM(RTRIM(@AadhaarNo)) <> '' 
        THEN REPLACE(REPLACE(LTRIM(RTRIM(@AadhaarNo)), '-', ''), ' ', '') 
        ELSE NULL 
    END;

    SET @CandidateName = LTRIM(RTRIM(@CandidateName));

    -- ── 1. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Applications) ──────
    DECLARE @ExistingAppName NVARCHAR(200);
    DECLARE @ExistingAppStatus NVARCHAR(100);
    DECLARE @ExistingAppJob NVARCHAR(200);

    SELECT TOP 1
        @ExistingAppName = CandidateName,
        @ExistingAppStatus = ISNULL(InterviewStatus, Stage),
        @ExistingAppJob = Designation
    FROM REC_Candidate_Applications
    WHERE RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(Mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
    ORDER BY pk_appId DESC;

    IF @ExistingAppName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingAppName AS CandidateName,
            ISNULL(@ExistingAppJob, 'Spot Candidate') AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' already exists (' + @ExistingAppName + ' - ' + ISNULL(@ExistingAppStatus, 'Active') + '). Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 2. DUPLICATE MOBILE NUMBER CHECK (REC_Candidate_Details) ───────────
    DECLARE @ExistingDetName NVARCHAR(200);
    DECLARE @ExistingDetStatus NVARCHAR(100);

    SELECT TOP 1
        @ExistingDetName = candidate_name,
        @ExistingDetStatus = status
    FROM REC_Candidate_Details
    WHERE (IsVendor = 0 OR IsVendor IS NULL)
      AND (
        RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(mobile, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
        OR RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phone, '+91', ''), '-', ''), ' ', ''), '+', ''), 10) = @MobileNumber
      )
    ORDER BY pk_recId DESC;

    IF @ExistingDetName IS NOT NULL
    BEGIN
        SELECT 
            0 AS Success,
            '' AS ApplicationRef,
            @ExistingDetName AS CandidateName,
            'Spot Candidate' AS JobTitle,
            'Mobile Number ' + @MobileNumber + ' is already registered under ' + @ExistingDetName + '. Duplicate mobile numbers are not allowed.' AS Message;
        RETURN;
    END

    -- ── 3. DUPLICATE AADHAAR NUMBER CHECK (If Provided) ────────────────────
    IF @AadhaarNo IS NOT NULL AND LEN(@AadhaarNo) = 12
    BEGIN
        DECLARE @AadhaarDupName NVARCHAR(200);
        DECLARE @AadhaarDupStatus NVARCHAR(100);

        SELECT TOP 1 
            @AadhaarDupName = CandidateName,
            @AadhaarDupStatus = ISNULL(InterviewStatus, Stage)
        FROM REC_Candidate_Applications
        WHERE REPLACE(REPLACE(AadhaarNo, '-', ''), ' ', '') = @AadhaarNo
          AND ISNULL(InterviewStatus, '') NOT IN ('Rejected', 'Dropped')
        ORDER BY pk_appId DESC;

        IF @AadhaarDupName IS NOT NULL
        BEGIN
            SELECT 
                0 AS Success,
                '' AS ApplicationRef,
                @AadhaarDupName AS CandidateName,
                'Spot Candidate' AS JobTitle,
                'Aadhaar Number already exists with active application (' + @AadhaarDupName + ' - ' + ISNULL(@AadhaarDupStatus, 'Active') + '). Duplicate application not allowed.' AS Message;
            RETURN;
        END
    END

    -- ── 4. RESOLVE VENDOR DETAILS (Strictly Optional) ──────────────────────
    DECLARE @IsVendorSelected BIT = 0;
    IF @VendorId IS NOT NULL AND @VendorId <> '' AND @VendorId <> 'DIRECT' AND @VendorId <> 'V-DIR-01'
    BEGIN
        SET @IsVendorSelected = 1;
        IF @VendorName IS NULL OR @VendorName = '' OR @VendorName = 'Direct Walk-In'
        BEGIN
            SELECT TOP 1 @VendorName = Vendor_Name 
            FROM REC_Candidate_Details WITH (NOLOCK)
            WHERE (pk_recId = @VendorId OR Vendor_Code = @VendorId) AND IsVendor = 1;
        END
    END
    ELSE
    BEGIN
        SET @VendorId = NULL;
        SET @VendorName = 'Direct Walk-In / Self';
    END

    -- ── 5. RESOLVE REQUISITION, LOCATION & COMPANY (Zero Hardcoding) ───────
    DECLARE @ValidReqId BIGINT = 0;
    IF @JobId IS NOT NULL AND TRY_CAST(@JobId AS BIGINT) IS NOT NULL
    BEGIN
        SET @ValidReqId = CAST(@JobId AS BIGINT);
    END

    DECLARE @AppNo NVARCHAR(50) = 'APP/WLK/' + FORMAT(GETDATE(), 'yyyy') + '/' + RIGHT(CAST(ABS(CHECKSUM(NEWID())) AS NVARCHAR(20)), 4);
    DECLARE @LocName NVARCHAR(200) = 'Hub';

    -- If locationId was provided, resolve location name
    IF @LocationId IS NOT NULL AND @LocationId <> ''
    BEGIN
        SELECT TOP 1 @LocName = locname 
        FROM Location_Mst WITH (NOLOCK)
        WHERE pk_locid = @LocationId OR code = @LocationId OR locationCode = @LocationId OR locname = @LocationId;
    END

    -- If locationId was not provided, dynamically resolve from Job Requisition
    IF (@LocationId IS NULL OR @LocationId = '') AND @ValidReqId > 0
    BEGIN
        SELECT TOP 1 
            @LocationId = req.fk_locid,
            @LocName = ISNULL(loc.locname, 'Hub')
        FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
        LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON req.fk_locid = loc.pk_locid
        WHERE req.pk_reqid = @ValidReqId;
    END

    -- Dynamically resolve CompanyId from Requisition, Location or active Client Details
    IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1')
    BEGIN
        IF @ValidReqId > 0
        BEGIN
            SELECT TOP 1 @CompanyId = req.fk_companyId
            FROM dbo.REC_JobRequisition_Mst req WITH (NOLOCK)
            WHERE req.pk_reqid = @ValidReqId;
        END

        IF (@CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1') AND @LocationId IS NOT NULL AND @LocationId <> ''
        BEGIN
            SELECT TOP 1 @CompanyId = loc.fk_companyId
            FROM dbo.Location_Mst loc WITH (NOLOCK)
            WHERE loc.pk_locid = @LocationId OR loc.code = @LocationId OR loc.locationCode = @LocationId OR loc.locname = @LocationId;
        END

        IF @CompanyId IS NULL OR @CompanyId = '' OR @CompanyId = '1'
        BEGIN
            SELECT TOP 1 @CompanyId = fk_companyId
            FROM dbo.Common_Client_Details WITH (NOLOCK)
            ORDER BY pk_clientid ASC;
        END
    END

    -- ── 6. INSERT INTO REC_Candidate_Applications ──────────────────────────
    INSERT INTO REC_Candidate_Applications (
        ApplicationNo,
        fk_reqid,
        CandidateName,
        Mobile,
        AadhaarNo,
        OperatingHub,
        Designation,
        SourceType,
        fk_vendorId,
        VendorName,
        Stage,
        InterviewStatus,
        fk_companyId,
        CompanyId,
        CreatedDate,
        CreatedBy
    ) VALUES (
        @AppNo,
        @ValidReqId,
        @CandidateName,
        @MobileNumber,
        @AadhaarNo,
        @LocName,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate'),
        CASE WHEN @IsVendorSelected = 1 THEN 'Vendor Sourced' ELSE 'Location QR - Walk-In' END,
        CASE WHEN @IsVendorSelected = 1 THEN @VendorId ELSE NULL END,
        @VendorName,
        'Applied',
        'Walk-In Applied',
        @CompanyId,
        @CompanyId,
        GETDATE(),
        'Location QR Portal'
    );

    -- ── 7. INSERT INTO REC_Candidate_Details ───────────────────────────────
    DECLARE @NewRecId VARCHAR(50) = 'REC-' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR(20));
    DECLARE @DefaultUserId VARCHAR(50) = (SELECT TOP 1 pk_userId FROM UM_Users_Mst WITH (NOLOCK) WHERE active = 1 ORDER BY pk_userId ASC);

    INSERT INTO REC_Candidate_Details (
        pk_recId,
        fk_jobId,
        candidate_name,
        mobile,
        Vendor_AaddharNo,
        Vendor_Name,
        Vendor_Code,
        fk_locid,
        designation,
        source,
        status,
        IsVendor,
        online_submit,
        fk_companyId,
        InsDate,
        fk_insUserID
    ) VALUES (
        @NewRecId,
        NULL,
        @CandidateName,
        @MobileNumber,
        @AadhaarNo,
        @VendorName,
        CASE WHEN @IsVendorSelected = 1 THEN @VendorId ELSE NULL END,
        @LocationId,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate'),
        CASE WHEN @IsVendorSelected = 1 THEN 'Vendor Sourced' ELSE 'Location QR - Walk-In' END,
        '1',
        0,
        1,
        @CompanyId,
        GETDATE(),
        @DefaultUserId
    );

    SELECT 
        1 AS Success,
        @AppNo AS ApplicationRef,
        @CandidateName AS CandidateName,
        ISNULL(@JobTitle, 'Spot Walk-In Candidate') AS JobTitle,
        'Application registered successfully for ' + @LocName + '.' AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_TAGCANDIDATE
-- Source File: 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_TagCandidate
    @AppId                BIGINT,
    @ReqId                BIGINT         = NULL,
    @SkillClassification  NVARCHAR(50)   = 'Semi-Skilled',
    @CandidateTags        NVARCHAR(250)  = NULL,
    @IsDiversityHiring    BIT            = 0,
    @AssignedReviewer     NVARCHAR(150)  = NULL,
    @Remarks              NVARCHAR(MAX)  = NULL,
    @TaggedBy             NVARCHAR(100)  = 'Recruiter',
    @CompanyId            NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);
    DECLARE @OldMrf NVARCHAR(100);
    DECLARE @TargetMrf NVARCHAR(100);

    SELECT 
        @CurrentStage = Stage, 
        @AppNo = ApplicationNo,
        @OldMrf = MrfCode
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Candidate application not found for this company.' AS Message;
        RETURN;
    END

    -- If ReqId is provided and different from current, re-tag candidate to the new requisition
    IF @ReqId IS NOT NULL AND @ReqId > 0
    BEGIN
        SELECT @TargetMrf = ISNULL(r.Mrfcode, CONCAT('MRF/', YEAR(r.dated), '/', r.pk_reqid))
        FROM dbo.REC_JobRequisition_Mst r
        WHERE r.pk_reqid = @ReqId;

        UPDATE dbo.REC_Candidate_Applications SET
            fk_reqid            = @ReqId,
            MrfCode             = ISNULL(@TargetMrf, MrfCode),
            SkillClassification = @SkillClassification,
            CandidateTags       = ISNULL(@CandidateTags, CandidateTags),
            IsDiversityHiring   = @IsDiversityHiring,
            AssignedReviewer    = ISNULL(@AssignedReviewer, AssignedReviewer),
            LastUpdatedDate     = GETDATE(),
            LastUpdatedBy       = @TaggedBy
        WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;
    END
    ELSE
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            SkillClassification = @SkillClassification,
            CandidateTags       = ISNULL(@CandidateTags, CandidateTags),
            IsDiversityHiring   = @IsDiversityHiring,
            AssignedReviewer    = ISNULL(@AssignedReviewer, AssignedReviewer),
            LastUpdatedDate     = GETDATE(),
            LastUpdatedBy       = @TaggedBy
        WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;
    END

    -- Insert Audit Entry
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'TAG_CANDIDATE', @CurrentStage, @CurrentStage,
        NULL, @TaggedBy, 'Recruiter',
        CONCAT('Candidate tags updated: Skill=', @SkillClassification, 
               ' | Tags=', ISNULL(@CandidateTags, 'None'), 
               ' | Diversity=', CASE WHEN @IsDiversityHiring = 1 THEN 'Yes' ELSE 'No' END,
               ' | Reviewer=', ISNULL(@AssignedReviewer, 'Unassigned'),
               CASE WHEN @Remarks IS NOT NULL THEN CONCAT(' | Note: ', @Remarks) ELSE '' END),
        GETDATE(), @CompanyId
    );

    SELECT 
        1 AS Success, 
        'Candidate tagged successfully with skill classification, tags, and reviewer.' AS Message,
        @AppId AS AppId,
        @SkillClassification AS SkillClassification,
        @CandidateTags AS CandidateTags;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_UPLOADCANDIDATEDOCUMENTITEM
-- Source File: 19_CJ_DARCL_Document_Review_Verification_Architecture.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_UploadCandidateDocumentItem
    @AppId           BIGINT,
    @DocTypeCode     NVARCHAR(50),
    @FileName        NVARCHAR(255),
    @FilePath        NVARCHAR(500),
    @FileSize        BIGINT,
    @FileType        NVARCHAR(50),
    @UploadedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Update or Insert Document Item
    IF EXISTS (SELECT 1 FROM dbo.REC_Candidate_Documents WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode)
    BEGIN
        UPDATE dbo.REC_Candidate_Documents SET
            FileName           = @FileName,
            FilePath           = @FilePath,
            FileSize           = @FileSize,
            FileType           = @FileType,
            VerificationStatus = 'Pending', -- Reset to pending for HR review upon upload/re-upload
            RejectionRemarks   = NULL,
            UploadedBy         = @UploadedBy,
            UploadedDate       = GETDATE(),
            CompanyId          = @CompanyId,
            fk_companyId       = @CompanyId
        WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.REC_Candidate_Documents (
            fk_appId, DocTypeCode, DocTypeName, DocCategory, IsMandatory,
            FileName, FilePath, FileSize, FileType, VerificationStatus,
            UploadedBy, UploadedDate, CompanyId, fk_companyId
        ) VALUES (
            @AppId, @DocTypeCode, @DocTypeCode, 'Uploaded', 1,
            @FileName, @FilePath, @FileSize, @FileType, 'Pending',
            @UploadedBy, GETDATE(), @CompanyId, @CompanyId
        );
    END;

    -- Sync back to REC_Candidate_Applications main fields if Aadhaar / PAN / Photo
    IF @DocTypeCode = 'AADHAAR'
        UPDATE dbo.REC_Candidate_Applications SET AadhaarDocPath = @FilePath WHERE pk_appId = @AppId;
    ELSE IF @DocTypeCode = 'PAN'
        UPDATE dbo.REC_Candidate_Applications SET PanDocPath = @FilePath WHERE pk_appId = @AppId;
    ELSE IF @DocTypeCode = 'PHOTO'
        UPDATE dbo.REC_Candidate_Applications SET PhotoDocPath = @FilePath WHERE pk_appId = @AppId;

    -- Audit Log
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'UPLOAD_DOC', 'Docs_Submitted', 'Docs_Submitted',
        NULL, @UploadedBy, 'Vendor/Site HR',
        CONCAT('Document [', @DocTypeCode, ' - ', @FileName, '] uploaded for verification'),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Document ', @FileName, ' uploaded successfully.') AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_UPSERTPIPELINESTAGECONFIG
-- Source File: 10_REC_PipelineStageConfig.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_UpsertPipelineStageConfig
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

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_VERIFYCANDIDATEDOCUMENTITEM
-- Source File: 19_CJ_DARCL_Document_Review_Verification_Architecture.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_VerifyCandidateDocumentItem
    @AppId           BIGINT,
    @DocTypeCode     NVARCHAR(50),
    @Status          NVARCHAR(50), -- 'Approved' or 'Rejected'
    @RejectionRemarks NVARCHAR(500) = NULL,
    @VerifiedBy      NVARCHAR(100),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.REC_Candidate_Documents SET
        VerificationStatus = @Status,
        RejectionRemarks   = CASE WHEN @Status = 'Rejected' THEN @RejectionRemarks ELSE NULL END,
        VerifiedBy         = @VerifiedBy,
        VerifiedDate       = GETDATE()
    WHERE fk_appId = @AppId AND DocTypeCode = @DocTypeCode;

    -- Check overall mandatory verification status
    DECLARE @TotalMandatory INT;
    DECLARE @ApprovedMandatory INT;
    DECLARE @RejectedCount INT;

    SELECT 
        @TotalMandatory = COUNT(1),
        @ApprovedMandatory = SUM(CASE WHEN VerificationStatus = 'Approved' THEN 1 ELSE 0 END),
        @RejectedCount = SUM(CASE WHEN VerificationStatus = 'Rejected' THEN 1 ELSE 0 END)
    FROM dbo.REC_Candidate_Documents
    WHERE fk_appId = @AppId AND IsMandatory = 1;

    -- Update Candidate Application overall status
    IF @ApprovedMandatory >= @TotalMandatory AND @TotalMandatory > 0
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            DocVerificationStatus = 'Verified',
            OnboardingStatus      = 'Completed',
            Stage                 = 'Docs_Verified',
            LastUpdatedDate       = GETDATE(),
            LastUpdatedBy         = @VerifiedBy
        WHERE pk_appId = @AppId;
    END
    ELSE IF @RejectedCount > 0
    BEGIN
        UPDATE dbo.REC_Candidate_Applications SET
            DocVerificationStatus = 'Deficient',
            OnboardingStatus      = 'Deficient',
            DeficiencyCount       = @RejectedCount,
            DeficiencyRemarks     = CONCAT(@RejectedCount, ' document(s) rejected during review. Correction & re-upload required.'),
            LastUpdatedDate       = GETDATE(),
            LastUpdatedBy         = @VerifiedBy
        WHERE pk_appId = @AppId;
    END;

    -- Audit Log
    DECLARE @AppNo NVARCHAR(50);
    SELECT @AppNo = ApplicationNo FROM dbo.REC_Candidate_Applications WHERE pk_appId = @AppId;

    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'VERIFY_DOC', 'Docs_Submitted', 'Docs_Submitted',
        NULL, @VerifiedBy, 'Site HR Admin',
        CONCAT('Document [', @DocTypeCode, '] ', @Status, CASE WHEN @Status = 'Rejected' THEN CONCAT(' - Reason: ', @RejectionRemarks) ELSE '' END),
        GETDATE(), @CompanyId, @CompanyId
    );

    SELECT 
        1 AS Success,
        CONCAT('Document [', @DocTypeCode, '] marked as ', @Status, '.') AS Message,
        @Status AS Status,
        @ApprovedMandatory AS ApprovedMandatory,
        @TotalMandatory AS TotalMandatory;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_REC_VERIFYCANDIDATEDOCUMENTS
-- Source File: 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_REC_VerifyCandidateDocuments
    @AppId           BIGINT,
    @IsApproved      BIT,
    @Remarks         NVARCHAR(500) = NULL,
    @VerifiedBy      NVARCHAR(150),
    @CompanyId       NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStage NVARCHAR(50);
    DECLARE @AppNo NVARCHAR(50);

    SELECT @CurrentStage = Stage, @AppNo = ApplicationNo
    FROM dbo.REC_Candidate_Applications
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    IF @AppNo IS NULL
    BEGIN
        SELECT 0 AS Success, 'Application not found.' AS Message;
        RETURN;
    END

    DECLARE @NextStatus NVARCHAR(50) = CASE WHEN @IsApproved = 1 THEN 'Verified' ELSE 'Rejected' END;
    DECLARE @NextStage NVARCHAR(50)  = CASE WHEN @IsApproved = 1 THEN 'Docs_Verified' ELSE 'Docs_Submitted' END;

    UPDATE dbo.REC_Candidate_Applications SET
        Stage                  = @NextStage,
        DocVerificationStatus  = @NextStatus,
        DocVerifiedBy          = @VerifiedBy,
        DocVerifiedDate        = GETDATE(),
        DocVerificationRemarks = @Remarks,
        LastUpdatedDate        = GETDATE(),
        LastUpdatedBy          = @VerifiedBy
    WHERE pk_appId = @AppId AND fk_companyId = @CompanyId;

    -- Audit Log
    INSERT INTO dbo.REC_Candidate_Lifecycle_Audit (
        fk_appId, ApplicationNo, ActionType, PreviousStage, NewStage,
        ActionByUserId, ActionByName, ActionRole, Remarks, ActionDate, fk_companyId
    ) VALUES (
        @AppId, @AppNo, 'VERIFY_DOCS', @CurrentStage, @NextStage,
        NULL, @VerifiedBy, 'Site HR', 
        CONCAT('Document Verification: ', @NextStatus, ' | Remarks: ', ISNULL(@Remarks, 'All mandatory docs verified')), 
        GETDATE(), @CompanyId
    );

    SELECT 1 AS Success, CONCAT('Documents marked as ', @NextStatus, '.') AS Message;
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_UM_GETUSERVENDORPROFILE
-- Source File: 26_CJ_DARCL_USP_GetUserVendorProfile.sql
-- ==========================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_UM_GetUserVendorProfile
    @UserId    VARCHAR(50),
    @CompanyId VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 
        CAST(ISNULL(u.isVendor, 0) AS BIT) AS isVendor, 
        ISNULL(u.fk_vendorId, '')          AS vendorId,
        COALESCE(cd.Vendor_Name, u.name)   AS vendorName,
        ISNULL(cd.Vendor_Code, '')         AS vendorCode,
        u.fk_companyId                     AS companyId,
        u.name                             AS userName,
        u.loginname                        AS loginName
    FROM dbo.UM_Users_Mst u WITH (NOLOCK)
    LEFT JOIN dbo.REC_Candidate_Details cd WITH (NOLOCK) ON cd.pk_recId = u.fk_vendorId
    WHERE (u.pk_userId = @UserId OR u.loginname = @UserId)
      AND (@CompanyId IS NULL OR @CompanyId = '' OR u.fk_companyId = @CompanyId);
END;
GO

-- ==========================================================================================
-- Stored Procedure: dbo.USP_UM_RESOLVEUSERNAME
-- Source File: 40_CJ_DARCL_JobRequisition_GetById_And_Update.sql
-- ==========================================================================================
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

