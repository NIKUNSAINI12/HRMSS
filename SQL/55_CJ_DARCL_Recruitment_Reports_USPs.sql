-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture
-- File: 55_CJ_DARCL_Recruitment_Reports_USPs.sql
-- Purpose: Consolidated 8 Stored Procedures for Recruitment Reports
-- Procedures: USP_Candidate_Report_Get, USP_Job_Report_Get, USP_Location_Report_Get,
--             USP_Location_Wise_Jobs_Report_Get, USP_MRF_Report_Get,
--             USP_Report_Master_Data_Get, USP_Vendor_Report_Get, USP_Vendor_Wise_Report_Get
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Script: USP_Candidate_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Candidate_Report_Get]    Script Date: 03-10-2026 12:01:07 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


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

-- ----------------------------------------------------------------------------
-- Script: USP_Job_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Job_Report_Get]    Script Date: 03-10-2026 12:00:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

-- ----------------------------------------------------------------------------
-- Script: USP_Location_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Location_Report_Get]    Script Date: 03-10-2026 12:02:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

-- ----------------------------------------------------------------------------
-- Script: USP_Location_Wise_Jobs_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Location_Wise_Jobs_Report_Get]    Script Date: 03-10-2026 12:02:53 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

-- ----------------------------------------------------------------------------
-- Script: USP_MRF_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_MRF_Report_Get]    Script Date: 03-10-2026 11:58:39 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

-- ----------------------------------------------------------------------------
-- Script: USP_Report_Master_Data_Get.sql
-- ----------------------------------------------------------------------------
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

GO

-- ----------------------------------------------------------------------------
-- Script: USP_Vendor_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Vendor_Report_Get]    Script Date: 03-10-2026 12:03:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

-- ----------------------------------------------------------------------------
-- Script: USP_Vendor_Wise_Report_Get.sql
-- ----------------------------------------------------------------------------
--GO
/****** Object:  StoredProcedure [dbo].[USP_Vendor_Wise_Report_Get]    Script Date: 03-10-2026 12:04:03 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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

