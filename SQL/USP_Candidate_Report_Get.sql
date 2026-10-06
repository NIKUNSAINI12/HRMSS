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
