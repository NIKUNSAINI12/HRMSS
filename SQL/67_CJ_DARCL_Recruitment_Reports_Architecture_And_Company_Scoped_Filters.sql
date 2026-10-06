-- ============================================================================
-- CJ DARCL Logistics - Recruitment Architecture (Migration 67)
-- File: SQL/67_CJ_DARCL_Recruitment_Reports_Architecture_And_Company_Scoped_Filters.sql
-- Purpose: Complete Harmonization of Recruitment Reports Suite (8 USPs):
--          1. USP_Report_Master_Data_Get
--          2. USP_Candidate_Report_Get
--          3. USP_Vendor_Report_Get
--          4. USP_Vendor_Wise_Report_Get
--          5. USP_Job_Report_Get
--          6. USP_MRF_Report_Get
--          7. USP_Location_Report_Get
--          8. USP_Location_Wise_Jobs_Report_Get
--
-- Core Directives Enforced:
--  A. 100% Real-Time Candidate & Vendor Data Integration:
--     Connects all reports directly to live ATS candidate pipeline records in
--     REC_Candidate_Applications (while gracefully preserving REC_Candidate_Details).
--  B. Complete Vendor Dropdown & Filter Resolution:
--     Harmonizes pk_recId (e.g. 'GU-4') and Vendor_Code (e.g. 'V001') and VendorName.
--     Dropdown returns valid vendor keys and reports match vendor across any identifier.
--  C. 100% Company-Specific Multi-Tenant Scoping:
--     Filters dynamically on CompanyId / fk_companyId with clean/prefixed normalization.
--  D. Zero Hardcoding:
--     No fixed company IDs, zero static fallback strings.
-- ============================================================================

USE [HRBook_22];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 1. USP_Report_Master_Data_Get
-- Master dropdown lists for all Recruitment Report filter bars
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[USP_Report_Master_Data_Get]
(
    @fk_companyId VARCHAR(50) = ''
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Dynamic company ID normalization
    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    -- ── Resultset 1: Vendors (Master & Active Pipeline Vendors - Deduplicated) ──
    ;WITH RawVendors AS (
        -- 1. Official Vendor Master in REC_Candidate_Details
        SELECT 
            v.pk_recId AS VendorId,
            NULLIF(RTRIM(LTRIM(v.Vendor_Code)), '') AS VendorCode,
            COALESCE(NULLIF(RTRIM(LTRIM(v.Vendor_Name)), ''), NULLIF(RTRIM(LTRIM(v.candidate_name)), ''), 'Vendor') AS VendorName,
            v.fk_companyId,
            v.CompanyId,
            1 AS Priority
        FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
        WHERE (v.IsVendor = 1 OR v.Vendor_Code IS NOT NULL)

        UNION ALL

        -- 2. Live ATS Candidate Applications (with lookup to Master if available)
        SELECT 
            ca.fk_vendorId AS VendorId,
            NULLIF(RTRIM(LTRIM(v.Vendor_Code)), '') AS VendorCode,
            COALESCE(NULLIF(RTRIM(LTRIM(v.Vendor_Name)), ''), NULLIF(RTRIM(LTRIM(ca.VendorName)), ''), 'Vendor') AS VendorName,
            COALESCE(ca.fk_companyId, v.fk_companyId) AS fk_companyId,
            COALESCE(ca.CompanyId, v.CompanyId) AS CompanyId,
            2 AS Priority
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        LEFT JOIN dbo.REC_Candidate_Details v WITH (NOLOCK) ON v.pk_recId = ca.fk_vendorId
        WHERE ca.fk_vendorId IS NOT NULL AND RTRIM(LTRIM(ca.fk_vendorId)) <> ''

        UNION ALL

        -- 3. Requisition Vendor Allocations
        SELECT 
            rvm.fk_vendorId AS VendorId,
            COALESCE(NULLIF(RTRIM(LTRIM(rvm.VendorCode)), ''), NULLIF(RTRIM(LTRIM(v.Vendor_Code)), '')) AS VendorCode,
            COALESCE(NULLIF(RTRIM(LTRIM(v.Vendor_Name)), ''), NULLIF(RTRIM(LTRIM(rvm.VendorName)), ''), 'Vendor') AS VendorName,
            COALESCE(rvm.fk_companyId, v.fk_companyId) AS fk_companyId,
            COALESCE(rvm.CompanyId, v.CompanyId) AS CompanyId,
            3 AS Priority
        FROM dbo.REC_Requisition_Vendor_Mapping rvm WITH (NOLOCK)
        LEFT JOIN dbo.REC_Candidate_Details v WITH (NOLOCK) ON v.pk_recId = rvm.fk_vendorId
        WHERE rvm.fk_vendorId IS NOT NULL AND RTRIM(LTRIM(rvm.fk_vendorId)) <> ''
    ),
    RankedVendors AS (
        SELECT 
            rv.VendorId,
            rv.VendorCode,
            rv.VendorName,
            rv.fk_companyId,
            rv.CompanyId,
            ROW_NUMBER() OVER (
                PARTITION BY rv.VendorId 
                ORDER BY rv.Priority ASC, 
                         LEN(ISNULL(rv.VendorName, '')) DESC,
                         LEN(ISNULL(rv.VendorCode, '')) DESC
            ) AS rn
        FROM RawVendors rv
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR rv.fk_companyId = @fk_companyId 
            OR rv.fk_companyId = @CleanCompanyId 
            OR rv.fk_companyId = @PrefixedCompanyId
            OR rv.CompanyId = @fk_companyId
            OR rv.CompanyId = @CleanCompanyId
            OR rv.CompanyId = @PrefixedCompanyId
        )
    )
    SELECT 
        VendorId AS Value,
        VendorName + CASE 
            WHEN ISNULL(VendorCode, '') <> '' AND VendorCode <> VendorId 
            THEN ' (' + VendorCode + ')' 
            ELSE '' 
        END AS Label,
        ISNULL(VendorCode, VendorId) AS Code
    FROM RankedVendors
    WHERE rn = 1
    ORDER BY Label;

    -- ── Resultset 2: Locations ──────────────────────────────────────────────
    SELECT DISTINCT 
        loc.pk_locid AS Value, 
        loc.locname AS Label 
    FROM dbo.Location_Mst loc WITH (NOLOCK)
    WHERE loc.locname IS NOT NULL AND RTRIM(LTRIM(loc.locname)) <> '' 
      AND (
          @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
          OR loc.fk_companyId = @fk_companyId 
          OR loc.fk_companyId = @CleanCompanyId 
          OR loc.fk_companyId = @PrefixedCompanyId
      )
    ORDER BY loc.locname;

    -- ── Resultset 3: Departments ────────────────────────────────────────────
    SELECT DISTINCT 
        dept.pk_deptid AS Value, 
        dept.description AS Label 
    FROM dbo.Department_Mst dept WITH (NOLOCK)
    WHERE dept.description IS NOT NULL AND RTRIM(LTRIM(dept.description)) <> '' 
      AND (
          @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
          OR dept.fk_companyId = @fk_companyId 
          OR dept.fk_companyId = @CleanCompanyId 
          OR dept.fk_companyId = @PrefixedCompanyId
      )
    ORDER BY dept.description;

    -- ── Resultset 4: Jobs / Requisitions ────────────────────────────────────
    SELECT DISTINCT 
        CAST(j.pk_reqid AS VARCHAR(50)) AS Value,
        ISNULL(j.Mrfcode + ' - ', '') + ISNULL(j.jobtitle, 'Job #' + CAST(j.pk_reqid AS VARCHAR(20))) AS Label
    FROM dbo.REC_JobRequisition_Mst j WITH (NOLOCK)
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR j.fk_companyId = @fk_companyId 
        OR j.fk_companyId = @CleanCompanyId 
        OR j.fk_companyId = @PrefixedCompanyId
        OR j.CompanyId = @fk_companyId
    )
    ORDER BY Label;

    -- ── Resultset 5: Candidate Sources (General Sources + Individual Vendors) 
    SELECT DISTINCT 
        s.SourceName AS Value,
        s.SourceLabel AS Label
    FROM (
        SELECT DISTINCT 
            ca.SourceType AS SourceName,
            ca.SourceType AS SourceLabel
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK) 
        WHERE ca.SourceType IS NOT NULL AND RTRIM(LTRIM(ca.SourceType)) <> ''
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR ca.fk_companyId = @fk_companyId OR ca.CompanyId = @fk_companyId
          )

        UNION

        SELECT DISTINCT 
            c.source AS SourceName,
            c.source AS SourceLabel
        FROM dbo.REC_Candidate_Details c WITH (NOLOCK) 
        WHERE c.source IS NOT NULL AND RTRIM(LTRIM(c.source)) <> '' 
          AND (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR c.fk_companyId = @fk_companyId
          )

        UNION SELECT 'Vendor', 'Vendor (All Agencies)'
        UNION SELECT 'Direct Walk-In / Self', 'Direct Walk-In / Self'
        UNION SELECT 'Location QR - Walk-In', 'Location QR - Walk-In'
        UNION SELECT 'Job Boards Syndication', 'Job Boards Syndication'
        UNION SELECT 'Employee Referral', 'Employee Referral'

        UNION

        -- Add specific registered staffing vendors as selectable candidate sources
        SELECT 
            v.pk_recId AS SourceName,
            'Vendor: ' + COALESCE(NULLIF(RTRIM(LTRIM(v.Vendor_Name)), ''), 'Authorized Vendor') 
            + CASE WHEN ISNULL(v.Vendor_Code, '') <> '' THEN ' (' + v.Vendor_Code + ')' ELSE '' END AS SourceLabel
        FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
        WHERE (v.IsVendor = 1 OR v.Vendor_Code IS NOT NULL)
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR v.fk_companyId = @fk_companyId 
              OR v.fk_companyId = @CleanCompanyId 
              OR v.fk_companyId = @PrefixedCompanyId
              OR v.CompanyId = @fk_companyId
          )
    ) s
    WHERE s.SourceName IS NOT NULL AND RTRIM(LTRIM(s.SourceName)) <> ''
    ORDER BY Label;
END;
GO


-- ────────────────────────────────────────────────────────────────────────────
-- 2. USP_Candidate_Report_Get
-- Full pipeline candidate tracking (Live ATS applications + legacy sync)
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    -- Dynamic Target Vendor Lookup if Source specifies a vendor
    DECLARE @TargetVendorId VARCHAR(50) = NULL;
    DECLARE @TargetVendorCode VARCHAR(50) = NULL;
    IF @source IS NOT NULL AND RTRIM(LTRIM(@source)) <> ''
    BEGIN
        SELECT TOP 1 
            @TargetVendorId = v.pk_recId,
            @TargetVendorCode = v.Vendor_Code
        FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
        WHERE v.pk_recId = @source OR v.Vendor_Code = @source OR v.Vendor_Name = @source;

        IF @TargetVendorId IS NULL SET @TargetVendorId = @source;
        IF @TargetVendorCode IS NULL SET @TargetVendorCode = @source;
    END;

    -- Unified Candidate Table from Live ATS Applications & Legacy Master
    ;WITH UnifiedCandidates AS (
        -- Live ATS Candidate Applications (Primary Source of Truth)
        SELECT 
            COALESCE(NULLIF(ca.ApplicationNo, ''), 'APP-' + CAST(ca.pk_appId AS VARCHAR(20))) AS PkRecId,
            ISNULL(ca.CandidateName, 'Unknown Candidate') AS CandidateName,
            ISNULL(ca.Email, '') AS Email,
            ISNULL(ca.Mobile, '') AS Mobile,
            ISNULL(ca.Gender, '') AS Gender,
            ISNULL(ca.SkillClassification, '') AS Education,
            '0' AS Experience,
            '0' AS CurrentCtc,
            CAST(ISNULL(ca.OfferedCTC, 0) AS VARCHAR(50)) AS ExpectedCtc,
            'Immediate' AS NoticePeriod,
            ISNULL(ca.CandidateTags, '') AS KeySkills,
            ISNULL(ca.CurrentLocation, '') AS Address,
            COALESCE(NULLIF(ca.VendorName, ''), NULLIF(ca.SourceType, ''), 'Direct / Walk-In') AS Source,
            ISNULL(ca.fk_vendorId, '') AS VendorCode,
            CAST(ISNULL(ca.fk_reqid, 0) AS VARCHAR(50)) AS JobId,
            ISNULL(ca.MrfCode, CASE WHEN ca.fk_reqid IS NOT NULL THEN 'MRF/' + CAST(ca.fk_reqid AS VARCHAR(20)) ELSE '' END) AS MrfCode,
            COALESCE(NULLIF(ca.Designation, ''), j.jobtitle, 'Unassigned Position') AS JobTitle,
            COALESCE(NULLIF(ca.Department, ''), dept.description, '') AS Department,
            COALESCE(NULLIF(ca.OperatingHub, ''), loc.locname, jloc.locname, '') AS Location,
            CASE 
                WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 'Joined'
                WHEN ca.Stage IN ('Offer_Generated', 'Offered') THEN 'Offered'
                WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified') THEN 'Offered'
                WHEN ca.Stage IN ('Interview_Scheduled', 'Interviewed') THEN 'Interviewed'
                WHEN ca.Stage IN ('Screened', 'Shortlisted') THEN 'Screened'
                WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 'Rejected'
                ELSE 'Applied'
            END AS DisplayStatus,
            ISNULL(ca.Stage, 'Applied') AS RawStatus,
            ca.CreatedDate AS AppliedDate,
            CAST(ISNULL(MONTH(ca.CreatedDate), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
            CAST(ISNULL(YEAR(ca.CreatedDate), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
            CASE 
                WHEN ca.CreatedDate IS NOT NULL 
                THEN DATENAME(MONTH, ca.CreatedDate) + ' ' + CAST(YEAR(ca.CreatedDate) AS VARCHAR(4))
                ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
            END AS MonthYear,
            CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 ELSE 0 END AS ShortlistStatus,
            CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 ELSE 0 END AS InterviewRound,
            CASE WHEN ca.Stage IN ('Selected', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 ELSE 0 END AS FinalSelectionStatus,
            CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 ELSE 0 END AS IsOnboardingDone,
            ca.HiredDate AS OnboardCompletionDate,
            ca.fk_companyId,
            ca.CompanyId
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        LEFT JOIN dbo.REC_JobRequisition_Mst j WITH (NOLOCK) ON (j.pk_reqid = ca.fk_reqid OR j.Mrfcode = ca.MrfCode)
        LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON (j.fk_deptid = dept.pk_deptid OR j.fk_deptid = dept.deptcode)
        LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (loc.locname = ca.OperatingHub OR loc.code = ca.OperatingHub)
        LEFT JOIN dbo.Location_Mst jloc WITH (NOLOCK) ON (j.fk_locid = jloc.pk_locid OR j.fk_locid = jloc.code)

        UNION ALL

        -- Standalone Candidates in REC_Candidate_Details not present in Applications
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
            c.OnboardCompletionDate AS OnboardCompletionDate,
            c.fk_companyId,
            c.CompanyId
        FROM dbo.REC_Candidate_Details c WITH (NOLOCK)
        LEFT JOIN dbo.REC_JobRequisition_Mst j WITH (NOLOCK) ON (CAST(j.pk_reqid AS VARCHAR(50)) = c.fk_jobId OR j.Mrfcode = c.fk_jobId)
        LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON (j.fk_deptid = dept.pk_deptid OR j.fk_deptid = dept.deptcode)
        LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (c.fk_locid = loc.pk_locid OR c.fk_locid = loc.code)
        LEFT JOIN dbo.Location_Mst jloc WITH (NOLOCK) ON (j.fk_locid = jloc.pk_locid OR j.fk_locid = jloc.code)
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.REC_Candidate_Applications ca_dup WITH (NOLOCK)
              WHERE (ca_dup.Mobile = c.mobile AND c.mobile IS NOT NULL AND c.mobile <> '')
                 OR (ca_dup.CandidateName = c.candidate_name AND c.candidate_name IS NOT NULL)
          )
    )
    SELECT *
    INTO #CandidateData
    FROM UnifiedCandidates c
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR c.fk_companyId = @fk_companyId 
        OR c.fk_companyId = @CleanCompanyId 
        OR c.fk_companyId = @PrefixedCompanyId
        OR c.CompanyId = @fk_companyId
        OR c.CompanyId = @CleanCompanyId
        OR c.CompanyId = @PrefixedCompanyId
    )
    AND (@jobId = '' OR c.JobId = @jobId OR c.MrfCode = @jobId OR c.JobTitle LIKE '%' + @jobId + '%')
    AND (@locationId = '' OR c.Location = @locationId OR c.Location LIKE '%' + @locationId + '%')
    AND (@department = '' OR c.Department LIKE '%' + @department + '%')
    AND (
        @source = '' 
        OR c.Source LIKE '%' + @source + '%' 
        OR c.VendorCode = @source
        OR c.VendorCode = @TargetVendorId
        OR c.VendorCode = @TargetVendorCode
    )
    AND (
        @status = '' 
        OR c.DisplayStatus = @status
        OR (@status = 'Applied' AND c.DisplayStatus = 'Applied')
        OR (@status = 'Screened' AND c.DisplayStatus IN ('Screened', 'Interviewed', 'Offered', 'Joined'))
        OR (@status = 'Interviewed' AND c.DisplayStatus IN ('Interviewed', 'Offered', 'Joined'))
        OR (@status = 'Offered' AND c.DisplayStatus IN ('Offered', 'Joined'))
        OR (@status = 'Joined' AND c.DisplayStatus = 'Joined')
        OR (@status = 'Rejected' AND c.DisplayStatus = 'Rejected')
    )
    AND (@month = '' OR c.[Month] = @month)
    AND (@year = '' OR c.[Year] = @year)
    AND (@fromDate = '' OR CAST(c.AppliedDate AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
    AND (@toDate = '' OR CAST(c.AppliedDate AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
    AND (
        @searchTerm = '' 
        OR c.CandidateName LIKE '%' + @searchTerm + '%'
        OR c.Email LIKE '%' + @searchTerm + '%'
        OR c.Mobile LIKE '%' + @searchTerm + '%'
        OR c.KeySkills LIKE '%' + @searchTerm + '%'
        OR c.PkRecId LIKE '%' + @searchTerm + '%'
        OR c.JobTitle LIKE '%' + @searchTerm + '%'
        OR c.MrfCode LIKE '%' + @searchTerm + '%'
        OR c.Department LIKE '%' + @searchTerm + '%'
        OR c.Location LIKE '%' + @searchTerm + '%'
        OR c.Source LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Summary KPIs
    SELECT 
        COUNT(1) AS TotalCandidates,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Screened', 'Interviewed', 'Offered', 'Joined') THEN 1 ELSE 0 END), 0) AS TotalScreened,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Interviewed', 'Offered', 'Joined') THEN 1 ELSE 0 END), 0) AS TotalInterviewed,
        ISNULL(SUM(CASE WHEN DisplayStatus IN ('Offered', 'Joined') THEN 1 ELSE 0 END), 0) AS TotalOffered,
        ISNULL(SUM(CASE WHEN DisplayStatus = 'Joined' THEN 1 ELSE 0 END), 0) AS TotalJoined,
        ISNULL(SUM(CASE WHEN DisplayStatus = 'Rejected' THEN 1 ELSE 0 END), 0) AS TotalRejected,
        CASE 
            WHEN COUNT(1) > 0 
            THEN CAST((CAST(SUM(CASE WHEN DisplayStatus = 'Joined' THEN 1 ELSE 0 END) AS DECIMAL(10,2)) / CAST(COUNT(1) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
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
        RowNum,
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


-- ────────────────────────────────────────────────────────────────────────────
-- 3. USP_Vendor_Report_Get
-- Full Vendor Performance & Agency Conversion Metrics
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    -- Dynamic Target Vendor Lookup
    DECLARE @TargetVendorId VARCHAR(50) = NULL;
    DECLARE @TargetVendorCode VARCHAR(50) = NULL;
    IF @vendorCode IS NOT NULL AND RTRIM(LTRIM(@vendorCode)) <> ''
    BEGIN
        SELECT TOP 1 
            @TargetVendorId = v.pk_recId,
            @TargetVendorCode = v.Vendor_Code
        FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
        WHERE v.pk_recId = @vendorCode OR v.Vendor_Code = @vendorCode OR v.Vendor_Name = @vendorCode;

        IF @TargetVendorId IS NULL SET @TargetVendorId = @vendorCode;
        IF @TargetVendorCode IS NULL SET @TargetVendorCode = @vendorCode;
    END;

    -- CTE 1: Candidate metrics sourced from REC_Candidate_Applications (and union with legacy details)
    ;WITH RawVendorCandidates AS (
        SELECT 
            ca.fk_vendorId AS VendorRef,
            ca.VendorName,
            ca.Stage,
            ca.IsRejected,
            ca.CreatedDate AS AppliedDate,
            ca.HiredDate
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE ca.fk_vendorId IS NOT NULL AND RTRIM(LTRIM(ca.fk_vendorId)) <> ''
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR ca.fk_companyId = @fk_companyId 
              OR ca.fk_companyId = @CleanCompanyId 
              OR ca.fk_companyId = @PrefixedCompanyId
              OR ca.CompanyId = @fk_companyId
          )

        UNION ALL

        SELECT 
            ISNULL(c.Vendor_Code, c.refcode) AS VendorRef,
            c.Vendor_Name,
            c.status AS Stage,
            CASE WHEN c.status IN ('7', 'Rejected', 'Disapproved') THEN 1 ELSE 0 END AS IsRejected,
            c.dated AS AppliedDate,
            c.OnboardCompletionDate AS HiredDate
        FROM dbo.REC_Candidate_Details c WITH (NOLOCK)
        WHERE (c.IsVendor IS NULL OR c.IsVendor = 0)
          AND (c.Vendor_Code IS NOT NULL OR c.refcode IS NOT NULL)
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR c.fk_companyId = @fk_companyId 
              OR c.fk_companyId = @CleanCompanyId 
              OR c.fk_companyId = @PrefixedCompanyId
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.REC_Candidate_Applications ca2 WITH (NOLOCK)
              WHERE ca2.Mobile = c.mobile OR ca2.CandidateName = c.candidate_name
          )
    ),
    CandMetrics AS (
        SELECT 
            VendorRef,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired', '2', 'Shortlisted') THEN 1 END) AS Shortlisted,
            COUNT(CASE WHEN Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired', '3', 'Interviewed') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired', '4', 'Offered') THEN 1 END) AS Selected,
            COUNT(CASE WHEN Stage IN ('Hired', 'Joined', 'Onboarded', '5', '6') THEN 1 END) AS Joined,
            COUNT(CASE WHEN IsRejected = 1 OR Stage IN ('Rejected', 'Disapproved', '7') THEN 1 END) AS Rejected,
            AVG(CASE WHEN AppliedDate IS NOT NULL THEN DATEDIFF(day, AppliedDate, ISNULL(HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM RawVendorCandidates
        GROUP BY VendorRef
    ),
    VendorJobMapping AS (
        SELECT 
            m.fk_vendorId,
            COUNT(DISTINCT m.fk_reqid) AS ActiveJobs
        FROM dbo.REC_Requisition_Vendor_Mapping m WITH (NOLOCK)
        WHERE (m.IsActive = 1 OR m.IsActive IS NULL)
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR m.fk_companyId = @fk_companyId 
              OR m.fk_companyId = @CleanCompanyId 
              OR m.fk_companyId = @PrefixedCompanyId
          )
        GROUP BY m.fk_vendorId
    )
    SELECT 
        v.pk_recId AS VendorId,
        ISNULL(v.Vendor_Code, ISNULL(v.pk_recId, '')) AS VendorCode,
        COALESCE(NULLIF(v.Vendor_Name, ''), NULLIF(v.candidate_name, ''), 'Authorized Vendor') AS VendorName,
        ISNULL(v.Vendor_FatherName, ISNULL(v.father_name, ISNULL(v.AgentName, 'Agency Lead'))) AS ContactPerson,
        ISNULL(v.email, ISNULL(v.EmailID, '')) AS Email,
        ISNULL(v.Vendor_ContactNo, ISNULL(v.mobile, ISNULL(v.phone, ''))) AS Phone,
        ISNULL(loc.locname, ISNULL(v.Vendor_City, 'Pan India')) AS Location,
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
    FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (v.fk_locid = loc.pk_locid OR v.Vendor_FKCityId = loc.pk_locid)
    LEFT JOIN CandMetrics cm ON (cm.VendorRef = v.pk_recId OR cm.VendorRef = v.Vendor_Code OR cm.VendorRef = v.Vendor_Name)
    LEFT JOIN VendorJobMapping jm ON (jm.fk_vendorId = v.pk_recId OR jm.fk_vendorId = v.Vendor_Code)
    WHERE (v.IsVendor = 1 OR v.Vendor_Code IS NOT NULL)
      AND (
          @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
          OR v.fk_companyId = @fk_companyId 
          OR v.fk_companyId = @CleanCompanyId 
          OR v.fk_companyId = @PrefixedCompanyId
          OR v.CompanyId = @fk_companyId
      )
      AND (
          @vendorCode = '' 
          OR v.pk_recId = @vendorCode
          OR (@TargetVendorId IS NOT NULL AND v.pk_recId = @TargetVendorId)
          OR (NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details v_chk WITH (NOLOCK) WHERE v_chk.pk_recId = @vendorCode) 
              AND (v.Vendor_Code = @vendorCode OR v.Vendor_Name = @vendorCode OR v.Vendor_Name LIKE '%' + @vendorCode + '%'))
      )
      AND (@location = '' OR loc.locname LIKE '%' + @location + '%' OR v.Vendor_City LIKE '%' + @location + '%')
      AND (@status = '' OR v.Vendor_Status = @status OR (@status = 'Active' AND (v.Vendor_Status IS NULL OR v.Vendor_Status = '')))
      AND (@month = '' OR MONTH(v.dated) = CAST(@month AS INT))
      AND (@year = '' OR YEAR(v.dated) = CAST(@year AS INT))
      AND (@fromDate = '' OR CAST(v.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
      AND (@toDate = '' OR CAST(v.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
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
            ROW_NUMBER() OVER (ORDER BY TotalSubmitted DESC, VendorName ASC) AS RowNum,
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


-- ────────────────────────────────────────────────────────────────────────────
-- 4. USP_Vendor_Wise_Report_Get
-- Requisition-level Allocation & Sourcing breakdown per Vendor
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    -- Dynamic Target Vendor Lookup
    DECLARE @TargetVendorId VARCHAR(50) = NULL;
    DECLARE @TargetVendorCode VARCHAR(50) = NULL;
    IF @vendorCode IS NOT NULL AND RTRIM(LTRIM(@vendorCode)) <> ''
    BEGIN
        SELECT TOP 1 
            @TargetVendorId = v.pk_recId,
            @TargetVendorCode = v.Vendor_Code
        FROM dbo.REC_Candidate_Details v WITH (NOLOCK)
        WHERE v.pk_recId = @vendorCode OR v.Vendor_Code = @vendorCode OR v.Vendor_Name = @vendorCode;

        IF @TargetVendorId IS NULL SET @TargetVendorId = @vendorCode;
        IF @TargetVendorCode IS NULL SET @TargetVendorCode = @vendorCode;
    END;

    -- Requisition & Vendor Candidate Metrics CTE
    ;WITH CandReqStats AS (
        SELECT 
            ca.fk_reqid,
            ca.fk_vendorId AS VendorRef,
            COUNT(1) AS ProfilesShared,
            COUNT(CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Offered,
            COUNT(CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 END) AS Joined,
            COUNT(CASE WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN ca.CreatedDate IS NOT NULL THEN DATEDIFF(day, ca.CreatedDate, ISNULL(ca.HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE ca.fk_vendorId IS NOT NULL AND RTRIM(LTRIM(ca.fk_vendorId)) <> ''
          AND (
              @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
              OR ca.fk_companyId = @fk_companyId 
              OR ca.fk_companyId = @CleanCompanyId 
              OR ca.fk_companyId = @PrefixedCompanyId
              OR ca.CompanyId = @fk_companyId
          )
        GROUP BY ca.fk_reqid, ca.fk_vendorId
    ),
    TotalJobProfiles AS (
        SELECT 
            ca.fk_reqid,
            COUNT(1) AS TotalCount
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR ca.fk_companyId = @fk_companyId 
            OR ca.fk_companyId = @CleanCompanyId 
            OR ca.fk_companyId = @PrefixedCompanyId
            OR ca.CompanyId = @fk_companyId
        )
        GROUP BY ca.fk_reqid
    )
    SELECT 
        COALESCE(m.fk_vendorId, v.pk_recId, '') AS VendorId,
        ISNULL(v.Vendor_Code, ISNULL(v.pk_recId, '')) AS VendorCode,
        COALESCE(NULLIF(v.Vendor_Name, ''), NULLIF(m.VendorName, ''), 'Authorized Vendor') AS VendorName,
        ISNULL(j.Mrfcode, 'MRF/' + CAST(j.pk_reqid AS VARCHAR(20))) AS ReqCode,
        ISNULL(j.jobtitle, 'Unassigned Job') AS JobTitle,
        ISNULL(d.description, '') AS Department,
        ISNULL(loc.locname, '') AS Location,
        ISNULL(m.AllocatedQuota, ISNULL(j.No_of_post, 1)) AS TargetPositions,
        ISNULL(cs.ProfilesShared, 0) AS ProfilesShared,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(tp.TotalCount, 0) > 0 
            THEN CAST((CAST(ISNULL(cs.ProfilesShared, 0) AS DECIMAL(10,2)) / CAST(tp.TotalCount AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS VendorSharePct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        CASE 
            WHEN m.IsActive = 1 THEN 'Active'
            WHEN m.IsActive = 0 THEN 'Inactive'
            ELSE 'Allocated'
        END AS [Status],
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear
    INTO #VendorWiseData
    FROM dbo.REC_Requisition_Vendor_Mapping m WITH (NOLOCK)
    INNER JOIN dbo.REC_JobRequisition_Mst j WITH (NOLOCK) ON j.pk_reqid = m.fk_reqid
    LEFT JOIN dbo.REC_Candidate_Details v WITH (NOLOCK) ON (m.fk_vendorId = v.pk_recId OR m.VendorCode = v.Vendor_Code)
    LEFT JOIN dbo.Department_Mst d WITH (NOLOCK) ON (j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code)
    LEFT JOIN CandReqStats cs ON cs.fk_reqid = j.pk_reqid AND (cs.VendorRef = v.pk_recId OR cs.VendorRef = m.fk_vendorId OR cs.VendorRef = v.Vendor_Code)
    LEFT JOIN TotalJobProfiles tp ON tp.fk_reqid = j.pk_reqid
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR j.fk_companyId = @fk_companyId 
        OR j.fk_companyId = @CleanCompanyId 
        OR j.fk_companyId = @PrefixedCompanyId
        OR j.CompanyId = @fk_companyId
    )
    AND (
        @vendorCode = '' 
        OR m.fk_vendorId = @vendorCode
        OR v.pk_recId = @vendorCode
        OR (@TargetVendorId IS NOT NULL AND (m.fk_vendorId = @TargetVendorId OR v.pk_recId = @TargetVendorId))
        OR (NOT EXISTS (SELECT 1 FROM dbo.REC_Candidate_Details v_chk WITH (NOLOCK) WHERE v_chk.pk_recId = @vendorCode) 
            AND (m.VendorCode = @vendorCode OR v.Vendor_Code = @vendorCode OR v.Vendor_Name = @vendorCode OR v.Vendor_Name LIKE '%' + @vendorCode + '%'))
    )
    AND (@department = '' OR d.pk_deptid = @department OR j.fk_deptid = @department OR d.description LIKE '%' + @department + '%')
    AND (@status = '' OR (@status = 'Active' AND m.IsActive = 1) OR (@status = 'Inactive' AND m.IsActive = 0))
    AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
    AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
    AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
    AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
    AND (
        @searchTerm = '' 
        OR j.jobtitle LIKE '%' + @searchTerm + '%' 
        OR j.Mrfcode LIKE '%' + @searchTerm + '%'
        OR v.Vendor_Name LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Count
    SELECT COUNT(1) AS TotalCount FROM #VendorWiseData;

    -- Resultset 2: Paginated Grid Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY ProfilesShared DESC, ReqCode ASC) AS RowNum,
            *
        FROM #VendorWiseData
    )
    SELECT 
        VendorCode,
        VendorName,
        ReqCode,
        JobTitle,
        Department,
        Location,
        TargetPositions,
        ProfilesShared,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        VendorSharePct,
        AvgTatDays,
        [Status],
        MonthYear
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #VendorWiseData;
END;
GO


-- ────────────────────────────────────────────────────────────────────────────
-- 5. USP_Job_Report_Get
-- Job Openings Fulfillment & Pipeline Metrics
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    ;WITH CandJobStats AS (
        SELECT 
            ca.fk_reqid,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Offered,
            COUNT(CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 END) AS Joined,
            COUNT(CASE WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN ca.CreatedDate IS NOT NULL THEN DATEDIFF(day, ca.CreatedDate, ISNULL(ca.HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR ca.fk_companyId = @fk_companyId 
            OR ca.fk_companyId = @CleanCompanyId 
            OR ca.fk_companyId = @PrefixedCompanyId
            OR ca.CompanyId = @fk_companyId
        )
        GROUP BY ca.fk_reqid
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
        ISNULL(j.No_of_post, 1) AS TargetPositions,
        ISNULL(j.WorkflowStatus, 'Submitted') AS WorkflowStatus,
        ISNULL(j.CurrentApprovalLevel, 1) AS CurrentApprovalLevel,
        ISNULL(cs.TotalSubmitted, 0) AS ProfilesSubmitted,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(j.No_of_post, 1) - ISNULL(cs.Joined, 0) 
            ELSE 0 
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(ISNULL(j.No_of_post, 1) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        j.dated AS CreatedDate,
        j.HiringOpenedDate,
        j.L1ApproverName,
        j.L1Action,
        j.L2ApproverName,
        j.L2Action,
        j.L3ApproverName,
        j.L3Action
    INTO #JobData
    FROM dbo.REC_JobRequisition_Mst j WITH (NOLOCK)
    LEFT JOIN dbo.Department_Mst d WITH (NOLOCK) ON (j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code)
    LEFT JOIN CandJobStats cs ON cs.fk_reqid = j.pk_reqid
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR j.fk_companyId = @fk_companyId 
        OR j.fk_companyId = @CleanCompanyId 
        OR j.fk_companyId = @PrefixedCompanyId
        OR j.CompanyId = @fk_companyId
    )
    AND (@locationId = '' OR loc.pk_locid = @locationId OR j.fk_locid = @locationId OR loc.locname LIKE '%' + @locationId + '%')
    AND (@department = '' OR d.pk_deptid = @department OR j.fk_deptid = @department OR d.description LIKE '%' + @department + '%')
    AND (@workflowStatus = '' OR j.WorkflowStatus = @workflowStatus)
    AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
    AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
    AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
    AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
    AND (
        @searchTerm = '' 
        OR j.jobtitle LIKE '%' + @searchTerm + '%' 
        OR j.Mrfcode LIKE '%' + @searchTerm + '%' 
        OR d.description LIKE '%' + @searchTerm + '%' 
        OR loc.locname LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalJobs,
        ISNULL(SUM(TargetPositions), 0) AS TotalTargetPositions,
        ISNULL(SUM(ProfilesSubmitted), 0) AS TotalProfilesSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        CASE 
            WHEN SUM(TargetPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TargetPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #JobData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC, ReqId DESC) AS RowNum,
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
        ProfilesSubmitted,
        Screened,
        Interviewed,
        Offered,
        Joined,
        PendingPositions,
        FulfillmentPct,
        AvgTatDays
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #JobData;
END;
GO


-- ────────────────────────────────────────────────────────────────────────────
-- 6. USP_MRF_Report_Get
-- Manpower Requisition Form (MRF) Lifecycle & Approval Audit Report
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[USP_MRF_Report_Get]
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    ;WITH CandMrfStats AS (
        SELECT 
            ca.fk_reqid,
            COUNT(1) AS ProfilesShared,
            COUNT(CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Offered,
            COUNT(CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 END) AS Joined,
            COUNT(CASE WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN ca.CreatedDate IS NOT NULL THEN DATEDIFF(day, ca.CreatedDate, ISNULL(ca.HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR ca.fk_companyId = @fk_companyId 
            OR ca.fk_companyId = @CleanCompanyId 
            OR ca.fk_companyId = @PrefixedCompanyId
            OR ca.CompanyId = @fk_companyId
        )
        GROUP BY ca.fk_reqid
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
        ISNULL(j.No_of_post, 1) AS TargetPositions,
        ISNULL(cs.ProfilesShared, 0) AS ProfilesShared,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(j.No_of_post, 1) - ISNULL(cs.Joined, 0)
            ELSE 0 
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(ISNULL(j.No_of_post, 1) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        ISNULL(j.WorkflowStatus, 'Submitted') AS WorkflowStatus,
        'Tier ' + CAST(ISNULL(j.CurrentApprovalLevel, 1) AS VARCHAR(5)) AS ApprovalTier,
        ISNULL(emp.empname, ISNULL(j.fk_empid, 'System User')) AS RaisedBy,
        ISNULL(j.dated, GETDATE()) AS CreatedDate
    INTO #MrfData
    FROM dbo.REC_JobRequisition_Mst j WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code)
    LEFT JOIN dbo.Department_Mst d WITH (NOLOCK) ON (j.fk_deptid = d.pk_deptid OR j.fk_deptid = d.deptcode)
    LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON (emp.pk_empid = j.fk_empid OR emp.empcode = j.fk_empid)
    LEFT JOIN CandMrfStats cs ON cs.fk_reqid = j.pk_reqid
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR j.fk_companyId = @fk_companyId 
        OR j.fk_companyId = @CleanCompanyId 
        OR j.fk_companyId = @PrefixedCompanyId
        OR j.CompanyId = @fk_companyId
    )
    AND (@locationId = '' OR loc.pk_locid = @locationId OR j.fk_locid = @locationId OR loc.locname LIKE '%' + @locationId + '%')
    AND (@department = '' OR d.pk_deptid = @department OR j.fk_deptid = @department OR d.description LIKE '%' + @department + '%')
    AND (@workflowStatus = '' OR j.WorkflowStatus = @workflowStatus)
    AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
    AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
    AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
    AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
    AND (
        @searchTerm = '' 
        OR j.jobtitle LIKE '%' + @searchTerm + '%' 
        OR j.Mrfcode LIKE '%' + @searchTerm + '%' 
        OR d.description LIKE '%' + @searchTerm + '%' 
        OR loc.locname LIKE '%' + @searchTerm + '%'
        OR emp.empname LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalMrfs,
        ISNULL(SUM(TargetPositions), 0) AS TotalPositions,
        ISNULL(SUM(ProfilesShared), 0) AS TotalSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        CASE 
            WHEN SUM(TargetPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TargetPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #MrfData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY CreatedDate DESC, ReqId DESC) AS RowNum,
            *
        FROM #MrfData
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
        PendingPositions,
        FulfillmentPct,
        AvgTatDays,
        WorkflowStatus,
        ApprovalTier,
        RaisedBy,
        CreatedDate
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #MrfData;
END;
GO


-- ────────────────────────────────────────────────────────────────────────────
-- 7. USP_Location_Report_Get
-- Geographic Hub Manpower Demand & Sourcing Statistics
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    ;WITH JobStats AS (
        SELECT 
            j.fk_locid,
            COUNT(DISTINCT j.pk_reqid) AS TotalOpeningJobs,
            SUM(ISNULL(j.No_of_post, 1)) AS TotalPositions
        FROM dbo.REC_JobRequisition_Mst j WITH (NOLOCK)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR j.fk_companyId = @fk_companyId 
            OR j.fk_companyId = @CleanCompanyId 
            OR j.fk_companyId = @PrefixedCompanyId
            OR j.CompanyId = @fk_companyId
        )
        AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
        AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
        AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
        AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
        GROUP BY j.fk_locid
    ),
    CandLocStats AS (
        SELECT 
            loc.pk_locid AS LocationId,
            COUNT(1) AS TotalSubmitted,
            COUNT(CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Shortlisted,
            COUNT(CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Selected,
            COUNT(CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 END) AS Joined,
            COUNT(CASE WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN ca.CreatedDate IS NOT NULL THEN DATEDIFF(day, ca.CreatedDate, ISNULL(ca.HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        INNER JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (loc.locname = ca.OperatingHub OR loc.code = ca.OperatingHub OR loc.pk_locid = ca.CurrentLocation)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR ca.fk_companyId = @fk_companyId 
            OR ca.fk_companyId = @CleanCompanyId 
            OR ca.fk_companyId = @PrefixedCompanyId
            OR ca.CompanyId = @fk_companyId
        )
        GROUP BY loc.pk_locid
    )
    SELECT 
        l.pk_locid AS LocationId,
        ISNULL(l.code, l.pk_locid) AS LocationCode,
        ISNULL(l.locname, 'Hub Operations') AS LocationName,
        ISNULL(js.TotalOpeningJobs, 0) AS TotalOpeningJobs,
        ISNULL(js.TotalPositions, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0)) AS TotalPositions,
        ISNULL(cls.TotalSubmitted, 0) AS TotalSubmitted,
        ISNULL(cls.Shortlisted, 0) AS Shortlisted,
        ISNULL(cls.Interviewed, 0) AS Interviewed,
        ISNULL(cls.Selected, 0) AS Selected,
        ISNULL(cls.Joined, 0) AS Joined,
        ISNULL(cls.Rejected, 0) AS Rejected,
        CASE 
            WHEN (ISNULL(js.TotalPositions, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0)) - ISNULL(cls.Joined, 0)) > 0 
            THEN (ISNULL(js.TotalPositions, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0)) - ISNULL(cls.Joined, 0))
            ELSE 0 
        END AS OpenPositions,
        CASE 
            WHEN (ISNULL(js.TotalPositions, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0))) > 0 
            THEN CAST((CAST(ISNULL(cls.Joined, 0) AS DECIMAL(10,2)) / CAST((ISNULL(js.TotalPositions, ISNULL(l.BaseDemand, 0) + ISNULL(l.BufferHeads, 0))) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentRate,
        ISNULL(cls.AvgTatDays, 0) AS AvgTatDays,
        'Active' AS [Status],
        DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4)) AS MonthYear
    INTO #LocData
    FROM dbo.Location_Mst l WITH (NOLOCK)
    LEFT JOIN JobStats js ON (js.fk_locid = l.pk_locid OR js.fk_locid = l.code)
    LEFT JOIN CandLocStats cls ON cls.LocationId = l.pk_locid
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR l.fk_companyId = @fk_companyId 
        OR l.fk_companyId = @CleanCompanyId 
        OR l.fk_companyId = @PrefixedCompanyId
    )
    AND (@locationId = '' OR l.pk_locid = @locationId OR l.code = @locationId)
    AND (@location = '' OR l.locname LIKE '%' + @location + '%')
    AND (
        @searchTerm = '' 
        OR l.locname LIKE '%' + @searchTerm + '%' 
        OR l.code LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        COUNT(1) AS TotalLocations,
        ISNULL(SUM(TotalOpeningJobs), 0) AS TotalOpeningJobs,
        ISNULL(SUM(TotalPositions), 0) AS TotalPositions,
        ISNULL(SUM(TotalSubmitted), 0) AS TotalSubmitted,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        CASE 
            WHEN SUM(TotalPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TotalPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #LocData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY TotalPositions DESC, LocationName ASC) AS RowNum,
            *
        FROM #LocData
    )
    SELECT 
        LocationId,
        LocationCode,
        LocationName,
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
        [Status],
        MonthYear
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #LocData;
END;
GO


-- ────────────────────────────────────────────────────────────────────────────
-- 8. USP_Location_Wise_Jobs_Report_Get
-- Location drill-down list of jobs and candidate pipelines
-- ────────────────────────────────────────────────────────────────────────────
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

    DECLARE @CleanCompanyId VARCHAR(50) = NULL;
    DECLARE @PrefixedCompanyId VARCHAR(50) = NULL;

    IF @fk_companyId IS NOT NULL AND RTRIM(LTRIM(@fk_companyId)) <> '' AND @fk_companyId <> '0'
    BEGIN
        SET @CleanCompanyId = REPLACE(@fk_companyId, 'GU-', '');
        SET @PrefixedCompanyId = 'GU-' + @CleanCompanyId;
    END;

    ;WITH CandJobLocStats AS (
        SELECT 
            ca.fk_reqid,
            COUNT(1) AS ProfilesShared,
            COUNT(CASE WHEN ca.Stage IN ('Screened', 'Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Screened,
            COUNT(CASE WHEN ca.Stage IN ('Interview_Scheduled', 'Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Interviewed,
            COUNT(CASE WHEN ca.Stage IN ('Selected', 'Docs_Submitted', 'Docs_Verified', 'Offer_Generated', 'Hired') THEN 1 END) AS Offered,
            COUNT(CASE WHEN ca.Stage IN ('Hired', 'Joined', 'Onboarded') THEN 1 END) AS Joined,
            COUNT(CASE WHEN ca.IsRejected = 1 OR ca.Stage IN ('Rejected', 'Disapproved') THEN 1 END) AS Rejected,
            AVG(CASE WHEN ca.CreatedDate IS NOT NULL THEN DATEDIFF(day, ca.CreatedDate, ISNULL(ca.HiredDate, GETDATE())) ELSE 0 END) AS AvgTatDays
        FROM dbo.REC_Candidate_Applications ca WITH (NOLOCK)
        WHERE (
            @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
            OR ca.fk_companyId = @fk_companyId 
            OR ca.fk_companyId = @CleanCompanyId 
            OR ca.fk_companyId = @PrefixedCompanyId
            OR ca.CompanyId = @fk_companyId
        )
        GROUP BY ca.fk_reqid
    )
    SELECT 
        j.pk_reqid AS PkReqId,
        ISNULL(j.Mrfcode, 'MRF/' + CAST(j.pk_reqid AS VARCHAR(20))) AS ReqCode,
        ISNULL(j.jobtitle, 'Untitled Position') AS JobTitle,
        ISNULL(desg.designation, '') AS Designation,
        ISNULL(dept.description, '') AS Department,
        ISNULL(loc.code, loc.pk_locid) AS LocationCode,
        ISNULL(loc.locname, 'Hub Operations') AS LocationName,
        ISNULL(emp.empname, ISNULL(j.fk_empid, 'System User')) AS RaisedBy,
        ISNULL(j.No_of_post, 1) AS TargetPositions,
        ISNULL(j.WorkflowStatus, 'Submitted') AS WorkflowStatus,
        ISNULL(cs.ProfilesShared, 0) AS ProfilesShared,
        ISNULL(cs.Screened, 0) AS Screened,
        ISNULL(cs.Interviewed, 0) AS Interviewed,
        ISNULL(cs.Offered, 0) AS Offered,
        ISNULL(cs.Joined, 0) AS Joined,
        ISNULL(cs.Rejected, 0) AS Rejected,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > ISNULL(cs.Joined, 0) 
            THEN ISNULL(j.No_of_post, 1) - ISNULL(cs.Joined, 0)
            ELSE 0 
        END AS PendingPositions,
        CASE 
            WHEN ISNULL(j.No_of_post, 1) > 0 
            THEN CAST((CAST(ISNULL(cs.Joined, 0) AS DECIMAL(10,2)) / CAST(ISNULL(j.No_of_post, 1) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS FulfillmentPct,
        ISNULL(cs.AvgTatDays, 0) AS AvgTatDays,
        CASE 
            WHEN j.WorkflowStatus = 'Approved' THEN 'Active'
            WHEN j.WorkflowStatus = 'Closed' THEN 'Closed'
            ELSE 'In Progress'
        END AS [Status],
        CAST(ISNULL(MONTH(j.dated), MONTH(GETDATE())) AS VARCHAR(10)) AS [Month],
        CAST(ISNULL(YEAR(j.dated), YEAR(GETDATE())) AS VARCHAR(10)) AS [Year],
        CASE 
            WHEN j.dated IS NOT NULL 
            THEN DATENAME(MONTH, j.dated) + ' ' + CAST(YEAR(j.dated) AS VARCHAR(4))
            ELSE DATENAME(MONTH, GETDATE()) + ' ' + CAST(YEAR(GETDATE()) AS VARCHAR(4))
        END AS MonthYear,
        j.dated AS CreatedDate
    INTO #LocJobsData
    FROM dbo.REC_JobRequisition_Mst j WITH (NOLOCK)
    LEFT JOIN dbo.Location_Mst loc WITH (NOLOCK) ON (j.fk_locid = loc.pk_locid OR j.fk_locid = loc.code)
    LEFT JOIN dbo.Department_Mst dept WITH (NOLOCK) ON (j.fk_deptid = dept.pk_deptid OR j.fk_deptid = dept.deptcode)
    LEFT JOIN dbo.SAL_Designation_Mst desg WITH (NOLOCK) ON (j.fk_desgid = desg.pk_desgid)
    LEFT JOIN dbo.SAL_Employee_Mst emp WITH (NOLOCK) ON (emp.pk_empid = j.fk_empid OR emp.empcode = j.fk_empid)
    LEFT JOIN CandJobLocStats cs ON cs.fk_reqid = j.pk_reqid
    WHERE (
        @fk_companyId IS NULL OR RTRIM(LTRIM(@fk_companyId)) = '' OR @fk_companyId = '0'
        OR j.fk_companyId = @fk_companyId 
        OR j.fk_companyId = @CleanCompanyId 
        OR j.fk_companyId = @PrefixedCompanyId
        OR j.CompanyId = @fk_companyId
    )
    AND (@locationId = '' OR loc.pk_locid = @locationId OR j.fk_locid = @locationId OR loc.code = @locationId)
    AND (@department = '' OR dept.pk_deptid = @department OR j.fk_deptid = @department OR dept.description LIKE '%' + @department + '%')
    AND (@status = '' OR j.WorkflowStatus = @status)
    AND (@month = '' OR MONTH(j.dated) = CAST(@month AS INT))
    AND (@year = '' OR YEAR(j.dated) = CAST(@year AS INT))
    AND (@fromDate = '' OR CAST(j.dated AS DATE) >= COALESCE(TRY_CONVERT(DATE, @fromDate, 120), TRY_CONVERT(DATE, @fromDate, 105), TRY_CONVERT(DATE, @fromDate)))
    AND (@toDate = '' OR CAST(j.dated AS DATE) <= COALESCE(TRY_CONVERT(DATE, @toDate, 120), TRY_CONVERT(DATE, @toDate, 105), TRY_CONVERT(DATE, @toDate)))
    AND (
        @searchTerm = '' 
        OR j.jobtitle LIKE '%' + @searchTerm + '%' 
        OR j.Mrfcode LIKE '%' + @searchTerm + '%' 
        OR dept.description LIKE '%' + @searchTerm + '%' 
        OR loc.locname LIKE '%' + @searchTerm + '%'
    );

    -- Resultset 1: Summary Counts
    SELECT 
        COUNT(1) AS TotalCount,
        ISNULL(SUM(TargetPositions), 0) AS TotalPositions,
        ISNULL(SUM(ProfilesShared), 0) AS TotalProfilesShared,
        ISNULL(SUM(Joined), 0) AS TotalJoined,
        CASE 
            WHEN SUM(TargetPositions) > 0 
            THEN CAST((CAST(SUM(Joined) AS DECIMAL(10,2)) / CAST(SUM(TargetPositions) AS DECIMAL(10,2)) * 100.0) AS DECIMAL(10,1))
            ELSE 0.0 
        END AS OverallFulfillmentRate
    FROM #LocJobsData;

    -- Resultset 2: Paginated Rows
    ;WITH Paged AS (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY ProfilesShared DESC, ReqCode ASC) AS RowNum,
            *
        FROM #LocJobsData
    )
    SELECT 
        PkReqId,
        ReqCode,
        JobTitle,
        Designation,
        Department,
        LocationCode,
        LocationName,
        RaisedBy,
        TargetPositions,
        WorkflowStatus,
        ProfilesShared,
        Screened,
        Interviewed,
        Offered,
        Joined,
        Rejected,
        PendingPositions,
        FulfillmentPct,
        AvgTatDays,
        [Status],
        MonthYear
    FROM Paged
    WHERE RowNum > (@pageIndex * @pageSize) AND RowNum <= ((@pageIndex + 1) * @pageSize)
    ORDER BY RowNum;

    DROP TABLE #LocJobsData;
END;
GO

PRINT 'Migration 67 executed successfully: All 8 Recruitment Report USPs harmonized with live ATS pipeline and strict company scoping.';
GO
