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