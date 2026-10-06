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