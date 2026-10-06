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