-- =========================================================================================
-- Script: 56_CJ_DARCL_Recruitment_Reports_WebPages_And_PageRights.sql
-- Description:
--   Registers 'Recruitment Reports' as a dynamic parent menu and registers all 7 recruitment
--   report screens as child web pages in dbo.UM_WebPage_Mst under Recruitment Management (Module ID 5).
--   Grants page rights in dbo.UM_UserPageRights to all authorized recruitment users and admins.
-- =========================================================================================

SET NOCOUNT ON;

DECLARE @moduleId TINYINT = 5; -- Recruitment Management
DECLARE @parentPageId INT;
DECLARE @maxPageId INT;

-- 1. Ensure Module 5 exists and is active
IF NOT EXISTS (SELECT 1 FROM dbo.UM_Module_Mst WHERE pk_moduleId = @moduleId)
BEGIN
    RAISERROR('Module ID 5 (Recruitment Management) does not exist.', 16, 1);
    RETURN;
END;

-- 2. Ensure or Insert Parent Menu: 'Recruitment Reports'
SELECT @parentPageId = pk_webpageId 
FROM dbo.UM_WebPage_Mst 
WHERE menucaption = 'Recruitment Reports' AND fk_moduleId = @moduleId;

IF @parentPageId IS NULL
BEGIN
    SELECT @maxPageId = ISNULL(MAX(pk_webpageId), 9020) FROM dbo.UM_WebPage_Mst;
    SET @parentPageId = @maxPageId + 1;

    INSERT INTO dbo.UM_WebPage_Mst (
        pk_webpageId,
        menucaption,
        webpagename,
        pagepath,
        tooltip,
        parentId,
        displayorder,
        activestatus,
        fk_moduleId,
        fk_pagetypeId,
        pagedescription,
        selectable,
        orderby,
        icon
    )
    VALUES (
        @parentPageId,
        'Recruitment Reports',
        'NONE',
        '#',
        'Recruitment & ATS Analytics & Reports',
        NULL,
        4, -- After Recruitment Masters (1), Recruitment Transactions (2), and ATS Talent Suite (3)
        1,
        @moduleId,
        1,
        'Recruitment & ATS Analytics & Reports for CJ DARCL Logistics',
        1,
        4,
        'feather feather-file-text'
    );

    PRINT 'Created Parent Menu: Recruitment Reports (pk_webpageId: ' + CAST(@parentPageId AS VARCHAR(10)) + ')';
END
ELSE
BEGIN
    PRINT 'Parent Menu Recruitment Reports already exists (pk_webpageId: ' + CAST(@parentPageId AS VARCHAR(10)) + ')';
END;

-- 3. Temporary table for the 7 report child pages
DECLARE @ReportPages TABLE (
    menucaption     VARCHAR(100),
    webpagename     VARCHAR(100),
    pagepath        VARCHAR(100),
    tooltip         VARCHAR(100),
    displayorder    INT,
    icon            VARCHAR(50)
);

INSERT INTO @ReportPages (menucaption, webpagename, pagepath, tooltip, displayorder, icon)
VALUES
('Candidate Report',           'RecCandidateReport',        'recruitment/recruitmentdashboard/candidate-report',          'Candidate Recruitment & Pipeline Report',      1, 'bi bi-person-lines-fill me-2'),
('Job Requisition Report',     'RecJobReport',              'recruitment/recruitmentdashboard/job-report',                'Job Requisitions Lifecycle Report',            2, 'bi bi-briefcase me-2'),
('MRF Status Report',          'RecMrfReport',              'recruitment/recruitmentdashboard/mrf-report',                'Manpower Requisition Form (MRF) Report',        3, 'bi bi-file-earmark-bar-graph me-2'),
('Location Wise Report',       'RecLocationReport',         'recruitment/recruitmentdashboard/location-report',           'Location Headcount & Distribution Report',     4, 'bi bi-geo-alt me-2'),
('Location Wise Jobs Report',  'RecLocationWiseJobsReport', 'recruitment/recruitmentdashboard/location-wise-jobs-report', 'Location Wise Active Jobs Report',            5, 'bi bi-building me-2'),
('Vendor Sourcing Report',     'RecVendorReport',           'recruitment/recruitmentdashboard/vendor-report',             'Vendor Performance & Candidate Sourcing Report', 6, 'bi bi-shop me-2'),
('Vendor Wise Report',         'RecVendorWiseReport',       'recruitment/recruitmentdashboard/vendor-wise-report',        'Vendor-wise Breakdown & Analytics Report',     7, 'bi bi-pie-chart me-2');

-- 4. Cursor / Loop to insert child pages
DECLARE @curCaption VARCHAR(100), @curPageName VARCHAR(100), @curPath VARCHAR(100), @curTip VARCHAR(100), @curOrder INT, @curIcon VARCHAR(50);
DECLARE @newPageId INT;

DECLARE page_cursor CURSOR FOR 
SELECT menucaption, webpagename, pagepath, tooltip, displayorder, icon FROM @ReportPages ORDER BY displayorder;

OPEN page_cursor;
FETCH NEXT FROM page_cursor INTO @curCaption, @curPageName, @curPath, @curTip, @curOrder, @curIcon;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.UM_WebPage_Mst WHERE menucaption = @curCaption AND fk_moduleId = @moduleId)
    BEGIN
        SELECT @maxPageId = ISNULL(MAX(pk_webpageId), 9030) FROM dbo.UM_WebPage_Mst;
        SET @newPageId = @maxPageId + 1;

        INSERT INTO dbo.UM_WebPage_Mst (
            pk_webpageId,
            menucaption,
            webpagename,
            pagepath,
            tooltip,
            parentId,
            displayorder,
            activestatus,
            fk_moduleId,
            fk_pagetypeId,
            pagedescription,
            selectable,
            orderby,
            icon
        )
        VALUES (
            @newPageId,
            @curCaption,
            @curPageName,
            @curPath,
            @curTip,
            @parentPageId,
            @curOrder,
            1,
            @moduleId,
            1,
            @curCaption + ' (Recruitment Management)',
            1,
            @curOrder,
            @curIcon
        );

        PRINT 'Inserted WebPage: ' + @curCaption + ' (pk_webpageId: ' + CAST(@newPageId AS VARCHAR(10)) + ')';
    END
    ELSE
    BEGIN
        -- Update existing record to guarantee parentId, path, and icon are correct
        UPDATE dbo.UM_WebPage_Mst
        SET parentId     = @parentPageId,
            pagepath     = @curPath,
            displayorder = @curOrder,
            activestatus = 1,
            icon         = @curIcon
        WHERE menucaption = @curCaption AND fk_moduleId = @moduleId;

        PRINT 'Updated WebPage: ' + @curCaption;
    END;

    FETCH NEXT FROM page_cursor INTO @curCaption, @curPageName, @curPath, @curTip, @curOrder, @curIcon;
END;

CLOSE page_cursor;
DEALLOCATE page_cursor;

-- 5. Grant Page Rights to all users associated with Recruitment Module or active admin/HR roles
DECLARE @TargetUsers TABLE (fk_userId VARCHAR(15));

INSERT INTO @TargetUsers (fk_userId)
SELECT DISTINCT fk_userId FROM dbo.UM_UserModuleDetails WHERE fk_moduleId = @moduleId
UNION
SELECT DISTINCT fk_userId FROM dbo.UM_UserPageRights WHERE fk_webpageId IN (SELECT pk_webpageId FROM dbo.UM_WebPage_Mst WHERE fk_moduleId = @moduleId)
UNION
SELECT pk_userId FROM dbo.UM_Users_Mst WHERE pk_userId IN ('GU-1', 'GU-15', 'GU-7') AND active = 1;

-- All Recruitment Reports web page IDs (parent + 7 children)
DECLARE @TargetPages TABLE (pk_webpageId INT);
INSERT INTO @TargetPages (pk_webpageId)
SELECT pk_webpageId FROM dbo.UM_WebPage_Mst 
WHERE parentId = @parentPageId OR pk_webpageId = @parentPageId;

-- Insert into UM_UserPageRights if missing
INSERT INTO dbo.UM_UserPageRights (
    fk_userId,
    fk_webpageId,
    AllowAdd,
    AllowUpdate,
    AllowDelete,
    AllowView
)
SELECT 
    u.fk_userId,
    p.pk_webpageId,
    1, 1, 1, 1
FROM @TargetUsers u
CROSS JOIN @TargetPages p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.UM_UserPageRights r 
    WHERE r.fk_userId = u.fk_userId AND r.fk_webpageId = p.pk_webpageId
);

PRINT 'Page rights successfully granted for Recruitment Reports.';

-- 6. Verification output
SELECT 
    WPM.pk_webpageId,
    WPM.menucaption,
    WPM.pagepath,
    WPM.parentId,
    WPM.displayorder,
    WPM.icon,
    COUNT(UPR.pk_pagerightid) AS AssignedUsersCount
FROM dbo.UM_WebPage_Mst WPM
LEFT JOIN dbo.UM_UserPageRights UPR ON UPR.fk_webpageId = WPM.pk_webpageId
WHERE WPM.parentId = @parentPageId OR WPM.pk_webpageId = @parentPageId
GROUP BY 
    WPM.pk_webpageId,
    WPM.menucaption,
    WPM.pagepath,
    WPM.parentId,
    WPM.displayorder,
    WPM.icon
ORDER BY WPM.parentId, WPM.displayorder;
