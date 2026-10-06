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