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