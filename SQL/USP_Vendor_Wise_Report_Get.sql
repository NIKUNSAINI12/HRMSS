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